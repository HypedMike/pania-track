import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/rust/analysis/pace.dart' show Profile;
import 'package:pania/features/tour/domain/pace_eta.dart';

/// 4 km: the first kilometer takes 1000 s, the second 2000 s (a climb), the last two 1000 s each.
final profile = Profile(stepM: 1000, totalM: 4000, seconds: Float64List.fromList([0, 1000, 3000, 4000, 5000]));

void main() {
  group('secondsAt', () {
    test('reads the profile at its steps and between them', () {
      expect(secondsAt(profile, 0), 0);
      expect(secondsAt(profile, 1000), 1000);
      expect(secondsAt(profile, 1500), 2000);
      expect(secondsAt(profile, 4000), 5000);
    });
    test('stays inside the trail', () {
      expect(secondsAt(profile, -50), 0);
      expect(secondsAt(profile, 99999), 5000);
    });
    test('handles a last step shorter than the others', () {
      final p = Profile(stepM: 1000, totalM: 1500, seconds: Float64List.fromList([0, 1000, 1500]));
      expect(secondsAt(p, 1250), 1250);
      expect(secondsAt(Profile(stepM: 50, totalM: 0, seconds: Float64List(0)), 10), 0);
    });
  });

  group('paceFactor', () {
    test('is 1 until there is enough to compare', () {
      expect(paceFactor(profile, 0, 50, 60), 1);
      expect(paceFactor(profile, 0, 1000, 60), 1);
    });
    test('is the ratio of the time taken to the time predicted', () {
      expect(paceFactor(profile, 0, 1000, 1000), closeTo(1, 1e-9));
      expect(paceFactor(profile, 0, 1000, 1200), closeTo(1.2, 1e-9));
      expect(paceFactor(profile, 0, 3000, 3000), closeTo(0.75, 1e-9));
    });
    test('is kept within reason', () {
      expect(paceFactor(profile, 0, 1000, 100000), 1.8);
      expect(paceFactor(profile, 0, 1000, 200), 0.6);
    });
    test('measures from where the person joined the trail', () {
      // Joined at 1000 m and took 2400 s for the 2000 s the model gives for the next kilometer.
      expect(paceFactor(profile, 1000, 2000, 2400), closeTo(1.2, 1e-9));
    });
  });

  group('profileSpeedMs', () {
    test("gives the model's own speed for what is left when the person is on the model", () {
      // 3 km left, the model expects 4000 s: 0.75 m/s.
      expect(profileSpeedMs(profile, 1000, 0, 1000), closeTo(0.75, 1e-9));
    });
    test('slows the rest of the trail down when the person is behind the model', () {
      final onModel = profileSpeedMs(profile, 1000, 0, 1000)!;
      final slow = profileSpeedMs(profile, 1000, 0, 1500)!;
      expect(slow, closeTo(onModel / 1.5, 1e-9));
    });
    test('knows a climb is coming: the same remaining distance takes longer', () {
      expect(profileSpeedMs(profile, 0, 0, 0)!, lessThan(profileSpeedMs(profile, 3000, 0, 0)!));
    });
    test('has no speed at the end of the trail', () {
      expect(profileSpeedMs(profile, 4000, 0, 5000), isNull);
      expect(profileSpeedMs(Profile(stepM: 50, totalM: 0, seconds: Float64List.fromList([0])), 0, 0, 0), isNull);
    });
  });
}
