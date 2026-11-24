import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/trail/domain/gps_coordinate.dart';

/// Terrain elevation from Open-Meteo's elevation API (https://open-meteo.com/en/docs/elevation-api,
/// a 90 m terrain model, free and without a key). A phone's GPS altitude is noisy, the terrain
/// model is smooth, so it gives a more believable climb. Only coordinates are sent.
const String _endpoint = 'https://api.open-meteo.com/v1/elevation';

/// The API takes up to 100 coordinates per request.
const int _batch = 100;

/// The terrain model is 90 m wide, so asking more often than every ~75 m says nothing new.
const int _maxSamples = 400;

/// [count] indices spread evenly over `0 … n-1`, always including the first and the last.
List<int> sampleIndices(int n, int count) {
  if (n <= 0) return [];
  if (n <= count) return List.generate(n, (i) => i);
  return List.generate(count, (i) => (i * (n - 1) / (count - 1)).round());
}

/// Values known at some indices, spread to every index in between by straight lines.
List<double> interpolateByIndex(List<int> indices, List<double> values, int n) {
  final out = List<double>.filled(n, 0);
  var k = 0;
  for (var i = 0; i < n; i++) {
    while (k + 1 < indices.length && indices[k + 1] <= i) {
      k++;
    }
    if (k + 1 >= indices.length || i <= indices[k]) {
      out[i] = values[k < values.length - 1 ? k : values.length - 1];
    } else {
      final f = (i - indices[k]) / (indices[k + 1] - indices[k]);
      out[i] = values[k] + (values[k + 1] - values[k]) * f;
    }
  }
  return out;
}

/// One terrain elevation, in meters, for every coordinate. Throws when the service cannot be reached.
Future<List<double>> fetchTerrainElevations(List<GpsCoordinate> coords, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final indices = sampleIndices(coords.length, _maxSamples);
    final elevations = <double>[];
    for (var i = 0; i < indices.length; i += _batch) {
      final chunk = indices.skip(i).take(_batch).map((idx) => coords[idx]).toList();
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {
          'latitude': chunk.map((p) => p.latitude.toStringAsFixed(5)).join(','),
          'longitude': chunk.map((p) => p.longitude.toStringAsFixed(5)).join(','),
        },
      );
      final response = await c.get(uri);
      if (response.statusCode != 200) throw Exception('Elevation service answered ${response.statusCode}');
      final body = jsonDecode(response.body) as Map<String, Object?>;
      final elevation = (body['elevation'] as List?)?.map((e) => (e as num).toDouble()).toList();
      if (elevation == null || elevation.length != chunk.length) throw Exception('Elevation service sent no data');
      elevations.addAll(elevation);
    }
    return interpolateByIndex(indices, elevations, coords.length);
  } finally {
    if (client == null) c.close();
  }
}
