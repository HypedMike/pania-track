import 'dart:math' as math;

import '../../../core/gps/trail_stats.dart';
import '../../../core/rust/analysis/geo.dart' show Activity;
import '../../../core/weather/open_meteo.dart';
import '../../trail/domain/gps_coordinate.dart';
import 'sun.dart';
import 'track_progress.dart';

// ── Speed and arrival time ──────────────────────────────────────────────────────────────

/// A moment on the trail: when, and how far along it the person was.
class ProgressSample {
  const ProgressSample(this.time, this.alongM);

  final int time;
  final double alongM;
}

const int _speedWindowMs = 3 * 60000;

/// A window shorter than this says little about speed.
const int _minWindowMs = 30000;

/// Below this the person is standing still, and the speed says nothing about the pace.
const double _movingMs = 0.5;

const double footSpeedMs = 4000 / 3600;
const double bikeSpeedMs = 14000 / 3600;

/// Naismith's rule: one extra hour per 600 m of ascent.
const double _ascentMs = 600 / 3600;

/// Progress made over the last few minutes, in m/s. Backwards steps count as no progress.
double? recentSpeedMs(List<ProgressSample> samples, int nowMs) {
  final recent = samples.where((s) => s.time >= nowMs - _speedWindowMs).toList();
  if (recent.length < 2) return null;
  final first = recent.first;
  final last = recent.last;
  final dt = last.time - first.time;
  if (dt < _minWindowMs) return null;
  return math.max(0, last.alongM - first.alongM) / (dt / 1000);
}

/// Progress made since the tour began, in m/s, once there is a minute of it.
double? averageSpeedMs(ProgressSample? first, ProgressSample? last) {
  if (first == null || last == null || last.time - first.time < 60000) return null;
  return math.max(0, last.alongM - first.alongM) / ((last.time - first.time) / 1000);
}

/// How fast the trail is expected to be covered, in m/s: the pace it was recorded at when it has
/// timestamps, otherwise walking at 4 km/h (plus Naismith's allowance for climbing) or cycling
/// at 14 km/h.
double plannedSpeedMs(List<GpsCoordinate> coords, Activity activity) {
  final stats = computeStats(coords);
  final sane = activity == Activity.bike ? 12.0 : 2.5;
  if (stats.durationMs != null && stats.durationMs! > 0 && stats.distanceM > 0) {
    final recorded = stats.distanceM / (stats.durationMs! / 1000);
    if (recorded >= 0.3 && recorded <= sane) return recorded;
  }
  if (activity == Activity.bike || stats.distanceM == 0) {
    return activity == Activity.bike ? bikeSpeedMs : footSpeedMs;
  }
  final seconds = stats.distanceM / footSpeedMs + (stats.elevationGainM ?? 0) / _ascentMs;
  return stats.distanceM / seconds;
}

/// The speed to base the arrival time on: what the person is doing now, else their average, else the plan.
double chooseSpeedMs(double? live, double? average, double planned) {
  if (live != null && live >= _movingMs) return live;
  if (average != null && average >= _movingMs) return average;
  return planned;
}

// ── Guidance ────────────────────────────────────────────────────────────────────────────

/// Closer than this to the end, the tour counts as arrived.
const double arrivedM = 30;

/// When off the trail, aim for a point this far ahead of the nearest one, so you rejoin going forward.
const double _rejoinAheadM = 25;

class NextWaypoint {
  const NextWaypoint(this.name, this.inM);
  final String name;
  final double inM;
}

class TourGuidance {
  const TourGuidance({
    required this.alongM,
    required this.remainingM,
    required this.progressPct,
    required this.offTrackM,
    required this.nearest,
    required this.bearing,
    required this.turn,
    required this.nextWaypoint,
    required this.arrived,
    required this.speedMs,
    required this.etaMs,
  });

  final double alongM;
  final double remainingM;

  /// 0–100.
  final double progressPct;
  final double offTrackM;

  /// Closest point of the trail.
  final LatLon nearest;

  /// Compass bearing to head in: along the trail when on it, towards it when off.
  final double bearing;

  /// The next turn of the trail, when on it.
  final Turn? turn;
  final NextWaypoint? nextWaypoint;
  final bool arrived;

  /// The speed the arrival time is based on, in m/s.
  final double speedMs;

  /// Estimated arrival, in milliseconds since the epoch.
  final int etaMs;
}

class GuidanceInput {
  const GuidanceInput({
    required this.index,
    required this.waypoints,
    required this.position,
    required this.speedMs,
    required this.nowMs,
    required this.offTrackThresholdM,
    this.previousAlongM,
  });

  final TrackIndex index;
  final List<Waypoint> waypoints;
  final GpsCoordinate position;

  /// Progress at the previous fix, to stay on the right lap of loops and out-and-backs.
  final double? previousAlongM;
  final double speedMs;
  final int nowMs;

  /// Distance beyond which the person counts as off the trail (so turns are not announced).
  final double offTrackThresholdM;
}

TourGuidance computeGuidance(GuidanceInput input) {
  final index = input.index;
  final position = latLonOf(input.position);
  final projection = projectOnTrack(index, position, input.previousAlongM);
  final alongM = projection.alongM;
  final remainingM = math.max(0.0, index.totalM - alongM);
  final offTrack = projection.offTrackM > input.offTrackThresholdM;

  final bearing = offTrack
      ? bearingDeg(position, pointAtDistance(index, alongM + _rejoinAheadM))
      : bearingDeg(pointAtDistance(index, alongM), pointAtDistance(index, alongM + 30));

  NextWaypoint? nextWaypoint;
  for (final w in input.waypoints) {
    final wAlong = projectOnTrack(index, latLonOf(w)).alongM;
    final inM = wAlong - alongM;
    // Waypoints right under the feet are already "reached".
    if (inM > 20 && (nextWaypoint == null || inM < nextWaypoint.inM)) nextWaypoint = NextWaypoint(w.name, inM);
  }

  return TourGuidance(
    alongM: alongM,
    remainingM: remainingM,
    progressPct: index.totalM > 0 ? math.min(100.0, alongM / index.totalM * 100) : 0,
    offTrackM: projection.offTrackM,
    nearest: projection.nearest,
    bearing: bearing,
    turn: offTrack ? null : nextTurn(index, alongM),
    nextWaypoint: nextWaypoint,
    arrived: remainingM <= arrivedM && !offTrack,
    speedMs: input.speedMs,
    etaMs: (input.nowMs + remainingM / math.max(input.speedMs, 0.1) * 1000).round(),
  );
}

// ── Warnings ────────────────────────────────────────────────────────────────────────────

enum WarningKind { offTrack, noGps, late, afterDark, dark, storm, rain, snow, wind, heat, cold }

enum WarningLevel { warning, danger }

class TourWarning {
  const TourWarning(this.kind, this.level, [this.data = const {}]);

  final WarningKind kind;
  final WarningLevel level;

  /// Numbers the message is built from (times in ms since the epoch, speeds in m/s, …).
  final Map<String, num> data;
}

/// Arriving this much after the wanted time still counts as on time.
const int _lateGraceMs = 5 * 60000;

/// A GPS signal older than this is reported as lost.
const int gpsLostMs = 60000;

const Set<int> _stormCodes = {95, 96, 99};
bool _isSnow(int code) => (code >= 71 && code <= 77) || code == 85 || code == 86;

/// What the forecast says about the hours between [fromMs] and [toMs].
List<TourWarning> assessWeather(List<HourForecast> hours, int fromMs, int toMs) {
  final window = hours.where((h) => h.time + 3600000 > fromMs && h.time < toMs).toList();
  if (window.isEmpty) return [];
  final warnings = <TourWarning>[];
  // An hour already under way counts from now.
  int at(bool Function(HourForecast) pick) {
    final found = window.where(pick).firstOrNull;
    return math.max(found?.time ?? 0, fromMs);
  }

  final storm = window.where((h) => _stormCodes.contains(h.code)).firstOrNull;
  if (storm != null) {
    warnings.add(TourWarning(WarningKind.storm, WarningLevel.danger, {'atMs': math.max(storm.time, fromMs)}));
  }

  final snow = window.where((h) => _isSnow(h.code)).firstOrNull;
  if (snow != null) {
    warnings.add(TourWarning(WarningKind.snow, WarningLevel.warning, {'atMs': math.max(snow.time, fromMs)}));
  }

  final wet = window.where((h) => !_isSnow(h.code) && h.precipProbPct >= 60 && h.precipMm >= 0.5).toList();
  if (wet.isNotEmpty && storm == null) {
    final heaviest = wet.reduce((a, b) => b.precipMm > a.precipMm ? b : a);
    warnings.add(
      TourWarning(WarningKind.rain, heaviest.precipMm >= 4 ? WarningLevel.danger : WarningLevel.warning, {
        'atMs': math.max(wet.first.time, fromMs),
        'mm': (heaviest.precipMm * 10).round() / 10,
        'probPct': heaviest.precipProbPct,
      }),
    );
  }

  final gust = window.map((h) => h.gustKmh).reduce(math.max);
  if (gust >= 60) {
    warnings.add(
      TourWarning(WarningKind.wind, gust >= 90 ? WarningLevel.danger : WarningLevel.warning, {
        'atMs': at((h) => h.gustKmh == gust),
        'kmh': gust.round(),
      }),
    );
  }

  final hottest = window.map((h) => h.temperatureC).reduce(math.max);
  if (hottest >= 32) {
    warnings.add(
      TourWarning(WarningKind.heat, WarningLevel.warning, {
        'atMs': at((h) => h.temperatureC == hottest),
        'c': hottest.round(),
      }),
    );
  }
  final coldest = window.map((h) => h.temperatureC).reduce(math.min);
  if (coldest <= 0) {
    warnings.add(
      TourWarning(WarningKind.cold, WarningLevel.warning, {
        'atMs': at((h) => h.temperatureC == coldest),
        'c': coldest.round(),
      }),
    );
  }
  return warnings;
}

class WarningInput {
  const WarningInput({
    required this.guidance,
    required this.offTrack,
    required this.nowMs,
    required this.lastFixMs,
    required this.targetArrivalMs,
    required this.position,
    required this.destination,
    required this.forecast,
  });

  final TourGuidance guidance;

  /// Whether the person has been off the trail long enough to be told.
  final bool offTrack;
  final int nowMs;

  /// Time of the last GPS fix, ms.
  final int lastFixMs;

  /// The time the person wants to be there by, ms, if they set one.
  final int? targetArrivalMs;
  final GpsCoordinate position;
  final GpsCoordinate destination;
  final List<HourForecast> forecast;
}

/// Everything the person should be warned about right now, most serious first.
List<TourWarning> computeWarnings(WarningInput input) {
  final guidance = input.guidance;
  final nowMs = input.nowMs;
  final warnings = <TourWarning>[];

  if (input.offTrack) {
    warnings.add(TourWarning(WarningKind.offTrack, WarningLevel.danger, {'m': guidance.offTrackM.round()}));
  }
  if (nowMs - input.lastFixMs > gpsLostMs) {
    warnings.add(TourWarning(WarningKind.noGps, WarningLevel.warning, {'sinceMs': input.lastFixMs}));
  }
  if (guidance.arrived) return warnings;

  final target = input.targetArrivalMs;
  if (target != null && guidance.etaMs > target + _lateGraceMs) {
    final remainingS = math.max(1.0, (target - nowMs) / 1000);
    warnings.add(
      TourWarning(WarningKind.late, WarningLevel.warning, {
        'etaMs': guidance.etaMs,
        'targetMs': target,
        'lateByMs': guidance.etaMs - target,
        // Pace needed to still make it; 0 when the wanted time has already passed.
        'neededSpeedMs': target > nowMs ? guidance.remainingM / remainingS : 0,
      }),
    );
  }

  final lat = input.position.latitude;
  final lon = input.position.longitude;
  if (isDark(lat, lon, nowMs)) {
    warnings.add(const TourWarning(WarningKind.dark, WarningLevel.warning));
  } else {
    final sunset = nextSunset(lat, lon, nowMs);
    final dest = input.destination;
    if (sunset != null && guidance.etaMs > sunset && isDark(dest.latitude, dest.longitude, guidance.etaMs)) {
      warnings.add(
        TourWarning(
          WarningKind.afterDark,
          guidance.etaMs - sunset > 30 * 60000 ? WarningLevel.danger : WarningLevel.warning,
          {'sunsetMs': sunset, 'etaMs': guidance.etaMs},
        ),
      );
    }
  }

  warnings.addAll(assessWeather(input.forecast, nowMs, guidance.etaMs + 30 * 60000));
  // Stable sort: dangers first, otherwise keep the order above.
  final indexed = warnings.asMap().entries.toList()
    ..sort((a, b) {
      final byLevel = (b.value.level == WarningLevel.danger ? 1 : 0) - (a.value.level == WarningLevel.danger ? 1 : 0);
      return byLevel != 0 ? byLevel : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}
