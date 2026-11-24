import 'package:flutter_test/flutter_test.dart';
import 'package:pania/features/tour/domain/off_track_monitor.dart';

const t = 50.0;

void main() {
  test('ignores a single stray fix', () {
    final m = OffTrackMonitor();
    expect(m.onFix(80, 5, t, 0), isNull);
    expect(m.offTrack, false);
  });
  test('alerts on two fixes in a row', () {
    final m = OffTrackMonitor()..onFix(80, 5, t, 0);
    expect(m.onFix(90, 5, t, 3000), OffTrackVerdict.alert);
    expect(m.offTrack, true);
  });
  test('a fix back on the trail resets the count', () {
    final m = OffTrackMonitor()
      ..onFix(80, 5, t, 0)
      ..onFix(10, 5, t, 3000);
    expect(m.onFix(80, 5, t, 6000), isNull);
  });
  test('does not count fixes less accurate than the threshold', () {
    final m = OffTrackMonitor()..onFix(80, 5, t, 0);
    expect(m.onFix(90, 200, t, 3000), isNull);
    expect(m.onFix(90, 5, t, 6000), OffTrackVerdict.alert);
  });
  test('reminds every two minutes while still off', () {
    final m = OffTrackMonitor()
      ..onFix(80, 5, t, 0)
      ..onFix(80, 5, t, 1000);
    expect(m.onFix(80, 5, t, 60000), isNull);
    expect(m.onFix(80, 5, t, 121000), OffTrackVerdict.remind);
    expect(m.onFix(80, 5, t, 130000), isNull);
  });
  test('clears only once well within the threshold', () {
    final m = OffTrackMonitor()
      ..onFix(80, 5, t, 0)
      ..onFix(80, 5, t, 1000);
    expect(m.onFix(45, 5, t, 2000), isNull); // inside 50 but not inside 70% of it
    expect(m.offTrack, true);
    expect(m.onFix(30, 5, t, 3000), OffTrackVerdict.back);
    expect(m.offTrack, false);
  });
  test('can alert again after coming back', () {
    final m = OffTrackMonitor()
      ..onFix(80, 5, t, 0)
      ..onFix(80, 5, t, 1000)
      ..onFix(10, 5, t, 2000)
      ..onFix(80, 5, t, 3000);
    expect(m.onFix(80, 5, t, 4000), OffTrackVerdict.alert);
  });
  test('reset clears everything', () {
    final m = OffTrackMonitor()
      ..onFix(80, 5, t, 0)
      ..onFix(80, 5, t, 1000)
      ..reset();
    expect(m.offTrack, false);
    expect(m.onFix(80, 5, t, 2000), isNull);
  });
}
