import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/application/trail_controller.dart';
import '../domain/stats_summary.dart';

String _periodSubtitle(Period period, DateTime now, TFunction t) {
  final locale = I18n.locale;
  switch (period) {
    case Period.week:
      final start = periodRange(Period.week, now).start!;
      final fmt = DateFormat.MMMd(locale);
      return '${fmt.format(start)} – ${fmt.format(addDays(start, 6))}';
    case Period.month:
      return DateFormat.yMMMM(locale).format(now);
    case Period.year:
      return '${now.year}';
    case Period.all:
      return t('stats.subtitleAll');
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.muted)),
      Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.aside});
  final String title;
  final String? aside;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (aside != null) Text(aside!, style: TextStyle(fontSize: 13, color: context.colors.muted)),
        ],
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

/// The Stats tab: totals, charts, averages and records for a week, month, year or everything.
class StatsView extends ConsumerStatefulWidget {
  const StatsView({super.key});

  @override
  ConsumerState<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends ConsumerState<StatsView> {
  Period _period = Period.month;
  final DateTime _now = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final trails = ref.watch(trailsProvider).value ?? const [];
    final entries = toEntries(trails);
    final inPeriod = filterByPeriod(entries, _period, _now);
    final summary = summarize(inPeriod);
    final buckets = buildBuckets(_period, inPeriod, _now);
    final range = periodRange(_period, _now);
    final today = startOfDay(_now);
    final showCalendar = _period == Period.week || _period == Period.month;
    final elapsedDays = range.start != null && showCalendar ? today.difference(range.start!).inDays + 1 : 0;
    final r = summary.records;
    final recordRows = [
      (t('stats.recLongest'), r.longest, formatDistance(r.longest?.stats.distanceM ?? 0)),
      (t('stats.recClimb'), r.climb, formatElevation(r.climb?.stats.elevationGainM, signed: true)),
      (t('stats.recHighest'), r.highest, formatElevation(r.highest?.stats.highestM)),
      (t('stats.recTime'), r.time, formatDuration(r.time?.stats.durationMs)),
    ].where((row) => row.$2 != null).toList();
    final splitTotal = summary.recorded.distanceM + summary.imported.distanceM;
    final recordedPct = splitTotal > 0 ? (summary.recorded.distanceM / splitTotal * 100).round() : 0;

    const periodLabels = {
      Period.week: 'stats.week',
      Period.month: 'stats.month',
      Period.year: 'stats.year',
      Period.all: 'stats.all',
    };

    Widget bigTile(String label, String value) => Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return PageColumn(
      children: [
        LargeTitle(t('stats.title'), subtitle: _periodSubtitle(_period, _now, t)),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              for (final p in Period.values)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _period = p),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p == _period ? c.ink : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        t(periodLabels[p]!),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: p == _period ? FontWeight.w600 : FontWeight.w500,
                          color: p == _period ? c.onInk : c.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            bigTile(t('common.distance'), formatDistance(summary.distanceM)),
            bigTile(t('common.elevationGain'), formatElevation(summary.count > 0 ? summary.gainM : null, signed: true)),
            bigTile(t('stats.movingTime'), formatDuration(summary.movingMs > 0 ? summary.movingMs : null)),
            bigTile(t('stats.trails'), '${summary.count}'),
          ],
        ),
        if (summary.count == 0)
          Panel(
            padding: const EdgeInsets.all(20),
            child: Text(
              t('stats.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          )
        else ...[
          DistanceChart(period: _period, buckets: buckets, t: t),
          _Section(
            title: t('stats.averages'),
            child: Panel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(child: _SmallStat(t('common.distance'), formatDistance(summary.avgDistanceM))),
                  Expanded(child: _SmallStat(t('detail.gain'), formatElevation(summary.avgGainM, signed: true))),
                  Expanded(
                    child: _SmallStat(
                      t('stats.speed'),
                      summary.avgSpeedKmh == null ? '—' : '${summary.avgSpeedKmh!.toStringAsFixed(1)} km/h',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (recordRows.isNotEmpty)
            _Section(
              title: t('stats.records'),
              child: Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < recordRows.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: c.line),
                      InkWell(
                        onTap: () => context.goTo(Routes.trailDetail(recordRows[i].$2!.trail.id)),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(recordRows[i].$1, style: TextStyle(fontSize: 13, color: c.muted)),
                                    Text(
                                      recordRows[i].$2!.trail.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(recordRows[i].$3, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          _Section(
            title: t('stats.split'),
            child: Panel(
              child: Column(
                children: [
                  Semantics(
                    label: t('stats.splitAlt', {'recorded': recordedPct, 'imported': 100 - recordedPct}),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        height: 14,
                        child: Row(
                          children: [
                            if (summary.recorded.distanceM > 0)
                              Expanded(
                                flex: summary.recorded.distanceM.round().clamp(1, 1 << 30),
                                child: ColoredBox(color: c.brand, child: const SizedBox.expand()),
                              ),
                            if (summary.recorded.distanceM > 0 && summary.imported.distanceM > 0)
                              const SizedBox(width: 3),
                            if (summary.imported.distanceM > 0)
                              Expanded(
                                flex: summary.imported.distanceM.round().clamp(1, 1 << 30),
                                child: ColoredBox(color: c.route, child: const SizedBox.expand()),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SmallStat(
                          t('stats.recordedCount', {'trails': plural(t, 'common.trail', summary.recorded.count)}),
                          formatDistance(summary.recorded.distanceM),
                        ),
                      ),
                      Expanded(
                        child: _SmallStat(
                          t('stats.importedCount', {'trails': plural(t, 'common.trail', summary.imported.count)}),
                          formatDistance(summary.imported.distanceM),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (showCalendar && range.start != null && range.end != null)
            _Section(
              title: t('stats.activeDays'),
              aside: t('stats.activeOf', {'n': summary.activeDays.length, 'total': elapsedDays}),
              child: ActivityCalendar(
                start: range.start!,
                end: range.end!,
                now: _now,
                activeDays: summary.activeDays,
                t: t,
              ),
            ),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.goTo(Routes.insights),
          child: Panel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('insights.open'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(t('insights.openHint'), style: TextStyle(fontSize: 14, color: c.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Monday-first grid of days; active days are filled, today is outlined.
class ActivityCalendar extends StatelessWidget {
  const ActivityCalendar({
    super.key,
    required this.start,
    required this.end,
    required this.now,
    required this.activeDays,
    required this.t,
  });

  /// First day shown and the first day after the last one shown.
  final DateTime start;
  final DateTime end;
  final DateTime now;
  final Set<String> activeDays;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = I18n.locale;
    final today = startOfDay(now);
    final leading = (start.weekday - 1) % 7;
    final days = <DateTime?>[for (var i = 0; i < leading; i++) null];
    for (var d = start; d.isBefore(end); d = addDays(d, 1)) {
      days.add(d);
    }
    final monday = startOfWeek(now);
    final weekdays = [
      for (var i = 0; i < 7; i++) DateFormat.E(locale).format(addDays(monday, i)).characters.first.toUpperCase(),
    ];
    final activeList = [
      for (final d in days)
        if (d != null && activeDays.contains(dayKey(d))) DateFormat.MMMd(locale).format(d),
    ].join(', ');
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Center(
                    child: Text(w, style: TextStyle(fontSize: 12, color: c.muted)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '${t('stats.calendarAlt')} $activeList',
            child: GridView.count(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              mainAxisExtent: 38,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final d in days)
                  if (d == null)
                    const SizedBox.shrink()
                  else
                    Builder(
                      builder: (context) {
                        final active = activeDays.contains(dayKey(d));
                        final isToday = d == today;
                        final future = d.isAfter(today);
                        return Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? c.brand : (future ? null : c.line),
                            borderRadius: BorderRadius.circular(10),
                            border: isToday ? Border.all(color: c.ink, width: 2) : null,
                          ),
                          child: Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active || isToday ? FontWeight.w600 : FontWeight.w400,
                              color: active ? Colors.white : (future ? c.muted : c.inkSoft),
                            ),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Distance per day, week, month or year, split by recorded and imported.
class DistanceChart extends StatelessWidget {
  const DistanceChart({super.key, required this.period, required this.buckets, required this.t});

  final Period period;
  final List<Bucket> buckets;
  final TFunction t;

  static const double _barAreaPx = 110;
  static const double _minBarPx = 4;
  static const int _maxLabelledBars = 7;

  String _label(DateTime start) {
    final locale = I18n.locale;
    switch (period) {
      case Period.week:
        return DateFormat.E(locale).format(start);
      case Period.month:
        return DateFormat.MMMd(locale).format(start);
      case Period.year:
        return DateFormat.MMM(locale).format(start).characters.first.toUpperCase();
      case Period.all:
        return '${start.year}';
    }
  }

  String _km(double m) => (m / 1000).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxV = buckets.fold<double>(0, (m, b) => m > b.recordedM + b.importedM ? m : b.recordedM + b.importedM);
    final showValues = buckets.length <= _maxLabelledBars;
    final title = t('stats.chart.${period.name}');
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text('km', style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (showValues)
                            Text(
                              (b.recordedM + b.importedM) > 0 ? _km(b.recordedM + b.importedM) : '0',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkSoft),
                            ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final total = b.recordedM + b.importedM;
                              final height = total > 0
                                  ? (total / maxV * _barAreaPx).round().clamp(_minBarPx, _barAreaPx).toDouble()
                                  : _minBarPx;
                              return ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(2),
                                ),
                                child: SizedBox(
                                  height: height,
                                  child: total == 0
                                      ? ColoredBox(color: c.lineStrong, child: const SizedBox.expand())
                                      : Column(
                                          children: [
                                            if (b.importedM > 0)
                                              Expanded(
                                                flex: b.importedM.round().clamp(1, 1 << 30),
                                                child: ColoredBox(color: c.route, child: const SizedBox.expand()),
                                              ),
                                            if (b.recordedM > 0)
                                              Expanded(
                                                flex: b.recordedM.round().clamp(1, 1 << 30),
                                                child: ColoredBox(color: c.brand, child: const SizedBox.expand()),
                                              ),
                                          ],
                                        ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _label(b.start),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(fontSize: 12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatusDot(color: c.brand, size: 10),
              const SizedBox(width: 6),
              Text(t('trail.sourceRecorded'), style: TextStyle(fontSize: 12, color: c.inkSoft)),
              const SizedBox(width: 16),
              StatusDot(color: c.route, size: 10),
              const SizedBox(width: 6),
              Text(t('trail.sourceImported'), style: TextStyle(fontSize: 12, color: c.inkSoft)),
            ],
          ),
        ],
      ),
    );
  }
}
