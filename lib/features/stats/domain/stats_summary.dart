import 'dart:math' as math;

import '../../../core/gps/trail_stats.dart';
import '../../trail/domain/trail.dart';

enum Period { week, month, year, all }

class TrailEntry {
  const TrailEntry({required this.trail, required this.stats, required this.date});

  final Trail trail;
  final TrailStats stats;

  /// When the trail was walked: first GPS timestamp, falling back to when it was saved.
  final DateTime? date;
}

class Bucket {
  Bucket(this.start, this.end);

  final DateTime start;
  final DateTime end;
  double recordedM = 0;
  double importedM = 0;
}

class Records {
  const Records({this.longest, this.climb, this.highest, this.time});

  final TrailEntry? longest;
  final TrailEntry? climb;
  final TrailEntry? highest;
  final TrailEntry? time;
}

class SourceTotals {
  int count = 0;
  double distanceM = 0;
}

class PeriodSummary {
  const PeriodSummary({
    required this.count,
    required this.distanceM,
    required this.gainM,
    required this.movingMs,
    required this.avgDistanceM,
    required this.avgGainM,
    required this.avgSpeedKmh,
    required this.records,
    required this.recorded,
    required this.imported,
    required this.activeDays,
  });

  final int count;
  final double distanceM;
  final double gainM;
  final int movingMs;
  final double avgDistanceM;
  final double? avgGainM;
  final double? avgSpeedKmh;
  final Records records;
  final SourceTotals recorded;
  final SourceTotals imported;

  /// Local-date keys (see [dayKey]) of days with at least one trail.
  final Set<String> activeDays;
}

const int _maxYearBars = 6;

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Weeks start on Monday.
DateTime startOfWeek(DateTime d) {
  final s = startOfDay(d);
  return addDays(s, -(s.weekday - 1));
}

String dayKey(DateTime d) => '${d.year}-${d.month - 1}-${d.day}';

/// Planned trails were not walked, and bookmarked ones are other people's: neither is your activity.
List<TrailEntry> toEntries(List<Trail> trails) {
  return [
    for (final trail in trails)
      if (trail.source != TrailSource.planned && trail.source != TrailSource.bookmarked)
        TrailEntry(
          trail: trail,
          stats: computeStats(trail.coordinates),
          date:
              trail.coordinates.where((c) => c.timestamp != null).firstOrNull?.timestamp?.toLocal() ??
              trail.createdAt?.toLocal(),
        ),
  ];
}

/// Half-open [start, end) range of a period; null bounds mean unbounded.
({DateTime? start, DateTime? end}) periodRange(Period period, DateTime now) {
  switch (period) {
    case Period.week:
      final start = startOfWeek(now);
      return (start: start, end: addDays(start, 7));
    case Period.month:
      return (start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 1));
    case Period.year:
      return (start: DateTime(now.year, 1, 1), end: DateTime(now.year + 1, 1, 1));
    case Period.all:
      return (start: null, end: null);
  }
}

List<TrailEntry> filterByPeriod(List<TrailEntry> entries, Period period, DateTime now) {
  final range = periodRange(period, now);
  final start = range.start;
  final end = range.end;
  if (start == null || end == null) return entries;
  return [
    for (final e in entries)
      if (e.date != null && !e.date!.isBefore(start) && e.date!.isBefore(end)) e,
  ];
}

/// Bars for the distance chart: days (week), 6 weeks (month), months (year) or years (all).
List<Bucket> buildBuckets(Period period, List<TrailEntry> entries, DateTime now) {
  final buckets = <Bucket>[];
  switch (period) {
    case Period.week:
      final ws = startOfWeek(now);
      for (var i = 0; i < 7; i++) {
        buckets.add(Bucket(addDays(ws, i), addDays(ws, i + 1)));
      }
    case Period.month:
      final ws = startOfWeek(now);
      for (var i = -5; i <= 0; i++) {
        buckets.add(Bucket(addDays(ws, i * 7), addDays(ws, i * 7 + 7)));
      }
    case Period.year:
      for (var m = 1; m <= 12; m++) {
        buckets.add(Bucket(DateTime(now.year, m, 1), DateTime(now.year, m + 1, 1)));
      }
    case Period.all:
      final years = [
        for (final e in entries)
          if (e.date != null) e.date!.year,
      ];
      final first = math.max(years.fold<int>(now.year, math.min), now.year - _maxYearBars + 1);
      for (var y = first; y <= now.year; y++) {
        buckets.add(Bucket(DateTime(y, 1, 1), DateTime(y + 1, 1, 1)));
      }
  }
  for (final e in entries) {
    final date = e.date;
    if (date == null) continue;
    final bucket = buckets.where((b) => !date.isBefore(b.start) && date.isBefore(b.end)).firstOrNull;
    if (bucket == null) continue;
    if (e.trail.source == TrailSource.recorded) {
      bucket.recordedM += e.stats.distanceM;
    } else {
      bucket.importedM += e.stats.distanceM;
    }
  }
  return buckets;
}

TrailEntry? _best(List<TrailEntry> entries, num? Function(TrailEntry) value) {
  TrailEntry? winner;
  num max = double.negativeInfinity;
  for (final e in entries) {
    final v = value(e);
    if (v != null && v > max) {
      max = v;
      winner = e;
    }
  }
  return winner;
}

PeriodSummary summarize(List<TrailEntry> entries) {
  final recorded = SourceTotals();
  final imported = SourceTotals();
  final activeDays = <String>{};
  var distanceM = 0.0;
  var gainM = 0.0;
  var gainCount = 0;
  var movingMs = 0;
  var timedDistanceM = 0.0;
  for (final e in entries) {
    distanceM += e.stats.distanceM;
    final totals = e.trail.source == TrailSource.recorded ? recorded : imported;
    totals.count += 1;
    totals.distanceM += e.stats.distanceM;
    if (e.stats.elevationGainM != null) {
      gainM += e.stats.elevationGainM!;
      gainCount += 1;
    }
    if (e.stats.durationMs != null && e.stats.durationMs! > 0) {
      movingMs += e.stats.durationMs!;
      timedDistanceM += e.stats.distanceM;
    }
    if (e.date != null) activeDays.add(dayKey(e.date!));
  }
  final count = entries.length;
  return PeriodSummary(
    count: count,
    distanceM: distanceM,
    gainM: gainM,
    movingMs: movingMs,
    avgDistanceM: count > 0 ? distanceM / count : 0,
    avgGainM: gainCount > 0 ? gainM / gainCount : null,
    avgSpeedKmh: movingMs > 0 ? timedDistanceM / 1000 / (movingMs / 3600000) : null,
    records: Records(
      longest: _best(entries, (e) => e.stats.distanceM),
      climb: _best(entries, (e) => e.stats.elevationGainM),
      highest: _best(entries, (e) => e.stats.highestM),
      time: _best(entries, (e) => e.stats.durationMs),
    ),
    recorded: recorded,
    imported: imported,
    activeDays: activeDays,
  );
}
