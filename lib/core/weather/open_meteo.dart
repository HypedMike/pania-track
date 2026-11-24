import 'dart:convert';

import 'package:http/http.dart' as http;

/// Hourly forecast from Open-Meteo (https://open-meteo.com), a free weather API that needs no key.
/// Only a latitude and longitude are sent, nothing that identifies the person.
const String _endpoint = 'https://api.open-meteo.com/v1/forecast';

class HourForecast {
  const HourForecast({
    required this.time,
    required this.temperatureC,
    required this.precipProbPct,
    required this.precipMm,
    required this.code,
    required this.gustKmh,
  });

  /// Start of the hour, in milliseconds since the epoch.
  final int time;
  final double temperatureC;

  /// Chance of precipitation, 0–100.
  final double precipProbPct;

  /// Expected precipitation during the hour, in mm.
  final double precipMm;

  /// WMO weather code.
  final int code;
  final double gustKmh;
}

Future<List<HourForecast>> fetchForecast(double latitude, double longitude, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {
        'latitude': latitude.toStringAsFixed(3),
        'longitude': longitude.toStringAsFixed(3),
        'hourly': 'temperature_2m,precipitation_probability,precipitation,weather_code,wind_gusts_10m',
        'wind_speed_unit': 'kmh',
        'forecast_days': '2',
        // GMT, so the hourly timestamps below are UTC and need no time zone handling.
        'timezone': 'GMT',
      },
    );
    final response = await c.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('Weather service answered ${response.statusCode}');
    final hourly = (jsonDecode(response.body) as Map<String, Object?>)['hourly'] as Map<String, Object?>?;
    if (hourly == null) throw Exception('Weather service sent no forecast');
    final times = (hourly['time'] as List).cast<String>();
    double at(String key, int i) => ((hourly[key] as List)[i] as num?)?.toDouble() ?? 0;
    return [
      for (var i = 0; i < times.length; i++)
        HourForecast(
          time: DateTime.parse('${times[i]}:00Z').millisecondsSinceEpoch,
          temperatureC: at('temperature_2m', i),
          precipProbPct: at('precipitation_probability', i),
          precipMm: at('precipitation', i),
          code: at('weather_code', i).round(),
          gustKmh: at('wind_gusts_10m', i),
        ),
    ];
  } finally {
    if (client == null) c.close();
  }
}
