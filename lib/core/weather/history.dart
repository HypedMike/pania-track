import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/trail/domain/gps_coordinate.dart';

/// Past weather from Open-Meteo's archive (https://open-meteo.com/en/docs/historical-weather-api),
/// to see how temperature and rain affected the person's pace. Only a coordinate and a date go
/// out. The archive trails real time by a few days, so very recent walks have no weather yet.
const String _endpoint = 'https://archive-api.open-meteo.com/v1/archive';
const String _cachePrefix = 'pania.weather.';
const int _hourMs = 3600000;

class WalkWeather {
  const WalkWeather({required this.tempC, required this.precipMm});

  final double tempC;

  /// Rain over the walk, in mm.
  final double precipMm;

  Map<String, Object?> toJson() => {'tempC': tempC, 'precipMm': precipMm};

  factory WalkWeather.fromJson(Map<String, Object?> json) =>
      WalkWeather(tempC: (json['tempC'] as num).toDouble(), precipMm: (json['precipMm'] as num).toDouble());
}

/// Average temperature and total rain over the hours a walk touched. `null` if no hour has data.
/// [hourly] has `time` ("YYYY-MM-DDTHH:00" in GMT), `temperature_2m` and `precipitation`.
WalkWeather? summarizeWalkWeather(Map<String, List<Object?>> hourly, int fromMs, int toMs) {
  var tempSum = 0.0;
  var tempCount = 0;
  var precip = 0.0;
  final times = hourly['time']!.cast<String>();
  for (var i = 0; i < times.length; i++) {
    final start = DateTime.tryParse('${times[i]}:00Z')?.millisecondsSinceEpoch;
    if (start == null || start + _hourMs <= fromMs || start > toMs) continue;
    final t = hourly['temperature_2m']![i] as num?;
    if (t != null) {
      tempSum += t;
      tempCount++;
    }
    precip += (hourly['precipitation']![i] as num?) ?? 0;
  }
  return tempCount == 0 ? null : WalkWeather(tempC: tempSum / tempCount, precipMm: precip);
}

String _day(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String().substring(0, 10);

/// The weather during a trail, from where it started and the times of its first and last points.
/// Cached per trail, since the past does not change. `null` for trails without times, and when
/// the archive does not have the day yet (not cached, so it is asked again later).
Future<WalkWeather?> fetchWalkWeather(
  String trailId,
  List<GpsCoordinate> coords,
  SharedPreferences prefs, {
  http.Client? client,
}) async {
  final cached = prefs.getString('$_cachePrefix$trailId');
  if (cached != null) {
    try {
      final decoded = jsonDecode(cached);
      return decoded == null ? null : WalkWeather.fromJson((decoded as Map).cast());
    } catch (_) {
      // Fall through and look it up again.
    }
  }
  final times = [
    for (final c in coords)
      if (c.timestamp != null) c.timestamp!.millisecondsSinceEpoch,
  ];
  if (times.length < 2 || coords.isEmpty) return null;
  final from = times.reduce((a, b) => a < b ? a : b);
  final to = times.reduce((a, b) => a > b ? a : b);
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'latitude': coords.first.latitude.toStringAsFixed(3),
        'longitude': coords.first.longitude.toStringAsFixed(3),
        'start_date': _day(from),
        'end_date': _day(to),
        'hourly': 'temperature_2m,precipitation',
        'timezone': 'GMT',
      },
    );
    final response = await c.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Weather archive answered ${response.statusCode}');
    final hourly = (jsonDecode(response.body) as Map<String, Object?>)['hourly'] as Map<String, Object?>?;
    final summary = hourly == null
        ? null
        : summarizeWalkWeather({for (final e in hourly.entries) e.key: (e.value as List).cast<Object?>()}, from, to);
    // A day the archive has not caught up with yet comes back empty: do not remember that.
    if (summary != null) await prefs.setString('$_cachePrefix$trailId', jsonEncode(summary.toJson()));
    return summary;
  } finally {
    if (client == null) c.close();
  }
}
