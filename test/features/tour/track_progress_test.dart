import 'package:flutter_test/flutter_test.dart';
import 'package:pania/features/tour/domain/track_progress.dart';

import 'test_helpers.dart';

void main() {
  // 1 km north, then 1 km east.
  final l = buildTrackIndex(line([(0, 0), (1000, 0), (1000, 1000)]));
  // 1 km north and straight back down the same way.
  final oab = buildTrackIndex(line([(0, 0), (1000, 0), (0, 0)]));

  group('buildTrackIndex', () {
    test('measures the trail', () {
      expect(l.totalM, closeTo(2000, 5));
      expect(l.cumulativeM[0], 0);
    });
    test('copes with an empty trail', () {
      expect(buildTrackIndex([]).totalM, 0);
    });
  });

  group('bearings', () {
    test('gives compass bearings', () {
      expect(bearingDeg(at(0), at(100)), closeTo(0, 0.5));
      expect(bearingDeg(at(0), at(0, 100)), closeTo(90, 0.5));
      expect(bearingDeg(at(0), at(-100)), closeTo(180, 0.5));
      expect(bearingDeg(at(0), at(0, -100)), closeTo(270, 0.5));
    });
    test('takes the short way round', () {
      expect(bearingDelta(350, 10), 20);
      expect(bearingDelta(10, 350), -20);
      expect(bearingDelta(0, 180), 180);
    });
    test('names compass points', () {
      expect(compassPoint(0), 'N');
      expect(compassPoint(359), 'N');
      expect(compassPoint(100), 'E');
      expect(compassPoint(225), 'SW');
    });
  });

  group('pointAtDistance', () {
    test('interpolates and clamps', () {
      final p = pointAtDistance(l, 500);
      expect(p.latitude, closeTo(at(500).latitude, 1e-5));
      expect(pointAtDistance(l, -5), l.coords.first);
      expect(pointAtDistance(l, 99999), l.coords.last);
    });
  });

  group('projectOnTrack', () {
    test('places a position on the trail', () {
      final p = projectOnTrack(l, at(500, 0));
      expect(p.alongM, closeTo(500, 0.5));
      expect(p.offTrackM, lessThan(0.5));
    });
    test('measures the distance off the trail', () {
      final p = projectOnTrack(l, at(500, 80));
      expect(p.offTrackM, closeTo(80, 0.5));
      expect(p.alongM, closeTo(500, 0.5));
    });
    test('clamps beyond the ends', () {
      expect(projectOnTrack(l, at(-50, 0)).alongM, 0);
      expect(projectOnTrack(l, at(1000, 1500)).alongM, closeTo(l.totalM, 0.5));
    });
    test('handles a one-point trail', () {
      final one = buildTrackIndex([at(0)]);
      expect(projectOnTrack(one, at(0, 40)).offTrackM, closeTo(40, 0.5));
    });
    test('stays abeam of the position far from the trail, whatever the previous progress', () {
      // Regression: neighbouring segments used to count as separate "passes" far off the trail.
      final p = projectOnTrack(l, at(500, -120), 0);
      expect(p.alongM, closeTo(500, 0.5));
      expect(p.offTrackM, closeTo(120, 0.5));
    });
    test('uses the previous progress to pick the right pass of an out-and-back', () {
      expect(projectOnTrack(oab, at(300, 0), 300).alongM, closeTo(300, 0.5));
      expect(projectOnTrack(oab, at(300, 0), 1700).alongM, closeTo(1700, 0.5));
      expect(projectOnTrack(oab, at(300, 60), 1700).alongM, closeTo(1700, 0.5));
    });
    test('without a hint takes the closest point', () {
      expect(projectOnTrack(l, at(900, 30)).alongM, closeTo(900, 0.5));
    });
  });

  group('nextTurn', () {
    test('finds a right turn ahead', () {
      final turn = nextTurn(l, 800)!;
      expect(turn.direction, TurnDirection.right);
      expect(turn.sharp, false);
      expect(turn.inM, inInclusiveRange(150, 260));
    });
    test('finds a left turn', () {
      final left = buildTrackIndex(line([(0, 0), (1000, 0), (1000, -1000)]));
      expect(nextTurn(left, 800)?.direction, TurnDirection.left);
    });
    test('calls a hairpin sharp', () {
      expect(nextTurn(oab, 800)?.sharp, true);
    });
    test('sees nothing on a straight stretch or beyond the look-ahead', () {
      expect(nextTurn(l, 100), isNull);
      expect(nextTurn(l, 500, 100), isNull);
    });
    test('sees nothing near the end', () {
      expect(nextTurn(l, l.totalM - 20), isNull);
    });
  });

  group('trackUpTo', () {
    test('returns the covered part, ending at the given distance', () {
      final done = trackUpTo(l, 505);
      expect(done.first, l.coords.first);
      expect(done.last.latitude, closeTo(at(505).latitude, 1e-5));
      expect(trackUpTo(l, 0), isEmpty);
    });
  });
}
