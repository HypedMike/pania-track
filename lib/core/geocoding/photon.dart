import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/trail/domain/gps_coordinate.dart';
import '../http/error_detail.dart';
import '../i18n/i18n.dart';

/// Place search through Photon (https://photon.komoot.io), komoot's free OpenStreetMap geocoder.
/// It allows search-as-you-type; the query and the map centre are sent to the server.
const String _endpoint = 'https://photon.komoot.io/api/';

enum PlaceKind { peak, settlement, nature, other }

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.kind,
    required this.context,
    required this.latitude,
    required this.longitude,
    this.south,
    this.west,
    this.north,
    this.east,
  });

  final String id;
  final String name;
  final PlaceKind kind;

  /// "Capannori, Lucca, Italy"
  final String context;
  final double latitude;
  final double longitude;

  /// Extent of areas such as towns and parks.
  final double? south;
  final double? west;
  final double? north;
  final double? east;

  bool get hasBounds => south != null && west != null && north != null && east != null;
}

const _peaks = {'peak', 'volcano', 'saddle', 'ridge', 'hill', 'mountain_range'};
const _settlements = {'city', 'town', 'village', 'hamlet', 'suburb', 'locality', 'isolated_dwelling'};

PlaceKind _kindOf(String key, String value) {
  if (key == 'natural' && _peaks.contains(value)) return PlaceKind.peak;
  if (key == 'place' && _settlements.contains(value)) return PlaceKind.settlement;
  if (key == 'natural' || value == 'nature_reserve' || value == 'national_park') return PlaceKind.nature;
  return PlaceKind.other;
}

/// Photon has no Italian labels; "default" gives local names, which is what Italian users expect.
String _photonLang(AppLanguage language) => language == AppLanguage.it ? 'default' : 'en';

Future<List<Place>> searchPlaces(
  String query, {
  GpsCoordinate? near,
  required AppLanguage language,
  http.Client? client,
}) async {
  final params = {
    'q': query,
    'limit': '6',
    'lang': _photonLang(language),
    if (near != null) 'lat': near.latitude.toStringAsFixed(4),
    if (near != null) 'lon': near.longitude.toStringAsFixed(4),
  };
  final c = client ?? http.Client();
  try {
    http.Response response;
    try {
      response = await c
          .get(Uri.parse(_endpoint).replace(queryParameters: params))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw Exception(I18n.t('search.error.offline'));
    }
    if (response.statusCode != 200) {
      throw Exception(withDetail(I18n.t('search.error.server', {'status': response.statusCode}), response.body));
    }
    final features = ((jsonDecode(response.body) as Map<String, Object?>)['features'] as List?) ?? const [];
    final places = <Place>[];
    for (final f in features) {
      final feature = f as Map<String, Object?>;
      final p = feature['properties'] as Map<String, Object?>;
      final name = p['name'] as String?;
      if (name == null || name.isEmpty) continue;
      final coordinates = ((feature['geometry'] as Map)['coordinates'] as List).cast<num>();
      final context = <String>{
        for (final part in [p['city'], p['county'], p['country']])
          if (part is String && part.isNotEmpty && part != name) part,
      }.join(', ');
      final extent = (p['extent'] as List?)?.cast<num>();
      places.add(
        Place(
          id: '${p['osm_type']}${p['osm_id']}',
          name: name,
          kind: _kindOf('${p['osm_key']}', '${p['osm_value']}'),
          context: context,
          latitude: coordinates[1].toDouble(),
          longitude: coordinates[0].toDouble(),
          // extent is [minLon, maxLat, maxLon, minLat]
          south: extent?[3].toDouble(),
          west: extent?[0].toDouble(),
          north: extent?[1].toDouble(),
          east: extent?[2].toDouble(),
        ),
      );
    }
    return places;
  } finally {
    if (client == null) c.close();
  }
}
