import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/rust/analysis/geo.dart' show Activity;
import 'package:pania/core/weather/open_meteo.dart';
import 'package:pania/features/tour/domain/tour_guidance.dart';
import 'package:pania/features/tour/domain/track_progress.dart';
import 'package:pania/features/trail/domain/gps_coordinate.dart';

import 'test_helpers.dart';

final coords = line([(0, 0), (1000, 0), (1000, 1000)]);
final index = buildTrackIndex(coords);
final trail = [for (final c in coords) GpsCoordinate(latitude: c.latitude, longitude: c.longitude)];

void main() {
  group('speed', () {
    const samples = [ProgressSample(0, 0), ProgressSample(60000, 90), ProgressSample(120000, 180)];
    test('measures recent progress', () {
      expect(recentSpeedMs(samples, 120000), closeTo(1.5, 1e-5));
    });
    test('needs enough time to say anything', () {
      expect(recentSpeedMs(const [ProgressSample(0, 0), ProgressSample(10000, 30)], 10000), isNull);
      expect(recentSpeedMs(const [], 0), isNull);
    });
    test('only looks at the last few minutes', () {
      final old = [
        const ProgressSample(0, 0),
        const ProgressSample(60000, 500),
        for (final s in samples) ProgressSample(s.time + 600000, s.alongM + 500),
      ];
      expect(recentSpeedMs(old, 720000), closeTo(1.5, 1e-5));
    });
    test('never reports going backwards', () {
      expect(recentSpeedMs(const [ProgressSample(0, 100), ProgressSample(60000, 40)], 60000), 0);
    });
    test('averages since the start, after a minute', () {
      expect(averageSpeedMs(const ProgressSample(0, 0), const ProgressSample(100000, 120)), closeTo(1.2, 1e-5));
      expect(averageSpeedMs(const ProgressSample(0, 0), const ProgressSample(30000, 100)), isNull);
      expect(averageSpeedMs(null, null), isNull);
    });
    test('prefers live, then average, then plan', () {
      expect(chooseSpeedMs(1.4, 1.0, 1.1), 1.4);
      expect(chooseSpeedMs(0.1, 1.0, 1.1), 1.0);
      expect(chooseSpeedMs(null, null, 1.1), 1.1);
      expect(chooseSpeedMs(0.1, 0.2, 1.1), 1.1);
    });
  });

  group('plannedSpeedMs', () {
    test('walks flat ground at 4 km/h and rides at 14', () {
      expect(plannedSpeedMs(trail, Activity.foot), closeTo(footSpeedMs, 1e-3));
      expect(plannedSpeedMs(trail, Activity.bike), closeTo(bikeSpeedMs, 1e-3));
    });
    test('is slower uphill (Naismith)', () {
      final climb = [
        for (var i = 0; i < trail.length; i++)
          GpsCoordinate(latitude: trail[i].latitude, longitude: trail[i].longitude, altitude: i * 5.0),
      ];
      expect(plannedSpeedMs(climb, Activity.foot), lessThan(footSpeedMs * 0.8));
    });
    test('uses the recorded pace when the trail has timestamps', () {
      final timed = [
        for (var i = 0; i < trail.length; i++)
          GpsCoordinate(
            latitude: trail[i].latitude,
            longitude: trail[i].longitude,
            timestamp: DateTime.fromMillisecondsSinceEpoch(i * 10000, isUtc: true),
          ),
      ]; // 1 m/s
      expect(plannedSpeedMs(timed, Activity.foot), closeTo(1, 0.05));
    });
    test('ignores an implausible recorded pace', () {
      final fast = [
        for (var i = 0; i < trail.length; i++)
          GpsCoordinate(
            latitude: trail[i].latitude,
            longitude: trail[i].longitude,
            timestamp: DateTime.fromMillisecondsSinceEpoch(i * 100, isUtc: true),
          ),
      ]; // 100 m/s
      expect(plannedSpeedMs(fast, Activity.foot), closeTo(footSpeedMs, 1e-3));
    });
  });

  TourGuidance guide({
    GpsCoordinate? position,
    double speedMs = 1,
    int nowMs = 0,
    List<Waypoint> waypoints = const [],
  }) => computeGuidance(
    GuidanceInput(
      index: index,
      waypoints: waypoints,
      position: position ?? gps(300, 0),
      speedMs: speedMs,
      nowMs: nowMs,
      offTrackThresholdM: 50,
    ),
  );

  group('computeGuidance', () {
    test('reports progress and remaining distance', () {
      final g = guide();
      expect(g.alongM, closeTo(300, 0.5));
      expect(g.remainingM, closeTo(index.totalM - 300, 0.5));
      expect(g.progressPct, closeTo(300 / index.totalM * 100, 0.1));
    });
    test('estimates arrival from the speed', () {
      final g = guide(speedMs: 2, nowMs: 1000);
      expect(g.etaMs, closeTo(1000 + g.remainingM / 2 * 1000, 10));
    });
    test('does not divide by zero when standing still', () {
      expect(guide(speedMs: 0).etaMs, isNonNegative);
    });
    test('points along the trail when on it', () {
      final g = guide();
      expect(g.bearing < 3 || g.bearing > 357, true);
      expect(g.turn, isNull);
    });
    test('announces the turn', () {
      expect(guide(position: gps(850, 0)).turn?.direction, TurnDirection.right);
    });
    test('points back to the trail when off it, and announces no turn', () {
      final g = guide(position: gps(500, -100));
      expect(g.offTrackM, closeTo(100, 0.5));
      expect(g.bearing, greaterThan(60));
      expect(g.bearing, lessThan(110));
      expect(g.turn, isNull);
    });
    test('is arrived within 30 m of the end, on the trail only', () {
      final end = pointAtDistance(index, index.totalM - 10);
      expect(
        guide(
          position: GpsCoordinate(latitude: end.latitude, longitude: end.longitude),
        ).arrived,
        true,
      );
      expect(guide(position: gps(1000, 995)).arrived, true);
      expect(guide(position: gps(1100, 1000)).arrived, false); // 100 m off, even if near the end
      expect(guide().arrived, false);
    });
    test('finds the next waypoint ahead, not the ones passed', () {
      final waypoints = [Waypoint.at(gps(100, 0), 'behind'), Waypoint.at(gps(1000, 400), 'ahead')];
      final g = guide(waypoints: waypoints);
      expect(g.nextWaypoint?.name, 'ahead');
      expect(g.nextWaypoint!.inM, closeTo(1100, 5));
      expect(guide(position: gps(1000, 900), waypoints: waypoints).nextWaypoint, isNull);
    });
  });

  HourForecast hour(
    int h, {
    double temperatureC = 15,
    double precipProbPct = 0,
    double precipMm = 0,
    int code = 1,
    double gustKmh = 10,
  }) => HourForecast(
    time: h * 3600000,
    temperatureC: temperatureC,
    precipProbPct: precipProbPct,
    precipMm: precipMm,
    code: code,
    gustKmh: gustKmh,
  );
  List<WarningKind> kinds(List<TourWarning> ws) => [for (final w in ws) w.kind];

  group('assessWeather', () {
    test('is quiet in good weather', () {
      expect(assessWeather([hour(0), hour(1)], 0, 7200000), isEmpty);
    });
    test('only looks at the hours of the trip', () {
      expect(assessWeather([hour(5, code: 95)], 0, 3600000), isEmpty);
    });
    test('warns of thunderstorms as danger, and drops rain then', () {
      final w = assessWeather([hour(0, code: 95, precipProbPct: 90, precipMm: 5)], 0, 3600000);
      expect(kinds(w), [WarningKind.storm]);
      expect(w.first.level, WarningLevel.danger);
    });
    test('needs both probability and amount for rain', () {
      expect(assessWeather([hour(0, precipProbPct: 90, precipMm: 0.1)], 0, 3600000), isEmpty);
      expect(assessWeather([hour(0, precipProbPct: 20, precipMm: 3)], 0, 3600000), isEmpty);
      expect(kinds(assessWeather([hour(0, precipProbPct: 70, precipMm: 1)], 0, 3600000)), [WarningKind.rain]);
    });
    test('calls heavy rain danger', () {
      expect(assessWeather([hour(0, precipProbPct: 90, precipMm: 6)], 0, 3600000).first.level, WarningLevel.danger);
    });
    test('reports snow, wind, heat and frost', () {
      expect(kinds(assessWeather([hour(0, code: 73)], 0, 3600000)), [WarningKind.snow]);
      final wind = assessWeather([hour(0, gustKmh: 95)], 0, 3600000);
      expect(wind.first.kind, WarningKind.wind);
      expect(wind.first.level, WarningLevel.danger);
      expect(wind.first.data['kmh'], 95);
      expect(kinds(assessWeather([hour(0, temperatureC: 35)], 0, 3600000)), [WarningKind.heat]);
      expect(kinds(assessWeather([hour(0, temperatureC: -3)], 0, 3600000)), [WarningKind.cold]);
    });
    test('dates a warning from now when the hour is already under way', () {
      final w = assessWeather([hour(0, code: 95)], 1800000, 3600000);
      expect(w.first.data['atMs'], 1800000);
    });
  });

  group('computeWarnings', () {
    // 14:30 UTC on 23 Nov 2026 in the Alps: sunset is about 15:38 UTC.
    final now = DateTime.utc(2026, 11, 23, 14, 30).millisecondsSinceEpoch;
    final destination = trail.last;

    WarningInput base({
      TourGuidance? guidance,
      bool offTrack = false,
      int? nowMs,
      int? lastFixMs,
      int? targetArrivalMs,
      List<HourForecast> forecast = const [],
      GpsCoordinate? position,
    }) {
      final at = nowMs ?? now;
      return WarningInput(
        guidance:
            guidance ??
            computeGuidance(
              GuidanceInput(
                index: index,
                waypoints: const [],
                position: gps(300, 0),
                speedMs: 1.2,
                nowMs: at,
                offTrackThresholdM: 50,
              ),
            ),
        offTrack: offTrack,
        nowMs: at,
        lastFixMs: lastFixMs ?? at,
        targetArrivalMs: targetArrivalMs,
        position: position ?? gps(300, 0),
        destination: destination,
        forecast: forecast,
      );
    }

    test('has nothing to say when all is well', () {
      // 1.7 km at 1.2 m/s ends well before sunset
      expect(computeWarnings(base()), isEmpty);
    });
    test('reports being off the trail first', () {
      final w = computeWarnings(base(offTrack: true));
      expect(w.first.kind, WarningKind.offTrack);
      expect(w.first.level, WarningLevel.danger);
    });
    test('reports lost GPS', () {
      expect(kinds(computeWarnings(base(lastFixMs: now - 90000))), [WarningKind.noGps]);
      expect(computeWarnings(base(lastFixMs: now - 30000)), isEmpty);
    });
    test('warns when late for the target, with the pace needed', () {
      final w = computeWarnings(base(targetArrivalMs: now + 10 * 60000)).firstWhere((x) => x.kind == WarningKind.late);
      expect(w.data['neededSpeedMs'], greaterThan(2));
      expect(w.data['lateByMs'], greaterThan(0));
    });
    test('tolerates five minutes of lateness', () {
      final input = base();
      final target = input.guidance.etaMs - 4 * 60000;
      expect(
        kinds(computeWarnings(base(guidance: input.guidance, targetArrivalMs: target))),
        isNot(contains(WarningKind.late)),
      );
    });
    test('still reports lateness when the target has passed, without a needed pace', () {
      final w = computeWarnings(base(targetArrivalMs: now - 60000)).firstWhere((x) => x.kind == WarningKind.late);
      expect(w.data['neededSpeedMs'], 0);
    });
    test('warns when the arrival is after sunset', () {
      final slow = computeGuidance(
        GuidanceInput(
          index: index,
          waypoints: const [],
          position: gps(300, 0),
          speedMs: 0.3,
          nowMs: now,
          offTrackThresholdM: 50,
        ),
      );
      expect(kinds(computeWarnings(base(guidance: slow))), contains(WarningKind.afterDark));
    });
    test('says when it is already dark', () {
      final night = DateTime.utc(2026, 11, 23, 19).millisecondsSinceEpoch;
      expect(kinds(computeWarnings(base(nowMs: night, lastFixMs: night))), contains(WarningKind.dark));
    });
    test('adds weather for the time of the trip', () {
      final forecast = [hour(now ~/ 3600000, code: 95)];
      expect(kinds(computeWarnings(base(forecast: forecast))), contains(WarningKind.storm));
    });
    test('puts danger before warning', () {
      final forecast = [hour(now ~/ 3600000, code: 95, temperatureC: -2)];
      expect(computeWarnings(base(forecast: forecast)).first.level, WarningLevel.danger);
    });
    test('stops warning about the future once arrived', () {
      final end = pointAtDistance(index, index.totalM - 5);
      final endGps = GpsCoordinate(latitude: end.latitude, longitude: end.longitude);
      final guidance = computeGuidance(
        GuidanceInput(
          index: index,
          waypoints: const [],
          position: endGps,
          speedMs: 0.3,
          nowMs: now,
          offTrackThresholdM: 50,
        ),
      );
      final forecast = [hour(now ~/ 3600000, code: 95)];
      expect(
        computeWarnings(base(guidance: guidance, position: endGps, forecast: forecast, targetArrivalMs: now - 1)),
        isEmpty,
      );
    });
  });
}
