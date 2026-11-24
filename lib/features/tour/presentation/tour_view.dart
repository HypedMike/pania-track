import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/settings/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../../trail/presentation/trail_map.dart';
import '../application/tour_controller.dart';
import '../domain/tour_guidance.dart';
import '../domain/track_progress.dart';
import '../domain/warning_text.dart';

/// "HH:MM" from a time picker, as the next time the clock shows it.
int nextOccurrence(TimeOfDay time, DateTime now) {
  var target = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
  return target.millisecondsSinceEpoch;
}

class _WarningRow extends StatelessWidget {
  const _WarningRow(this.warning);

  final TourWarning warning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final danger = warning.level == WarningLevel.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? c.danger.withValues(alpha: 0.1) : c.warnTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10),
            child: Icon(Icons.warning_amber_rounded, size: 16, color: danger ? c.danger : c.warnInk),
          ),
          Expanded(
            child: Text(
              warningText(warning),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: danger ? c.danger : c.warnInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Following a trail: the map and, over it, what to do next, when you arrive, and what to watch for.
class TourView extends ConsumerStatefulWidget {
  const TourView({super.key, required this.trailId});

  final String trailId;

  @override
  ConsumerState<TourView> createState() => _TourViewState();
}

class _TourViewState extends ConsumerState<TourView> {
  bool _follow = true;
  int _followKey = 0;
  TimeOfDay? _arriveBy;
  bool _starting = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-render every second so the arrival time and "in 12 min" stay current between fixes.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(tourProvider).trailId == widget.trailId) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final trail = ref.read(trailProvider(widget.trailId));
    if (trail == null) return;
    setState(() => _starting = true);
    final arriveBy = _arriveBy;
    await ref
        .read(tourProvider.notifier)
        .start(trail, arriveBy == null ? null : nextOccurrence(arriveBy, DateTime.now()));
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _finish() async {
    final t = ref.read(tProvider);
    final guidance = ref.read(tourProvider).guidance;
    if (guidance != null && !guidance.arrived) {
      final ok = await confirmDialog(
        context,
        message: t('tour.confirmStop'),
        confirmLabel: t('tour.stop'),
        cancelLabel: t('common.cancel'),
      );
      if (!ok) return;
    }
    // A tour that was recorded is shown next to its plan; one that was not kept goes back to the trail.
    final runId = await ref.read(tourProvider.notifier).stop();
    if (!mounted) return;
    context.goTo(runId != null ? Routes.tourReview(runId) : Routes.trailDetail(widget.trailId), replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final trails = ref.watch(trailsProvider);
    final trail = ref.watch(trailProvider(widget.trailId));
    final tour = ref.watch(tourProvider);
    final offTrackThreshold = ref.watch(settingsProvider.select((s) => s.offTrackM));
    final startedHere = tour.active && tour.trailId == widget.trailId;

    if (trail == null || trail.coordinates.length < 2) {
      return PageScaffold(
        onBack: context.goBack,
        backLabel: t('detail.trails'),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            trail == null && trails.isLoading ? t('common.loading') : t('detail.notFound'),
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    }

    if (tour.active && !startedHere) {
      final other = ref.watch(trailProvider(tour.trailId ?? ''));
      return PageScaffold(
        onBack: context.goBack,
        backLabel: t('detail.trails'),
        body: PageColumn(
          gap: 16,
          children: [
            Text(t('tour.otherActive', {'name': other?.name ?? '…'}), style: const TextStyle(fontSize: 15)),
            PrimaryButton(
              label: t('tour.openActive'),
              onPressed: () => context.goTo(Routes.tour(tour.trailId!), replace: true),
            ),
          ],
        ),
      );
    }

    final guidance = tour.guidance;
    final current = tour.current;
    final index = buildTrackIndex([for (final p in trail.coordinates) latLonOf(p)]);
    final completed = startedHere && guidance != null
        ? [
            for (final p in trackUpTo(index, guidance.alongM))
              GpsCoordinate(latitude: p.latitude, longitude: p.longitude),
          ]
        : const <GpsCoordinate>[];
    final guideLine = startedHere && current != null && guidance != null && guidance.offTrackM > 15
        ? [current, GpsCoordinate(latitude: guidance.nearest.latitude, longitude: guidance.nearest.longitude)]
        : const <GpsCoordinate>[];

    // What the sheet says.
    var instruction = t('tour.gpsWaiting');
    String? detail;
    double? arrowDeg;
    if (guidance != null) {
      arrowDeg = guidance.bearing;
      if (guidance.arrived) {
        instruction = t('tour.arrived');
      } else if (guidance.offTrackM > offTrackThreshold) {
        instruction = t('tour.offTrack');
        detail = t('tour.headTo', {
          'dir': t('tour.dir.${compassPoint(guidance.bearing)}'),
          'd': formatDistance(guidance.offTrackM),
        });
      } else if (guidance.turn != null) {
        final turn = guidance.turn!;
        final key = turn.direction == TurnDirection.left
            ? (turn.sharp ? 'tour.sharpLeft' : 'tour.turnLeft')
            : (turn.sharp ? 'tour.sharpRight' : 'tour.turnRight');
        instruction = t(key, {'d': formatDistance(turn.inM)});
      } else {
        instruction = t('tour.straight');
      }
      if (detail == null && guidance.nextWaypoint != null && !guidance.arrived) {
        detail = t('tour.nextWaypoint', {
          'name': guidance.nextWaypoint!.name,
          'd': formatDistance(guidance.nextWaypoint!.inM),
        });
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final etaSub = guidance != null && !guidance.arrived
        ? t('tour.etaIn', {'d': formatDuration(guidance.etaMs - now)})
        : null;
    final accuracy = current?.accuracy != null ? 'GPS ±${current!.accuracy!.round()} m' : 'GPS …';
    final offTrackNow = guidance != null && guidance.offTrackM > offTrackThreshold;

    return MapSheetScreen(
      sheetFraction: 0.52,
      centerTooltip: t('tour.centerMap'),
      onCenter: startedHere
          ? () => setState(() {
              _follow = true;
              _followKey++;
            })
          : null,
      map: TrailMap(
        coordinates: trail.coordinates,
        waypoints: trail.waypoints,
        source: trail.source,
        completed: completed,
        guideLine: guideLine,
        current: startedHere ? current : null,
        fit: !(startedHere && current != null),
        follow: _follow,
        followKey: _followKey,
        onUserMove: () {
          if (_follow) setState(() => _follow = false);
        },
      ),
      leftChip: Flexible(
        child: MapChip(
          label: trail.name,
          onTap: context.goBack,
          leading: startedHere ? StatusDot(color: c.brand) : null,
        ),
      ),
      rightChip: startedHere ? MapChip(label: accuracy) : null,
      sheet: startedHere
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: offTrackNow ? c.danger.withValues(alpha: 0.1) : c.brandTint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: arrowDeg == null
                          ? Center(child: StatusDot(color: c.brandTintInk, size: 12))
                          : guidance!.arrived
                          ? Icon(Icons.check, size: 30, color: c.brandTintInk)
                          : Center(
                              child: AnimatedRotation(
                                turns: arrowDeg / 360,
                                duration: const Duration(milliseconds: 400),
                                child: Icon(Icons.navigation, size: 34, color: offTrackNow ? c.danger : c.brandTintInk),
                              ),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            instruction,
                            style: const TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w600),
                          ),
                          if (detail != null) Text(detail, style: TextStyle(fontSize: 13, color: c.inkSoft)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Metric(
                        label: t('tour.remaining'),
                        value: guidance != null ? formatDistance(guidance.remainingM) : '—',
                      ),
                    ),
                    Expanded(
                      child: Metric(
                        label: t('tour.eta'),
                        value: guidance != null ? formatTimeOfDay(guidance.etaMs) : '—',
                        sub: etaSub,
                      ),
                    ),
                    Expanded(
                      child: Metric(
                        label: t('tour.speed'),
                        value: tour.liveSpeedMs != null ? formatSpeed(tour.liveSpeedMs!) : '—',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: math.min(1.0, (guidance?.progressPct ?? 0) / 100),
                    minHeight: 6,
                    backgroundColor: c.canvas,
                    color: c.brand,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t('tour.progress', {'pct': (guidance?.progressPct ?? 0).round()})}'
                  '${tour.targetArrivalMs != null ? ' · ${t('tour.target', {'time': formatTimeOfDay(tour.targetArrivalMs!)})}' : ''}',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                const SizedBox(height: 14),
                Text(t('tour.warnings'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (tour.warnings.isNotEmpty)
                  for (final w in tour.warnings) ...[_WarningRow(w), const SizedBox(height: 8)]
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(12)),
                    child: Text(t('tour.noWarnings'), style: TextStyle(fontSize: 13, color: c.inkSoft)),
                  ),
                if (tour.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: ErrorText(tour.error!)),
                const SizedBox(height: 4),
                Text(t('tour.weatherNote'), style: TextStyle(fontSize: 12, color: c.muted)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _finish,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.danger,
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.stop, size: 18),
                  label: Text(guidance?.arrived == true ? t('tour.finish') : t('tour.stop')),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('tour.title'), style: const TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(t('tour.setupHint'), style: TextStyle(fontSize: 14, color: c.inkSoft)),
                const SizedBox(height: 14),
                Text(t('tour.arriveBy'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _arriveBy ?? TimeOfDay.now(),
                          );
                          if (picked != null) setState(() => _arriveBy = picked);
                        },
                        child: Text(_arriveBy == null ? '--:--' : _arriveBy!.format(context)),
                      ),
                    ),
                    if (_arriveBy != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        onPressed: () => setState(() => _arriveBy = null),
                        child: Text(
                          t('tour.arriveByClear'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(t('tour.arriveByHint'), style: TextStyle(fontSize: 12, color: c.muted)),
                if (tour.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: ErrorText(tour.error!)),
                const SizedBox(height: 16),
                PrimaryButton(
                  icon: Icons.play_arrow,
                  label: _starting ? t('tour.starting') : t('tour.begin'),
                  onPressed: _starting ? null : _begin,
                ),
              ],
            ),
    );
  }
}
