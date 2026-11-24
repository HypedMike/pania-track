import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/trail/domain/gps_coordinate.dart';
import '../http/error_detail.dart';
import '../i18n/i18n.dart';

/// Client for the public BRouter server (https://brouter.de), an OpenStreetMap router with
/// elevation data. No API key is needed; the checkpoints' coordinates are sent to the server.
const String _endpoint = 'https://brouter.de/brouter';

/// BRouter routing profiles used by the planner.
/// - [hikingMountain] prefers marked footpaths and avoids roads where it can.
/// - [shortest] takes the shortest legal walking line, roads included.
enum RoutingProfile {
  hikingMountain('hiking-mountain'),
  shortest('shortest');

  const RoutingProfile(this.id);
  final String id;
}

/// A stretch of the route along one OSM way, with that way's tags (highway, sac_scale, …).
class WaySegment {
  const WaySegment({required this.distanceM, required this.tags});

  final double distanceM;
  final Map<String, String> tags;
}

class RoutedPath {
  const RoutedPath({required this.coordinates, required this.segments});

  final List<GpsCoordinate> coordinates;
  final List<WaySegment> segments;
}

Map<String, String> _parseTags(String text) {
  final tags = <String, String>{};
  for (final pair in text.split(' ')) {
    final eq = pair.indexOf('=');
    if (eq > 0) tags[pair.substring(0, eq)] = pair.substring(eq + 1);
  }
  return tags;
}

/// BRouter's `messages` table: a header row, then one row per way segment.
List<WaySegment> parseSegments(List<List<String>> messages) {
  if (messages.isEmpty) return [];
  final header = messages.first;
  final distance = header.indexOf('Distance');
  final wayTags = header.indexOf('WayTags');
  return [
    for (final row in messages.skip(1))
      WaySegment(
        distanceM: distance >= 0 && distance < row.length ? double.tryParse(row[distance]) ?? 0 : 0,
        tags: _parseTags(wayTags >= 0 && wayTags < row.length ? row[wayTags] : ''),
      ),
  ];
}

Exception _friendlyError(int status, String body) {
  if (RegExp(r'not mapped|no track found|target island', caseSensitive: false).hasMatch(body)) {
    return Exception(I18n.t('plan.error.noPath'));
  }
  if (RegExp(r'distance|too long|limit', caseSensitive: false).hasMatch(body)) {
    return Exception(I18n.t('plan.error.tooLong'));
  }
  return Exception(withDetail(I18n.t('plan.error.server', {'status': status}), body));
}

/// Routes through [points] in order. Throws an [Exception] with a user-facing message.
Future<RoutedPath> fetchRoute(
  List<GpsCoordinate> points,
  RoutingProfile profile,
  int alternative, {
  http.Client? client,
}) async {
  final lonlats = points.map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}').join('|');
  final uri = Uri.parse('$_endpoint?lonlats=$lonlats&profile=${profile.id}&alternativeidx=$alternative&format=geojson');
  final c = client ?? http.Client();
  try {
    http.Response response;
    try {
      response = await c.get(uri).timeout(const Duration(seconds: 40));
    } catch (_) {
      throw Exception(I18n.t('plan.error.offline'));
    }
    if (response.statusCode != 200) throw _friendlyError(response.statusCode, response.body);
    final features = ((jsonDecode(response.body) as Map<String, Object?>)['features'] as List?) ?? const [];
    if (features.isEmpty) throw Exception(I18n.t('plan.error.noPath'));
    final feature = features.first as Map<String, Object?>;
    final coords = ((feature['geometry'] as Map)['coordinates'] as List).cast<List>();
    final messages = (((feature['properties'] as Map)['messages'] as List?) ?? const [])
        .map((row) => (row as List).map((e) => '$e').toList())
        .toList();
    return RoutedPath(
      coordinates: [
        for (final c in coords)
          GpsCoordinate(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble(),
            altitude: c.length > 2 ? (c[2] as num?)?.toDouble() : null,
          ),
      ],
      segments: parseSegments(messages),
    );
  } finally {
    if (client == null) c.close();
  }
}
