import 'dart:math' as math;

/// Sunrise and sunset from the "sunrise equation" (https://en.wikipedia.org/wiki/Sunrise_equation).
/// Accurate to a few minutes at mid-latitudes, which is plenty for "you'll arrive after dark".
/// No network needed.
const double _j2000 = 2451545.0;
const int _dayMs = 86400000;
double _rad(double deg) => deg * math.pi / 180;

int _jdToMs(double jd) => ((jd - 2440587.5) * _dayMs).round();
double _msToJd(int ms) => ms / _dayMs + 2440587.5;

enum SunEventType { sunrise, sunset }

class SunEvent {
  const SunEvent(this.type, this.time);

  final SunEventType type;

  /// Milliseconds since the epoch.
  final int time;
}

/// Sunrise and sunset of solar day number [n], or none in polar day / polar night.
List<SunEvent> _eventsForDay(int n, double lat, double lon) {
  final jStar = n - lon / 360; // solar noon comes earlier the further east you are
  final m = (357.5291 + 0.98560028 * jStar) % 360;
  final c = 1.9148 * math.sin(_rad(m)) + 0.02 * math.sin(_rad(2 * m)) + 0.0003 * math.sin(_rad(3 * m));
  final lambda = (m + c + 180 + 102.9372) % 360;
  final transit = _j2000 + jStar + 0.0053 * math.sin(_rad(m)) - 0.0069 * math.sin(_rad(2 * lambda));
  final sinDecl = math.sin(_rad(lambda)) * math.sin(_rad(23.4397));
  final cosDecl = math.cos(math.asin(sinDecl));
  final cosOmega = (math.sin(_rad(-0.833)) - math.sin(_rad(lat)) * sinDecl) / (math.cos(_rad(lat)) * cosDecl);
  if (cosOmega < -1 || cosOmega > 1) return [];
  final omega = math.acos(cosOmega) * 180 / math.pi;
  return [
    SunEvent(SunEventType.sunrise, _jdToMs(transit - omega / 360)),
    SunEvent(SunEventType.sunset, _jdToMs(transit + omega / 360)),
  ];
}

/// Sunrises and sunsets around [atMs] (about five days of them), in time order.
List<SunEvent> sunEvents(double lat, double lon, int atMs) {
  final n = (_msToJd(atMs) - _j2000 + 0.0008 + lon / 360).round();
  final all = <SunEvent>[];
  for (var d = -2; d <= 2; d++) {
    all.addAll(_eventsForDay(n + d, lat, lon));
  }
  all.sort((a, b) => a.time.compareTo(b.time));
  return all;
}

/// The next sunset at or after [fromMs], or null where the sun does not set.
int? nextSunset(double lat, double lon, int fromMs) {
  for (final e in sunEvents(lat, lon, fromMs)) {
    if (e.type == SunEventType.sunset && e.time >= fromMs) return e.time;
  }
  return null;
}

/// Whether the sun is below the horizon at [atMs]. Polar day and night count as light.
bool isDark(double lat, double lon, int atMs) {
  final before = sunEvents(lat, lon, atMs).where((e) => e.time <= atMs).toList();
  return before.isNotEmpty && before.last.type == SunEventType.sunset;
}
