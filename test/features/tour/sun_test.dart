import 'package:flutter_test/flutter_test.dart';
import 'package:pania/features/tour/domain/sun.dart';

int minutesUtc(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return d.hour * 60 + d.minute;
}

int utc(int y, int mo, int d, [int h = 0]) => DateTime.utc(y, mo, d, h).millisecondsSinceEpoch;

// Reference times come from an independent NOAA solar calculation.
void main() {
  test('sunset in the Alps at midsummer', () {
    final s = nextSunset(46, 11, utc(2026, 6, 21, 12))!;
    expect((minutesUtc(s) - (19 * 60 + 9)).abs(), lessThanOrEqualTo(8));
  });
  test('sunset in the Alps in late November', () {
    final s = nextSunset(46, 11, utc(2026, 11, 23, 12))!;
    expect((minutesUtc(s) - (15 * 60 + 38)).abs(), lessThanOrEqualTo(8));
  });
  test('western longitudes land on the right day', () {
    final s = nextSunset(40.7, -74, utc(2026, 6, 21, 16))!;
    final d = DateTime.fromMillisecondsSinceEpoch(s, isUtc: true);
    expect(d.day, 22);
    expect((minutesUtc(s) - 30).abs(), lessThanOrEqualTo(10));
  });
  test('tells day from night', () {
    expect(isDark(46, 11, utc(2026, 11, 23, 11)), false);
    expect(isDark(46, 11, utc(2026, 11, 23, 18)), true);
    expect(isDark(46, 11, utc(2026, 11, 23, 3)), true);
  });
  test('alternates sunrises and sunsets in order', () {
    final events = sunEvents(46, 11, utc(2026, 11, 23, 12));
    for (var i = 1; i < events.length; i++) {
      expect(events[i].time, greaterThan(events[i - 1].time));
      expect(events[i].type, isNot(events[i - 1].type));
    }
  });
  test('has no sunset in polar day, and counts it as light', () {
    final june = utc(2026, 6, 21, 12);
    expect(nextSunset(80, 0, june), isNull);
    expect(isDark(80, 0, june), false);
  });
}
