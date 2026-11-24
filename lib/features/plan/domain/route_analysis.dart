import '../../../core/gps/trail_stats.dart';
import '../../../core/routing/brouter.dart';

/// Italian CAI difficulty grades, the scale used on trail signs in Italy:
/// T (tourist, easy), E (hiking), EE (expert hikers), EEA (equipped / alpine).
enum CaiGrade { t, e, ee, eea }

enum HazardKind { demanding, faint, busyRoad, steep, ferry }

class Hazard {
  const Hazard(this.kind, this.value);

  final HazardKind kind;

  /// Length of the affected stretch, in meters (for [HazardKind.steep]: the steepest grade, in %).
  final double value;
}

class RouteAnalysis {
  const RouteAnalysis({
    required this.distanceM,
    required this.gainM,
    required this.lossM,
    required this.maxSlopePct,
    required this.markedShare,
    required this.roadM,
    required this.busyRoadM,
    required this.ferryM,
    required this.difficulty,
    required this.estimatedMs,
    required this.hazards,
  });

  final double distanceM;
  final double gainM;
  final double lossM;

  /// Steepest grade sustained over ~200 m, in percent.
  final double maxSlopePct;

  /// Share of the distance on waymarked hiking routes, 0–1.
  final double markedShare;

  /// Meters on roads open to traffic.
  final double roadM;

  /// Meters on busy roads (primary, secondary, trunk).
  final double busyRoadM;

  /// Meters on ferry lines, which the router uses when a checkpoint is off the coast.
  final double ferryM;
  final CaiGrade difficulty;

  /// Estimated walking time (DIN 33466), in milliseconds.
  final double estimatedMs;
  final List<Hazard> hazards;
}

/// Altitude changes below this are treated as noise, as in trail stats.
const double _elevationNoiseM = 3;

/// Grades are measured over at least this distance. The router's elevation model has ~90 m
/// cells, so shorter windows mostly measure noise.
const double _slopeWindowM = 200;

/// Sustained grade that alone makes a route EE, and that gets a warning.
const double _expertSlopePct = 40;
const double _steepWarningPct = 35;

/// Stretches shorter than this don't change the grade or raise a warning.
const double _minStretchM = 50;

const Set<String> _roads = {
  'motorway',
  'trunk',
  'primary',
  'secondary',
  'tertiary',
  'unclassified',
  'residential',
  'living_street',
  'service',
  'road',
  'trunk_link',
  'primary_link',
  'secondary_link',
  'tertiary_link',
};
const Set<String> _busyRoads = {'trunk', 'primary', 'secondary', 'trunk_link', 'primary_link', 'secondary_link'};

/// OSM sac_scale → CAI grade.
const Map<String, CaiGrade> _sacToCai = {
  'hiking': CaiGrade.t,
  'mountain_hiking': CaiGrade.e,
  'demanding_mountain_hiking': CaiGrade.ee,
  'alpine_hiking': CaiGrade.eea,
  'demanding_alpine_hiking': CaiGrade.eea,
  'difficult_alpine_hiking': CaiGrade.eea,
};

CaiGrade _harder(CaiGrade a, CaiGrade b) => a.index >= b.index ? a : b;

({double gainM, double lossM}) _gainAndLoss(List<double> alts) {
  var gain = 0.0;
  var loss = 0.0;
  var ref = alts.first;
  for (final alt in alts) {
    if (alt - ref >= _elevationNoiseM) {
      gain += alt - ref;
      ref = alt;
    } else if (ref - alt >= _elevationNoiseM) {
      loss += ref - alt;
      ref = alt;
    }
  }
  return (gainM: gain, lossM: loss);
}

double _maxSlope(RoutedPath path) {
  final pts = [
    for (final c in path.coordinates)
      if (c.altitude != null) c,
  ];
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum[i - 1] + haversine(pts[i - 1], pts[i]));
  }
  var max = 0.0;
  var j = 0;
  for (var i = 0; i < pts.length; i++) {
    while (j < pts.length && cum[j] - cum[i] < _slopeWindowM) {
      j++;
    }
    if (j >= pts.length) break;
    final slope = (pts[j].altitude! - pts[i].altitude!).abs() / (cum[j] - cum[i]);
    if (slope > max) max = slope;
  }
  return max * 100;
}

CaiGrade _slopeGrade(double pct) {
  if (pct >= _expertSlopePct) return CaiGrade.ee;
  if (pct >= 15) return CaiGrade.e;
  return CaiGrade.t;
}

bool _isRoad(WaySegment s) => _roads.contains(s.tags['highway']) && s.tags['foot'] != 'designated';
bool _isMarked(WaySegment s) => s.tags.keys.any((k) => k.startsWith('route_hiking_'));
bool _isFaint(WaySegment s) => const ['bad', 'horrible', 'no'].contains(s.tags['trail_visibility']);
bool _isDemanding(WaySegment s) {
  final grade = _sacToCai[s.tags['sac_scale']];
  return grade == CaiGrade.ee || grade == CaiGrade.eea;
}

double _sum(List<WaySegment> segments, bool Function(WaySegment) test) =>
    segments.fold(0.0, (total, s) => total + (test(s) ? s.distanceM : 0));

/// DIN 33466: 4 km/h on the flat, 300 m/h up, 500 m/h down; the smaller part counts half.
double walkingTimeMs(double distanceM, double gainM, double lossM) {
  final horizontalH = distanceM / 4000;
  final verticalH = gainM / 300 + lossM / 500;
  final hours =
      (horizontalH > verticalH ? horizontalH : verticalH) + (horizontalH < verticalH ? horizontalH : verticalH) / 2;
  return hours * 3600000;
}

RouteAnalysis analyzeRoute(RoutedPath path) {
  final coordinates = path.coordinates;
  final segments = path.segments;
  var distanceM = 0.0;
  for (var i = 1; i < coordinates.length; i++) {
    distanceM += haversine(coordinates[i - 1], coordinates[i]);
  }
  final alts = [
    for (final c in coordinates)
      if (c.altitude != null) c.altitude!,
  ];
  final gl = alts.isNotEmpty ? _gainAndLoss(alts) : (gainM: 0.0, lossM: 0.0);
  final maxSlopePct = _maxSlope(path);

  final segmentTotal = _sum(segments, (_) => true) != 0
      ? _sum(segments, (_) => true)
      : (distanceM != 0 ? distanceM : 1);
  final markedShare = _sum(segments, _isMarked) / segmentTotal;
  final roadM = _sum(segments, _isRoad);
  final busyRoadM = _sum(segments, (s) => _busyRoads.contains(s.tags['highway']));
  final demandingM = _sum(segments, _isDemanding);
  final faintM = _sum(segments, _isFaint);
  final ferryM = _sum(segments, (s) => s.tags['route'] == 'ferry');

  var difficulty = _slopeGrade(maxSlopePct);
  for (final s in segments) {
    final grade = _sacToCai[s.tags['sac_scale']];
    if (grade != null && s.distanceM >= _minStretchM) difficulty = _harder(difficulty, grade);
  }

  final hazards = <Hazard>[
    if (demandingM >= _minStretchM) Hazard(HazardKind.demanding, demandingM),
    if (ferryM > 0) Hazard(HazardKind.ferry, ferryM),
    if (maxSlopePct >= _steepWarningPct) Hazard(HazardKind.steep, maxSlopePct),
    if (faintM >= _minStretchM) Hazard(HazardKind.faint, faintM),
    if (busyRoadM >= 200) Hazard(HazardKind.busyRoad, busyRoadM),
  ];

  return RouteAnalysis(
    distanceM: distanceM,
    gainM: gl.gainM,
    lossM: gl.lossM,
    maxSlopePct: maxSlopePct,
    markedShare: markedShare,
    roadM: roadM,
    busyRoadM: busyRoadM,
    ferryM: ferryM,
    difficulty: difficulty,
    estimatedMs: walkingTimeMs(distanceM, gl.gainM, gl.lossM),
    hazards: hazards,
  );
}

const Map<CaiGrade, double> _difficultyPenalty = {CaiGrade.t: 0, CaiGrade.e: 0.1, CaiGrade.ee: 0.5, CaiGrade.eea: 1};

/// Lower is better. Distance, weighted up by how risky the route is: harder grades, faint
/// trails and busy roads cost extra, and so do roads in general when the user avoids them.
/// This is what makes the recommended route "the shortest of the safe ones".
double routeCost(RouteAnalysis a, bool avoidRoads) {
  final d = a.distanceM != 0 ? a.distanceM : 1;
  final faint = a.hazards.where((h) => h.kind == HazardKind.faint).firstOrNull?.value ?? 0;
  final risk =
      _difficultyPenalty[a.difficulty]! +
      (a.busyRoadM / d) * 1.5 +
      (a.ferryM / d) * 5 +
      faint / d * 0.5 +
      (a.roadM / d) * (avoidRoads ? 0.6 : 0.05) +
      (1 - a.markedShare) * 0.1;
  return d * (1 + risk);
}
