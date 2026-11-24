import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../features/trail/domain/gps_coordinate.dart';
import '../i18n/i18n.dart';

const double _earthRadiusM = 6371000;

/// Altitude changes below this are treated as GPS noise when summing elevation gain.
const double _elevationNoiseM = 3;

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance between two points, in meters.
double haversine(GpsCoordinate a, GpsCoordinate b) => haversineLatLon(a.latitude, a.longitude, b.latitude, b.longitude);

double haversineLatLon(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final h =
      math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(h.toDouble()));
}

class TrailStats {
  const TrailStats({required this.distanceM, this.elevationGainM, this.highestM, this.lowestM, this.durationMs});

  final double distanceM;
  final double? elevationGainM;
  final double? highestM;
  final double? lowestM;
  final int? durationMs;
}

TrailStats computeStats(List<GpsCoordinate> coords) {
  var distance = 0.0;
  for (var i = 1; i < coords.length; i++) {
    distance += haversine(coords[i - 1], coords[i]);
  }

  final alts = [
    for (final c in coords)
      if (c.altitude != null) c.altitude!,
  ];
  var gain = 0.0;
  if (alts.isNotEmpty) {
    var ref = alts.first;
    for (final alt in alts) {
      if (alt - ref >= _elevationNoiseM) {
        gain += alt - ref;
        ref = alt;
      } else if (ref - alt >= _elevationNoiseM) {
        ref = alt;
      }
    }
  }

  final times = [
    for (final c in coords)
      if (c.timestamp != null) c.timestamp!.millisecondsSinceEpoch,
  ];
  return TrailStats(
    distanceM: distance,
    elevationGainM: alts.isNotEmpty ? gain : null,
    highestM: alts.isNotEmpty ? alts.reduce(math.max) : null,
    lowestM: alts.isNotEmpty ? alts.reduce(math.min) : null,
    durationMs: times.length > 1 ? times.last - times.first : null,
  );
}

String formatDistance(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

String formatElevation(double? m, {bool signed = false}) {
  if (m == null) return '—';
  return '${signed && m > 0 ? '+' : ''}${m.round()} m';
}

String formatDuration(int? ms) {
  if (ms == null) return '—';
  final totalMin = (ms / 60000).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
}

/// "Nov 24".
String formatDate(DateTime? date) {
  if (date == null) return '';
  return DateFormat.MMMd(I18n.locale).format(date.toLocal());
}

/// Average pace as "m:ss /km", or "—" when there is no distance yet.
String formatPace(double distanceM, int movingMs) {
  if (distanceM < 50) return '—';
  final secPerKm = movingMs / 1000 / (distanceM / 1000);
  final m = secPerKm ~/ 60;
  var s = (secPerKm % 60).round();
  final minutes = s == 60 ? m + 1 : m;
  if (s == 60) s = 0;
  return '$minutes:${s.toString().padLeft(2, '0')} /km';
}

/// Clock-style duration, "hh:mm:ss".
String formatClock(int ms) {
  final total = math.max(0, ms ~/ 1000);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(total ~/ 3600)}:${pad((total % 3600) ~/ 60)}:${pad(total % 60)}';
}
