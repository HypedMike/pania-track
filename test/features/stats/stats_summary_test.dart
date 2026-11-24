import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/rust/analysis/geo.dart' show Activity;
import 'package:pania/features/stats/domain/stats_summary.dart';
import 'package:pania/features/trail/domain/gps_coordinate.dart';
import 'package:pania/features/trail/domain/trail.dart';

/// A trail of about [km] kilometers north, starting at [start].
Trail trail(String id, double km, DateTime start, {TrailSource source = TrailSource.recorded, double gain = 0}) =>
    Trail(
      id: id,
      name: id,
      source: source,
      activity: Activity.foot,
      createdAt: start,
      coordinates: [
        GpsCoordinate(latitude: 46, longitude: 11, altitude: 1000, timestamp: start),
        GpsCoordinate(
          latitude: 46 + km / 111.195,
          longitude: 11,
          altitude: 1000 + gain,
          timestamp: start.add(Duration(minutes: (km * 12).round())),
        ),
      ],
      waypoints: const [],
    );

void main() {
  // Wednesday 2026-11-25.
  final now = DateTime(2026, 11, 25, 12);

  test('weeks start on Monday', () {
    expect(startOfWeek(now), DateTime(2026, 11, 23));
    expect(startOfWeek(DateTime(2026, 11, 22)), DateTime(2026, 11, 16)); // a Sunday
  });

  test('planned and bookmarked trails are not your activity', () {
    final entries = toEntries([
      trail('a', 5, DateTime(2026, 11, 24)),
      trail('b', 5, DateTime(2026, 11, 24), source: TrailSource.planned),
      trail('c', 5, DateTime(2026, 11, 24), source: TrailSource.bookmarked),
      trail('d', 5, DateTime(2026, 11, 24), source: TrailSource.imported),
    ]);
    expect(entries.map((e) => e.trail.id), ['a', 'd']);
  });

  test('summarises a period', () {
    final entries = toEntries([
      trail('a', 10, DateTime(2026, 11, 24, 8), gain: 300),
      trail('b', 4, DateTime(2026, 11, 3, 8), gain: 100),
      trail('old', 20, DateTime(2025, 6, 3, 8)),
    ]);
    final month = summarize(filterByPeriod(entries, Period.month, now));
    expect(month.count, 2);
    expect(month.distanceM, closeTo(14000, 100));
    expect(month.gainM, closeTo(400, 1));
    expect(month.activeDays, {dayKey(DateTime(2026, 11, 24)), dayKey(DateTime(2026, 11, 3))});
    expect(month.records.longest?.trail.id, 'a');
    expect(month.records.climb?.trail.id, 'a');

    final week = summarize(filterByPeriod(entries, Period.week, now));
    expect(week.count, 1);
    expect(summarize(filterByPeriod(entries, Period.all, now)).count, 3);
  });

  test('buckets: seven days, six weeks, twelve months, and years since the first trail', () {
    final entries = toEntries([trail('a', 10, DateTime(2026, 11, 24, 8)), trail('old', 20, DateTime(2024, 6, 3, 8))]);
    expect(buildBuckets(Period.week, entries, now), hasLength(7));
    expect(buildBuckets(Period.month, entries, now), hasLength(6));
    expect(buildBuckets(Period.year, entries, now), hasLength(12));
    final years = buildBuckets(Period.all, entries, now);
    expect(years.map((b) => b.start.year), [2024, 2025, 2026]);
    expect(years.first.recordedM, closeTo(20000, 100));

    final week = buildBuckets(Period.week, entries, now);
    expect(week[1].recordedM, closeTo(10000, 100)); // Tuesday the 24th
    expect(week[0].recordedM, 0);
  });

  test('an empty period has no averages', () {
    final s = summarize(const []);
    expect(s.count, 0);
    expect(s.avgGainM, isNull);
    expect(s.avgSpeedKmh, isNull);
  });
}
