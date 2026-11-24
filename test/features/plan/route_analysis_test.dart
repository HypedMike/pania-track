import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/routing/brouter.dart';
import 'package:pania/features/plan/domain/route_analysis.dart';
import 'package:pania/features/plan/domain/route_profile.dart';
import 'package:pania/features/trail/domain/gps_coordinate.dart';

/// A route going north [meters] with a point every 10 m, climbing [slopePct] %.
List<GpsCoordinate> climb(double meters, double slopePct) => [
  for (var d = 0.0; d <= meters; d += 10)
    GpsCoordinate(latitude: 46 + d / 111195, longitude: 11, altitude: 1000 + d * slopePct / 100),
];

void main() {
  test('a gentle marked path is T and gets a sensible walking time', () {
    final path = RoutedPath(
      coordinates: climb(2000, 5),
      segments: const [
        WaySegment(distanceM: 2000, tags: {'highway': 'path', 'route_hiking_iwn': 'yes', 'sac_scale': 'hiking'}),
      ],
    );
    final a = analyzeRoute(path);
    expect(a.difficulty, CaiGrade.t);
    expect(a.distanceM, closeTo(2000, 5));
    expect(a.gainM, closeTo(100, 5));
    expect(a.markedShare, 1);
    expect(a.maxSlopePct, closeTo(5, 0.5));
    // 2 km flat = 30 min, 100 m up = 20 min: the longer counts in full, the shorter half.
    expect(a.estimatedMs / 60000, closeTo(30 + 10, 3));
    expect(a.hazards, isEmpty);
  });

  test('steep ground and demanding paths raise the grade and warn', () {
    final steep = analyzeRoute(RoutedPath(coordinates: climb(1000, 45), segments: const []));
    expect(steep.difficulty, CaiGrade.ee);
    expect(steep.hazards.map((h) => h.kind), contains(HazardKind.steep));

    final alpine = analyzeRoute(
      RoutedPath(
        coordinates: climb(1000, 5),
        segments: const [
          WaySegment(distanceM: 300, tags: {'highway': 'path', 'sac_scale': 'alpine_hiking'}),
        ],
      ),
    );
    expect(alpine.difficulty, CaiGrade.eea);
    expect(alpine.hazards.map((h) => h.kind), contains(HazardKind.demanding));
  });

  test('busy roads are a hazard and cost more than paths', () {
    final road = analyzeRoute(
      RoutedPath(
        coordinates: climb(1000, 0),
        segments: const [
          WaySegment(distanceM: 1000, tags: {'highway': 'primary'}),
        ],
      ),
    );
    final path = analyzeRoute(
      RoutedPath(
        coordinates: climb(1000, 0),
        segments: const [
          WaySegment(distanceM: 1000, tags: {'highway': 'path', 'route_hiking_iwn': 'yes'}),
        ],
      ),
    );
    expect(road.hazards.map((h) => h.kind), contains(HazardKind.busyRoad));
    expect(routeCost(road, true), greaterThan(routeCost(path, true)));
  });

  group('route profile', () {
    test('classifies grades by steps', () {
      expect(gradeClass(3), 0);
      expect(gradeClass(-10), 1);
      expect(gradeClass(20), 2);
      expect(gradeClass(30), 3);
    });

    test('cuts a route into bins with the right grade', () {
      final p = buildProfile(climb(3000, 10))!;
      expect(p.totalM, closeTo(3000, 5));
      expect(p.bins.every((b) => (b.gradePct - 10).abs() < 0.5), true);
      expect(p.bins.first.from, 0);
      expect(p.bins.last.to, closeTo(p.totalM, 1e-6));
      expect(altAt(p.points, 1500), closeTo(1150, 1));
    });

    test('has no profile without altitude', () {
      expect(
        buildProfile([
          const GpsCoordinate(latitude: 46, longitude: 11),
          const GpsCoordinate(latitude: 46.01, longitude: 11),
        ]),
        isNull,
      );
    });

    test('finds where the route passes each checkpoint, in order', () {
      final route = [...climb(1000, 0), ...climb(1000, 0).reversed];
      final p = buildProfile(route)!;
      final marks = checkpointDistances(p, [route.first, route[100], route.last]);
      expect(marks[0], 0);
      expect(marks[1], closeTo(1000, 15));
      expect(marks[2], closeTo(p.totalM, 15));
    });
  });
}
