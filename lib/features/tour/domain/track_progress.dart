import 'dart:math' as math;

import '../../trail/domain/gps_coordinate.dart';

const double _earthRadiusM = 6371000;
double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// A latitude/longitude pair.
class LatLon {
  const LatLon(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// A trail prepared for fast "where am I on it" queries.
class TrackIndex {
  const TrackIndex({required this.coords, required this.cumulativeM, required this.totalM});

  final List<LatLon> coords;

  /// `cumulativeM[i]` is the distance along the trail from its start to point `i`.
  final List<double> cumulativeM;
  final double totalM;
}

/// Great-circle distance in meters.
double distanceM(LatLon a, LatLon b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(h.toDouble()));
}

LatLon latLonOf(GpsCoordinate c) => LatLon(c.latitude, c.longitude);

TrackIndex buildTrackIndex(List<LatLon> coords) {
  final cumulative = <double>[0];
  for (var i = 1; i < coords.length; i++) {
    cumulative.add(cumulative[i - 1] + distanceM(coords[i - 1], coords[i]));
  }
  return TrackIndex(coords: coords, cumulativeM: cumulative, totalM: cumulative.isEmpty ? 0 : cumulative.last);
}

/// Compass bearing from [a] to [b], in degrees clockwise from north, 0–360.
double bearingDeg(LatLon a, LatLon b) {
  final dLon = _rad(b.longitude - a.longitude);
  final y = math.sin(dLon) * math.cos(_rad(b.latitude));
  final x =
      math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
      math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(dLon);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Smallest signed difference `to − from` between two bearings, in (−180, 180].
double bearingDelta(double from, double to) {
  final d = (((to - from) % 360) + 540) % 360 - 180;
  return d == -180 ? 180 : d;
}

/// The point at [distM] along the trail (clamped to its ends).
LatLon pointAtDistance(TrackIndex index, double distM) {
  final coords = index.coords;
  final cumulative = index.cumulativeM;
  if (coords.isEmpty) throw StateError('Empty trail');
  if (distM <= 0) return coords.first;
  if (distM >= index.totalM) return coords.last;
  var lo = 0;
  var hi = cumulative.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (cumulative[mid] <= distM) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final span = cumulative[hi] - cumulative[lo];
  final f = span > 0 ? (distM - cumulative[lo]) / span : 0.0;
  return LatLon(
    coords[lo].latitude + (coords[hi].latitude - coords[lo].latitude) * f,
    coords[lo].longitude + (coords[hi].longitude - coords[lo].longitude) * f,
  );
}

class TrackProjection {
  const TrackProjection({required this.offTrackM, required this.alongM, required this.nearest});

  /// How far the position is from the nearest point of the trail, in meters.
  final double offTrackM;

  /// Distance from the trail's start to the nearest point, in meters.
  final double alongM;

  /// The nearest point on the trail.
  final LatLon nearest;
}

/// Segments this close to the best match all count as "the same place" when choosing among them.
const double _ambiguityM = 15;

class _Candidate {
  _Candidate(this.dist, this.along, this.lat, this.lon);
  final double dist;
  final double along;
  final double lat;
  final double lon;
}

/// Finds where on the trail a position is. Loops and out-and-back trails pass the same place more
/// than once; the pass nearest to [previousAlongM] wins, so progress doesn't jump to another lap.
TrackProjection projectOnTrack(TrackIndex index, LatLon position, [double? previousAlongM]) {
  final coords = index.coords;
  final cumulative = index.cumulativeM;
  if (coords.isEmpty) throw StateError('Empty trail');
  if (coords.length == 1) {
    return TrackProjection(offTrackM: distanceM(coords.first, position), alongM: 0, nearest: coords.first);
  }

  // Local flat projection around the position: accurate to well under a meter for the
  // distances that matter here, and much cheaper than great-circle maths per segment.
  final kx = _earthRadiusM * math.cos(_rad(position.latitude)) * (math.pi / 180);
  const ky = _earthRadiusM * (math.pi / 180);

  final candidates = <_Candidate>[];
  var best = double.infinity;

  for (var i = 0; i < coords.length - 1; i++) {
    final ax = (coords[i].longitude - position.longitude) * kx;
    final ay = (coords[i].latitude - position.latitude) * ky;
    final bx = (coords[i + 1].longitude - position.longitude) * kx;
    final by = (coords[i + 1].latitude - position.latitude) * ky;
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    // The position is the origin; project it on the segment.
    final f = len2 > 0 ? math.max(0.0, math.min(1.0, -(ax * dx + ay * dy) / len2)) : 0.0;
    final px = ax + dx * f;
    final py = ay + dy * f;
    final dist = math.sqrt(px * px + py * py);
    if (dist > best + _ambiguityM) continue;
    if (dist < best) best = dist;
    candidates.add(
      _Candidate(
        dist,
        cumulative[i] + (cumulative[i + 1] - cumulative[i]) * f,
        coords[i].latitude + (coords[i + 1].latitude - coords[i].latitude) * f,
        coords[i].longitude + (coords[i + 1].longitude - coords[i].longitude) * f,
      ),
    );
  }

  // Several passes of a loop or out-and-back can be about equally close. Find the pass nearest to
  // where the person was, then take the closest point within that pass. Segments next to each
  // other belong to one pass, and the farther off the trail the more of them are about as close.
  final close = candidates.where((c) => c.dist <= best + _ambiguityM).toList();
  final passRadius = 1.5 * (best + _ambiguityM) + 50;
  var anchor = close.reduce((a, b) => b.dist < a.dist ? b : a);
  if (previousAlongM != null) {
    for (final c in close) {
      if ((c.along - previousAlongM).abs() < (anchor.along - previousAlongM).abs()) anchor = c;
    }
  }
  var pick = anchor;
  for (final c in close) {
    if ((c.along - anchor.along).abs() <= passRadius && c.dist < pick.dist) pick = c;
  }
  return TrackProjection(offTrackM: pick.dist, alongM: pick.along, nearest: LatLon(pick.lat, pick.lon));
}

enum TurnDirection { left, right }

class Turn {
  const Turn({required this.direction, required this.inM, required this.sharp});

  final TurnDirection direction;

  /// Distance ahead, in meters.
  final double inM;

  /// True for turns of more than ~120°.
  final bool sharp;
}

/// The trail is looked at in chords of this length, which smooths out GPS wobble.
const double _chordM = 30;
const double _turnThresholdDeg = 45;
const double _sharpDeg = 120;

/// The next turn within [lookAheadM], if any: the first place where the trail's heading has
/// changed by more than 45° from the heading right now.
Turn? nextTurn(TrackIndex index, double alongM, [double lookAheadM = 300]) {
  final remaining = index.totalM - alongM;
  if (remaining < _chordM * 3) return null;
  double heading(double s) => bearingDeg(pointAtDistance(index, s), pointAtDistance(index, s + _chordM));
  final reference = heading(alongM);
  final limit = math.min(lookAheadM, remaining - _chordM);
  for (var s = _chordM; s <= limit; s += _chordM) {
    final delta = bearingDelta(reference, heading(alongM + s));
    if (delta.abs() >= _turnThresholdDeg) {
      return Turn(
        direction: delta > 0 ? TurnDirection.right : TurnDirection.left,
        inM: s,
        sharp: delta.abs() >= _sharpDeg,
      );
    }
  }
  return null;
}

/// "N", "NE", … for a bearing.
String compassPoint(double bearing) {
  const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return points[(bearing / 45).round() % 8];
}

/// The part of the trail from its start to [alongM], ending exactly at that point.
List<LatLon> trackUpTo(TrackIndex index, double alongM) {
  final coords = index.coords;
  final cumulative = index.cumulativeM;
  if (coords.isEmpty || alongM <= 0) return [];
  final done = <LatLon>[];
  for (var i = 0; i < coords.length && cumulative[i] < alongM; i++) {
    done.add(coords[i]);
  }
  done.add(pointAtDistance(index, alongM));
  return done;
}
