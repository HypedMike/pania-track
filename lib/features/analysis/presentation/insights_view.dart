import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/settings/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/toast.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/weather/history.dart';
import '../../../core/rust/analysis/patterns.dart' as rust_patterns;
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/trail.dart';
import '../data/analysis_api.dart';
import 'analysis_widgets.dart';
import 'format.dart';
import 'heatmap_map.dart';

/// The weather is looked up for this many of the most recent trails with times.
const int _weatherTrails = 60;

/// Trails the person walked themselves: recorded or imported, not planned or other people's.
List<Trail> _walked(List<Trail> trails) => [
  for (final t in trails)
    if ((t.source == TrailSource.recorded || t.source == TrailSource.imported) && t.coordinates.length > 1) t,
];

bool _hasTimes(Trail t) => t.coordinates.any((c) => c.timestamp != null);

String _hourLabel(int h) => DateFormat.Hm(I18n.locale).format(DateTime(2024, 1, 1, h));

TrailForAnalysis _input(Trail t, [Map<String, WalkWeather>? weather]) => TrailForAnalysis(
  id: t.id,
  activity: t.activity,
  coordinates: t.coordinates,
  weather: weather?[t.id] == null
      ? null
      : rust_patterns.Weather(tempC: weather![t.id]!.tempC, precipMm: weather[t.id]!.precipMm),
);

/// When and where the person goes out, and how the weather changes their pace.
class InsightsView extends ConsumerStatefulWidget {
  const InsightsView({super.key});

  @override
  ConsumerState<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends ConsumerState<InsightsView> {
  Heatmap? _heatmap;
  Patterns? _patterns;
  Map<String, WalkWeather> _weather = {};
  ({int done, int total})? _lookup;
  String? _error;
  bool _disposed = false;
  List<Trail> _lastMine = const [];

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _compute(List<Trail> mine) async {
    try {
      final heatmap = await AnalysisApi.heatmap([for (final t in mine) _input(t)]);
      if (!_disposed) setState(() => _heatmap = heatmap);
    } catch (e) {
      if (!_disposed) setState(() => _error = '$e');
    }
    await _computePatterns(mine);
  }

  Future<void> _computePatterns(List<Trail> mine) async {
    final timed = mine.where(_hasTimes).toList();
    if (timed.isEmpty) return;
    try {
      final tz = DateTime.now().timeZoneOffset.inMinutes;
      final patterns = await AnalysisApi.patterns([for (final t in timed) _input(t, _weather)], tz);
      if (!_disposed) setState(() => _patterns = patterns);
    } catch (e) {
      if (!_disposed) setState(() => _error = '$e');
    }
  }

  Future<void> _lookUpWeather(List<Trail> mine) async {
    final t = ref.read(tProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final timed = mine.where(_hasTimes).toList()
      ..sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
    final batch = timed.take(_weatherTrails).toList();
    setState(() => _lookup = (done: 0, total: batch.length));
    final found = {..._weather};
    var failures = 0;
    for (var i = 0; i < batch.length; i++) {
      if (_disposed) return;
      try {
        final w = await fetchWalkWeather(batch[i].id, batch[i].coordinates, prefs);
        if (w != null) found[batch[i].id] = w;
      } catch (_) {
        failures++;
        if (failures >= 3) break; // offline, or the service is down: stop asking
      }
      if (!_disposed) setState(() => _lookup = (done: i + 1, total: batch.length));
    }
    if (_disposed) return;
    setState(() {
      _weather = found;
      _lookup = null;
    });
    await _computePatterns(mine);
    if (failures >= 3) AppToast.show(t('insights.weatherFailed'), level: ToastLevel.error);
  }

  String _weatherSentence(Patterns p, TFunction t) {
    final w = p.weather;
    if (w == null) return '';
    final parts = <String>[];
    final corr = w.tempCorrelation;
    if (corr != null) {
      parts.add(
        t(corr <= -0.3 ? 'insights.tempSlows' : (corr >= 0.3 ? 'insights.tempFaster' : 'insights.tempNeutral')),
      );
    } else {
      parts.add(t('insights.tempNotEnough'));
    }
    final wet = w.wetVsDryPct;
    if (wet != null) {
      final pct = wet.abs().round();
      parts.add(
        wet <= -3
            ? t('insights.rainSlower', {'pct': pct})
            : (wet >= 3 ? t('insights.rainFaster', {'pct': pct}) : t('insights.rainSame')),
      );
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final trailsAsync = ref.watch(trailsProvider);
    final mine = _walked(trailsAsync.value ?? const []);
    if (mine.length != _lastMine.length || !_sameIds(mine, _lastMine)) {
      _lastMine = mine;
      if (mine.isNotEmpty) Future.microtask(() => _compute(mine));
    }
    final months = monthNames();
    final weekdays = weekdayNames();
    final timedCount = mine.where(_hasTimes).length;
    final heatmap = _heatmap;
    final patterns = _patterns;
    String? speedHint(Bucket b) => formatSpeedKmh(b.adjustedSpeedMs);

    return PageScaffold(
      onBack: context.goBack,
      backLabel: t('stats.title'),
      body: PageColumn(
        gap: 14,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(t('insights.title'), style: const TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w700)),
          if (_error != null) ErrorText(_error!),
          if (mine.isEmpty && !trailsAsync.isLoading)
            Text(t('insights.empty'), style: TextStyle(fontSize: 14, color: c.muted)),
          if (heatmap != null && heatmap.cells.isNotEmpty)
            AnalysisCard(
              title: t('insights.heatmap'),
              aside: plural(t, 'common.trail', heatmap.trails.toInt()),
              children: [
                SizedBox(
                  height: 288,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: HeatmapMap(heatmap: heatmap),
                  ),
                ),
                FigureRow([
                  Figure(
                    label: t('insights.explored'),
                    value: '${heatmap.exploredKm2.toStringAsFixed(1)} km²',
                    hint: t('insights.cellHint', {'m': heatmap.cellM}),
                  ),
                  Figure(label: t('insights.mostVisited'), value: t('insights.times', {'n': heatmap.maxCount})),
                ]),
                Text(t('insights.heatmapHint'), style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          if (patterns != null && patterns.trails > BigInt.zero) ...[
            AnalysisCard(
              title: t('insights.hours'),
              aside: plural(t, 'common.trail', patterns.trails.toInt()),
              children: [
                BarChart(
                  values: [for (final b in patterns.byHour) b.trails.toDouble()],
                  labels: [for (var h = 0; h < patterns.byHour.length; h++) '$h'],
                  labelEvery: 3,
                  highlight: patterns.busiestHour?.toInt(),
                  semanticLabel: t('insights.hoursAlt'),
                ),
                FigureRow([
                  if (patterns.busiestHour != null)
                    Figure(label: t('insights.busiestHour'), value: _hourLabel(patterns.busiestHour!.toInt())),
                  if (patterns.fastestHour != null)
                    Figure(
                      label: t('insights.fastestHour'),
                      value: _hourLabel(patterns.fastestHour!.toInt()),
                      hint: speedHint(patterns.byHour[patterns.fastestHour!.toInt()]),
                    ),
                ]),
              ],
            ),
            AnalysisCard(
              title: t('insights.weekdays'),
              children: [
                BarChart(
                  values: [for (final b in patterns.byWeekday) b.trails.toDouble()],
                  labels: weekdays,
                  height: 90,
                  semanticLabel: t('insights.weekdaysAlt'),
                ),
              ],
            ),
            AnalysisCard(
              title: t('insights.months'),
              children: [
                BarChart(
                  values: [for (final b in patterns.byMonth) b.distanceM / 1000],
                  labels: months,
                  highlight: patterns.busiestMonth?.toInt(),
                  semanticLabel: t('insights.monthsAlt'),
                ),
                FigureRow([
                  if (patterns.busiestMonth != null)
                    Figure(
                      label: t('insights.busiestMonth'),
                      value: months[patterns.busiestMonth!.toInt()],
                      hint: formatDistance(patterns.byMonth[patterns.busiestMonth!.toInt()].distanceM),
                    ),
                  if (patterns.fastestMonth != null)
                    Figure(
                      label: t('insights.fastestMonth'),
                      value: months[patterns.fastestMonth!.toInt()],
                      hint: speedHint(patterns.byMonth[patterns.fastestMonth!.toInt()]),
                    ),
                ]),
              ],
            ),
            AnalysisCard(
              title: t('insights.weather'),
              children: [
                if (patterns.weather != null) ...[
                  BarChart(
                    values: [for (final b in patterns.weather!.bands) (b.adjustedSpeedMs ?? 0) * 3.6],
                    labels: [
                      for (final b in patterns.weather!.bands)
                        b.fromC == null
                            ? '<${b.toC?.round()}°'
                            : (b.toC == null ? '≥${b.fromC!.round()}°' : '${b.fromC!.round()}–${b.toC!.round()}°'),
                    ],
                    height: 90,
                    semanticLabel: t('insights.weatherAlt'),
                  ),
                  Text(_weatherSentence(patterns, t), style: TextStyle(fontSize: 14, color: c.inkSoft)),
                  Text(
                    t('insights.weatherBasis', {'n': patterns.weather!.trails}),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ] else
                  Text(t('insights.weatherIntro'), style: TextStyle(fontSize: 14, color: c.muted)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SmallButton(
                    label: _lookup != null
                        ? t('insights.lookingUp', {'done': _lookup!.done, 'total': _lookup!.total})
                        : t('insights.lookUp'),
                    onPressed: _lookup != null || timedCount == 0 ? null : () => _lookUpWeather(mine),
                  ),
                ),
                Text(t('insights.weatherPrivacy'), style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ],
          if (mine.isNotEmpty && timedCount == 0)
            Text(t('insights.noTimes'), style: TextStyle(fontSize: 14, color: c.muted)),
        ],
      ),
    );
  }

  bool _sameIds(List<Trail> a, List<Trail> b) {
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
