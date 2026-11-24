import 'dart:math' as math;

import '../../../core/gps/trail_stats.dart';
import '../../trail/domain/gps_coordinate.dart';

/// Grade classes used to colour the profile, by absolute grade in percent.
const List<double> gradeSteps = [8, 15, 25];

int gradeClass(double pct) {
  final i = gradeSteps.indexWhere((step) => pct.abs() < step);
  return i == -1 ? gradeSteps.length : i;
}

class ProfilePoint {
  const ProfilePoint(this.d, this.alt, this.coordinate);

  /// Distance from the start, in meters.
  final double d;
  final double alt;
  final GpsCoordinate coordinate;
}

/// A stretch of the profile with one grade, signed (negative = downhill).
class ProfileBin {
  const ProfileBin(this.from, this.to, this.gradePct);

  final double from;
  final double to;
  final double gradePct;
}

class RouteProfile {
  const RouteProfile({
    required this.points,
    required this.bins,
    required this.totalM,
    required this.minAlt,
    required this.maxAlt,
  });

  final List<ProfilePoint> points;
  final List<ProfileBin> bins;
  final double totalM;
  final double minAlt;
  final double maxAlt;
}

/// Bins are at least this long: the router's elevation model has ~90 m cells.
const double _minBinM = 150;
const int _maxBins = 60;

/// Elevation at distance [d], interpolated between profile points.
double altAt(List<ProfilePoint> points, double d) {
  var lo = 0;
  var hi = points.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (points[mid].d <= d) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final a = points[lo];
  final b = points[hi];
  if (b.d == a.d) return a.alt;
  return a.alt + (b.alt - a.alt) * (d - a.d) / (b.d - a.d);
}

/// Elevation against distance, cut into bins coloured by grade. Null without elevation data.
RouteProfile? buildProfile(List<GpsCoordinate> coordinates) {
  final points = <ProfilePoint>[];
  var d = 0.0;
  for (var i = 0; i < coordinates.length; i++) {
    if (i > 0) d += haversine(coordinates[i - 1], coordinates[i]);
    final alt = coordinates[i].altitude;
    if (alt != null) points.add(ProfilePoint(d, alt, coordinates[i]));
  }
  if (points.length < 2 || d == 0) return null;
  final totalM = d;
  final binM = math.max(_minBinM, totalM / _maxBins);
  final count = math.max(1, (totalM / binM).round());
  final bins = <ProfileBin>[];
  for (var i = 0; i < count; i++) {
    final from = totalM * i / count;
    final to = totalM * (i + 1) / count;
    bins.add(ProfileBin(from, to, (altAt(points, to) - altAt(points, from)) / (to - from) * 100));
  }
  final alts = points.map((p) => p.alt);
  return RouteProfile(
    points: points,
    bins: bins,
    totalM: totalM,
    minAlt: alts.reduce(math.min),
    maxAlt: alts.reduce(math.max),
  );
}

/// Profile point closest to distance [d].
ProfilePoint pointAtProfile(RouteProfile profile, double d) {
  var best = profile.points.first;
  for (final p in profile.points) {
    if ((p.d - d).abs() < (best.d - d).abs()) best = p;
  }
  return best;
}

ProfileBin binAt(RouteProfile profile, double d) =>
    profile.bins.where((b) => d <= b.to).firstOrNull ?? profile.bins.last;

/// Distance along the route at which it passes each checkpoint. Searched in order, so an
/// out-and-back route that passes a spot twice gets the right pass.
List<double> checkpointDistances(RouteProfile profile, List<GpsCoordinate> checkpoints) {
  final result = <double>[];
  var from = 0;
  for (final c in checkpoints) {
    var bestI = from;
    var bestD = double.infinity;
    for (var i = from; i < profile.points.length; i++) {
      final dist = haversine(c, profile.points[i].coordinate);
      if (dist < bestD) {
        bestD = dist;
        bestI = i;
      }
    }
    result.add(profile.points[bestI].d);
    from = bestI;
  }
  return result;
}
