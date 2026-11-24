import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/terrain.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/toast.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../../trail/domain/trail.dart';
import '../../trail/presentation/trail_map.dart';
import '../application/analysis_providers.dart';
import '../data/analysis_api.dart';
import 'analysis_widgets.dart';
import 'format.dart';

/// Replay length: the whole trail plays in about this many seconds, however long it was.
const int _replaySeconds = 20;
const int _replayTickMs = 100;

class TrailAnalysisView extends ConsumerStatefulWidget {
  const TrailAnalysisView({super.key, required this.trailId});

  final String trailId;

  @override
  ConsumerState<TrailAnalysisView> createState() => _TrailAnalysisViewState();
}

class _TrailAnalysisViewState extends ConsumerState<TrailAnalysisView> {
  Cleaned? _cleaned;
  bool _cleaning = false;
  int _cursor = 0;
  bool _playing = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _togglePlay(int count) {
    if (_playing) {
      _timer?.cancel();
      setState(() => _playing = false);
      return;
    }
    if (_cursor >= count - 1) _cursor = 0;
    final stepBy = math.max(1, (count / (_replaySeconds * 1000 / _replayTickMs)).round());
    _timer = Timer.periodic(const Duration(milliseconds: _replayTickMs), (timer) {
      setState(() {
        if (_cursor + stepBy >= count - 1) {
          _cursor = count - 1;
          _playing = false;
          timer.cancel();
        } else {
          _cursor += stepBy;
        }
      });
    });
    setState(() => _playing = true);
  }

  Future<void> _previewClean(Trail trail, bool withTerrain) async {
    final t = ref.read(tProvider);
    setState(() => _cleaning = true);
    try {
      final terrain = withTerrain ? await fetchTerrainElevations(trail.coordinates) : null;
      final cleaned = await AnalysisApi.cleanTrack(trail.coordinates, trail.activity, terrain: terrain);
      if (mounted) setState(() => _cleaned = cleaned);
    } catch (e) {
      AppToast.show(
        withTerrain ? t('analysis.terrainFailed') : t('analysis.cleanFailed'),
        description: '$e'.replaceFirst('Exception: ', ''),
        level: ToastLevel.error,
      );
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _saveCleaned(Trail trail) async {
    final t = ref.read(tProvider);
    final cleaned = _cleaned;
    if (cleaned == null) return;
    final ok = await confirmDialog(
      context,
      message: t('analysis.confirmSaveCleaned'),
      confirmLabel: t('analysis.saveCleaned'),
      cancelLabel: t('common.cancel'),
    );
    if (!ok) return;
    try {
      await ref.read(trailsProvider.notifier).updateTrail(trail.copyWith(coordinates: fromFixes(cleaned.fixes)));
      if (!mounted) return;
      setState(() {
        _cleaned = null;
        _cursor = 0;
      });
      AppToast.show(t('analysis.cleanSaved'), level: ToastLevel.success);
    } catch (e) {
      AppToast.show('$e', level: ToastLevel.error);
    }
  }

  Future<void> _addStop(Trail trail, TrailAnalysis analysis, int i) async {
    final t = ref.read(tProvider);
    final stop = analysis.motion.stops[i];
    final name = t('analysis.stopName', {'d': formatSeconds(stop.durationS)});
    try {
      await ref
          .read(trailsProvider.notifier)
          .updateTrail(
            trail.copyWith(
              waypoints: [
                ...trail.waypoints,
                Waypoint(latitude: stop.latitude, longitude: stop.longitude, name: name),
              ],
            ),
          );
      AppToast.show(t('analysis.waypointAdded'), level: ToastLevel.success);
    } catch (e) {
      AppToast.show('$e', level: ToastLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final trails = ref.watch(trailsProvider);
    final trail = ref.watch(trailProvider(widget.trailId));

    if (trail == null) {
      return PageScaffold(
        onBack: context.goBack,
        backLabel: t('analysis.back'),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              trails.isLoading ? t('common.loading') : t('error.trailNotFound'),
              style: TextStyle(color: c.muted),
            ),
          ),
        ),
      );
    }

    final analysisAsync = ref.watch(trailAnalysisProvider(widget.trailId));
    final analysis = analysisAsync.value;
    final groups = ref.watch(sameRouteProvider(widget.trailId)).value ?? const <RouteGroup>[];
    final coordinates = trail.coordinates;
    final count = coordinates.length;
    final distances = <double>[];
    var total = 0.0;
    for (var i = 0; i < count; i++) {
      if (i > 0) total += haversine(coordinates[i - 1], coordinates[i]);
      distances.add(total);
    }
    final ownTrail = trail.source != TrailSource.bookmarked;
    final motion = analysis?.motion;
    final at = math.min(_cursor, math.max(0, count - 1));
    final here = count > 0 ? coordinates[at] : null;
    final hereTime = here?.timestamp?.millisecondsSinceEpoch;
    final startTime = coordinates.isNotEmpty ? coordinates.first.timestamp?.millisecondsSinceEpoch : null;
    final allTrails = trails.value ?? const <Trail>[];

    return PageScaffold(
      onBack: context.goBack,
      backLabel: t('analysis.back'),
      body: PageColumn(
        gap: 14,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('analysis.title'),
                style: const TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w700),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                onPressed: () => context.goTo(Routes.trailDetail(trail.id)),
                child: Text(trail.name),
              ),
            ],
          ),
          if (analysisAsync.hasError) ErrorText('${analysisAsync.error}'),
          if (analysis == null && !analysisAsync.hasError)
            Text(t('analysis.working'), style: TextStyle(fontSize: 14, color: c.muted)),
          if (count > 1)
            AnalysisCard(
              title: t('analysis.replay'),
              aside: formatDistance(distances.last),
              children: [
                SizedBox(
                  height: 224,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: TrailMap(
                      coordinates: coordinates,
                      source: trail.source,
                      completed: coordinates.sublist(0, at + 1),
                      current: here,
                    ),
                  ),
                ),
                ProfileChart(
                  distances: distances,
                  altitudes: [for (final p in coordinates) p.altitude],
                  segments: analysis?.climbs?.segments ?? const [],
                  stops: motion?.stops ?? const [],
                  cursor: at,
                  semanticLabel: t('analysis.profileAlt'),
                ),
                Row(
                  children: [
                    SmallButton(
                      primary: true,
                      label: _playing ? t('analysis.pause') : t('analysis.play'),
                      onPressed: () => _togglePlay(count),
                    ),
                    Expanded(
                      child: Slider(
                        value: at.toDouble(),
                        min: 0,
                        max: (count - 1).toDouble(),
                        semanticFormatterCallback: (_) => t('analysis.position'),
                        onChanged: (v) {
                          _timer?.cancel();
                          setState(() {
                            _playing = false;
                            _cursor = v.round();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                FigureRow([
                  Figure(label: t('common.distance'), value: formatDistance(distances[at])),
                  Figure(label: t('analysis.altitude'), value: formatElevation(here?.altitude)),
                  Figure(
                    label: t('analysis.elapsed'),
                    value: hereTime != null && startTime != null ? formatSeconds((hereTime - startTime) / 1000) : '—',
                    hint: hereTime != null ? formatClockTime(hereTime) : null,
                  ),
                ]),
              ],
            ),
          if (motion != null)
            if (motion.hasTime)
              AnalysisCard(
                title: t('analysis.time'),
                children: [
                  FigureRow([
                    Figure(label: t('analysis.moving'), value: formatSeconds(motion.movingS)),
                    Figure(label: t('analysis.stopped'), value: formatSeconds(motion.stoppedS)),
                    Figure(
                      label: t('analysis.paused'),
                      value: formatSeconds(motion.pausedS),
                      hint: t('analysis.pausedHint'),
                    ),
                  ]),
                  FigureRow([
                    Figure(label: t('analysis.movingSpeed'), value: formatSpeedKmh(motion.avgMovingSpeedMs)),
                    Figure(
                      label: t('analysis.adjustedSpeed'),
                      value: formatSpeedKmh(analysis?.adjustedSpeedMs),
                      hint: t('analysis.adjustedHint'),
                    ),
                  ]),
                  if (motion.stops.isNotEmpty)
                    Column(
                      children: [
                        for (var i = 0; i < motion.stops.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: c.line),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${formatSeconds(motion.stops[i].durationS)} · ${formatDistance(motion.stops[i].alongM)}',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        motion.stops[i].startMs != null
                                            ? formatClockTime(motion.stops[i].startMs!.toInt())
                                            : '',
                                        style: TextStyle(fontSize: 12, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (ownTrail)
                                  SmallButton(
                                    label: t('analysis.addWaypoint'),
                                    onPressed: () => _addStop(trail, analysis!, i),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Text(t('analysis.noStops'), style: TextStyle(fontSize: 14, color: c.muted)),
                ],
              )
            else
              AnalysisCard(
                title: t('analysis.time'),
                children: [Text(t('analysis.noTimes'), style: TextStyle(fontSize: 14, color: c.muted))],
              ),
          if (analysis != null && analysis.curve.legsUsed > BigInt.zero)
            AnalysisCard(
              title: t('analysis.pace'),
              aside: t('analysis.paceAxis'),
              children: [
                PaceCurve(model: analysis.curve, semanticLabel: t('analysis.paceAlt')),
                Text(t('analysis.paceLegend'), style: TextStyle(fontSize: 12, color: c.muted)),
                _PaceNotes(model: analysis.curve, t: t),
              ],
            ),
          if (analysis?.climbs != null) _climbsCard(analysis!.climbs!, t, c),
          if (analysis?.fatigue != null) _fatigueCard(analysis!.fatigue!, t, c),
          if (analysis != null) _qualityCard(trail, analysis, ownTrail, t, c),
          if (groups.isNotEmpty)
            AnalysisCard(
              title: t('analysis.sameRoute'),
              children: [
                for (final g in groups)
                  Column(
                    children: [
                      for (final m in ([
                        ...g.members,
                      ]..sort((a, b) => (a.movingS ?? double.infinity).compareTo(b.movingS ?? double.infinity))))
                        Builder(
                          builder: (context) {
                            final other = allTrails.where((x) => x.id == m.id).firstOrNull;
                            final started = m.startMs != null
                                ? DateTime.fromMillisecondsSinceEpoch(m.startMs!.toInt())
                                : other?.createdAt;
                            return InkWell(
                              onTap: () => m.id != trail.id ? context.goTo(Routes.trailDetail(m.id)) : null,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 44),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${other?.name ?? m.id}${m.isBest ? ' · ${t('analysis.best')}' : ''}${m.id == trail.id ? ' · ${t('analysis.thisOne')}' : ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: m.id == trail.id ? FontWeight.w600 : FontWeight.w400,
                                            ),
                                          ),
                                          Text(
                                            '${formatDate(started)}${m.reversed ? ' · ${t('analysis.reversed')}' : ''}',
                                            style: TextStyle(fontSize: 12, color: c.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          formatSeconds(m.movingS),
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          m.vsBestPct == null
                                              ? ''
                                              : (m.isBest
                                                    ? t('analysis.best')
                                                    : '+${m.vsBestPct!.toStringAsFixed(0)}%'),
                                          style: TextStyle(fontSize: 12, color: c.muted),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _climbsCard(Climbs climbs, TFunction t, AppColors c) {
    return AnalysisCard(
      title: t('analysis.climbs'),
      children: [
        FigureRow([
          Figure(label: t('detail.gain'), value: formatElevation(climbs.totalGainM, signed: true)),
          Figure(label: t('analysis.loss'), value: formatElevation(-climbs.totalLossM)),
          Figure(label: t('analysis.vertSpeed'), value: formatVerticalSpeed(climbs.avgVerticalSpeedMh)),
        ]),
        if (climbs.steepestClimbKm != null || climbs.steepestDescentKm != null)
          FigureRow([
            if (climbs.steepestClimbKm != null)
              Figure(
                label: t('analysis.steepestUp'),
                value: formatGrade(climbs.steepestClimbKm!.gradePct),
                hint: t('analysis.atKm', {'d': formatDistance(climbs.steepestClimbKm!.startM)}),
              ),
            if (climbs.steepestDescentKm != null)
              Figure(
                label: t('analysis.steepestDown'),
                value: formatGrade(climbs.steepestDescentKm!.gradePct),
                hint: t('analysis.atKm', {'d': formatDistance(climbs.steepestDescentKm!.startM)}),
              ),
          ]),
        Column(
          children: [
            for (var i = 0; i < climbs.segments.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.line),
              Builder(
                builder: (context) {
                  final s = climbs.segments[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t('analysis.kind.${s.kind.name}')} · ${formatDistance(s.distanceM)}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${formatDistance(s.startM)} → ${formatDistance(s.endM)}${s.durationS != null && s.durationS! > 0 ? ' · ${formatSeconds(s.durationS)}' : ''}',
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatGrade(s.avgGradePct),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              s.kind == SegmentKind.climb && s.verticalSpeedMh != null && s.verticalSpeedMh! > 0
                                  ? formatVerticalSpeed(s.verticalSpeedMh)
                                  : formatElevation(s.riseM, signed: true),
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _fatigueCard(Fatigue f, TFunction t, AppColors c) {
    String sentence() {
      final pct = f.changePct;
      if (pct <= -15) return t('analysis.fatigueBig', {'pct': pct.abs().round()});
      if (pct <= -5) return t('analysis.fatigueSome', {'pct': pct.abs().round()});
      if (pct >= 5) return t('analysis.fatigueFaster', {'pct': pct.round()});
      return t('analysis.fatigueSteady');
    }

    return AnalysisCard(
      title: t('analysis.fatigue'),
      children: [
        BarChart(
          values: [f.firstAdjustedMs * 3.6, f.lastAdjustedMs * 3.6],
          labels: [t('analysis.firstThird'), t('analysis.lastThird')],
          tones: [Tone.brand, f.changePct < -5 ? Tone.bad : Tone.brand],
          height: 80,
          semanticLabel: t('analysis.fatigueAlt'),
        ),
        FigureRow([
          Figure(label: t('analysis.firstThird'), value: formatSpeedKmh(f.firstSpeedMs)),
          Figure(label: t('analysis.lastThird'), value: formatSpeedKmh(f.lastSpeedMs)),
          Figure(label: t('analysis.change'), value: '${f.changePct > 0 ? '+' : ''}${f.changePct.toStringAsFixed(0)}%'),
        ]),
        Text(sentence(), style: TextStyle(fontSize: 14, color: c.inkSoft)),
        if (!f.gradeAdjusted) Text(t('analysis.noAltitudeNote'), style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }

  Widget _qualityCard(Trail trail, TrailAnalysis analysis, bool ownTrail, TFunction t, AppColors c) {
    final q = analysis.quality;
    final cleaned = _cleaned;
    return AnalysisCard(
      title: t('analysis.quality'),
      aside: '${q.score}/100',
      children: [
        FigureRow([
          Figure(label: t('analysis.spikes'), value: '${q.spikes}'),
          Figure(label: t('analysis.altJumps'), value: '${q.altitudeJumps}'),
          Figure(
            label: t('analysis.gaps'),
            value: '${q.gaps}',
            hint: q.gaps > BigInt.zero ? t('analysis.longest', {'d': formatSeconds(q.longestGapS)}) : null,
          ),
        ]),
        if (q.accuracy != null)
          FigureRow([
            Figure(label: t('analysis.accMedian'), value: '${q.accuracy!.medianM.toStringAsFixed(0)} m'),
            Figure(label: t('analysis.accP95'), value: '${q.accuracy!.p95M.toStringAsFixed(0)} m'),
            Figure(label: t('analysis.accPoor'), value: '${q.accuracy!.poorPct.toStringAsFixed(0)}%'),
          ])
        else
          Text(t('analysis.noAccuracy'), style: TextStyle(fontSize: 12, color: c.muted)),
        Text(
          q.suspicious ? t('analysis.qualityBad') : t('analysis.qualityGood'),
          style: TextStyle(fontSize: 14, color: c.inkSoft),
        ),
        if (ownTrail && cleaned == null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SmallButton(label: t('analysis.clean'), onPressed: _cleaning ? null : () => _previewClean(trail, false)),
              if (q.withAltitudePct > 0)
                SmallButton(
                  label: _cleaning ? t('analysis.working') : t('analysis.terrain'),
                  onPressed: _cleaning ? null : () => _previewClean(trail, true),
                ),
            ],
          ),
        if (cleaned != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('analysis.cleanResult', {
                    'removed': cleaned.removedPoints,
                    'before': formatElevation(cleaned.gainBeforeM, signed: true),
                    'after': formatElevation(cleaned.gainAfterM, signed: true),
                  }),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    SmallButton(primary: true, label: t('analysis.saveCleaned'), onPressed: () => _saveCleaned(trail)),
                    SmallButton(label: t('common.cancel'), onPressed: () => setState(() => _cleaned = null)),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the curve says in words: the speed on the slopes the person actually walked.
class _PaceNotes extends StatelessWidget {
  const _PaceNotes({required this.model, required this.t});

  final PaceModel model;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    CurveBin? at(double pct) => model.bins.where((b) => (b.gradePct - pct).abs() < 0.1).firstOrNull;
    final rows = [
      (10.0, t('analysis.uphill')),
      (0.0, t('analysis.flat')),
      (-10.0, t('analysis.downhill')),
    ].where((r) => at(r.$1)?.measured == true).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return FigureRow([for (final r in rows) Figure(label: r.$2, value: formatSpeedKmh(at(r.$1)!.speedMs))]);
  }
}
