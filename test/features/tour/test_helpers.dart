import 'dart:math' as math;

import 'package:pania/features/tour/domain/track_progress.dart';
import 'package:pania/features/trail/domain/gps_coordinate.dart';

/// Degrees of latitude per meter.
const double m = 1 / 111195;
const double _baseLat = 46;
const double _baseLon = 11;
final double _kx = m / math.cos(_baseLat * math.pi / 180);

/// A point [northM] north and [eastM] east of the test origin.
LatLon at(double northM, [double eastM = 0]) => LatLon(_baseLat + northM * m, _baseLon + eastM * _kx);

/// A polyline through the given (north, east) corners, with a point every 10 m.
List<LatLon> line(List<(double, double)> corners) {
  final out = <LatLon>[];
  for (var c = 0; c < corners.length - 1; c++) {
    final (n0, e0) = corners[c];
    final (n1, e1) = corners[c + 1];
    final len = math.sqrt(math.pow(n1 - n0, 2) + math.pow(e1 - e0, 2));
    final steps = math.max(1, (len / 10).round());
    for (var i = c == 0 ? 0 : 1; i <= steps; i++) {
      out.add(at(n0 + (n1 - n0) * i / steps, e0 + (e1 - e0) * i / steps));
    }
  }
  return out;
}

/// Like [at], as a trail point.
GpsCoordinate gps(double northM, [double eastM = 0]) {
  final p = at(northM, eastM);
  return GpsCoordinate(latitude: p.latitude, longitude: p.longitude);
}
