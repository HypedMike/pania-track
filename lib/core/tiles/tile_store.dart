import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tile_math.dart';

const String tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _userAgent = 'flutter_map (com.michelesaladino.pania)';

/// An area whose map tiles are stored on the device.
class SavedRegion {
  const SavedRegion({
    required this.id,
    required this.name,
    required this.polygon,
    required this.maxZoom,
    required this.tiles,
    required this.bytes,
    required this.savedAt,
  });

  final String id;
  final String name;
  final List<LatLng> polygon;
  final int maxZoom;
  final int tiles;
  final int bytes;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'polygon': [
      for (final point in polygon) [point.latitude, point.longitude],
    ],
    'maxZoom': maxZoom,
    'tiles': tiles,
    'bytes': bytes,
    'savedAt': savedAt.toIso8601String(),
  };

  factory SavedRegion.fromJson(Map<String, Object?> json) => SavedRegion(
    id: json['id']! as String,
    name: json['name']! as String,
    polygon: [for (final point in json['polygon']! as List) LatLng((point as List)[0] as double, point[1] as double)],
    maxZoom: json['maxZoom']! as int,
    tiles: json['tiles']! as int,
    bytes: json['bytes']! as int,
    savedAt: DateTime.parse(json['savedAt']! as String),
  );
}

/// Thrown when a tile could not be fetched.
class TileDownloadException implements Exception {
  const TileDownloadException(this.tile);
  final TileId tile;

  @override
  String toString() => 'Could not download tile $tile';
}

/// Map tiles kept on disk, one file per tile (`tiles/z/x/y.png`), shared by all saved areas, plus
/// `regions.json` listing the areas.
abstract final class TileStore {
  static Directory? _root;
  static http.Client? _client;

  /// Finds the folder. Without it (tests) no tile is stored and the map uses the network.
  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _root = Directory(p.join(dir.path, 'saved_tiles'));
    await _root!.create(recursive: true);
  }

  static File? fileFor(TileId tile) {
    final root = _root;
    return root == null ? null : File(p.join(root.path, 'tiles', '${tile.z}', '${tile.x}', '${tile.y}.png'));
  }

  static File? get _index => _root == null ? null : File(p.join(_root!.path, 'regions.json'));

  static Future<List<SavedRegion>> regions() async {
    final file = _index;
    if (file == null || !await file.exists()) return [];
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      return [for (final r in list) SavedRegion.fromJson((r as Map).cast<String, Object?>())];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeRegions(List<SavedRegion> regions) async {
    await _index!.writeAsString(jsonEncode([for (final r in regions) r.toJson()]), flush: true);
  }

  /// Downloads the tiles of [polygon] up to [maxZoom] and records the area. Tiles already on the
  /// device are kept as they are. Throws [TileDownloadException] if a tile cannot be fetched, and
  /// removes what this call downloaded. Returns null when [isCancelled] turned true.
  static Future<SavedRegion?> save({
    required String name,
    required List<LatLng> polygon,
    required int maxZoom,
    required void Function(int done, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final root = _root;
    if (root == null) throw StateError('TileStore.init was not called');
    final tiles = tilesCovering(polygon, minSavedZoom, maxZoom).tiles;
    final client = _client ??= http.Client();
    final created = <File>[];
    var done = 0;
    var bytes = 0;
    Object? failure;
    var next = 0;

    onProgress(0, tiles.length);
    Future<void> worker() async {
      while (failure == null && !isCancelled()) {
        if (next >= tiles.length) return;
        final tile = tiles[next++];
        final file = fileFor(tile)!;
        try {
          if (await file.exists()) {
            bytes += await file.length();
          } else {
            final data = await _fetch(client, tile);
            await file.parent.create(recursive: true);
            final part = File('${file.path}.part');
            await part.writeAsBytes(data, flush: true);
            await part.rename(file.path);
            created.add(file);
            bytes += data.length;
          }
          onProgress(++done, tiles.length);
        } catch (_) {
          failure ??= TileDownloadException(tile);
        }
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);

    if (failure != null || isCancelled()) {
      for (final file in created) {
        await _delete(file);
      }
      if (failure != null) throw failure!;
      return null;
    }

    final region = SavedRegion(
      id: const Uuid().v4(),
      name: name,
      polygon: polygon,
      maxZoom: maxZoom,
      tiles: tiles.length,
      bytes: bytes,
      savedAt: DateTime.now(),
    );
    await _writeRegions([region, ...await regions()]);
    return region;
  }

  static Future<Uint8List> _fetch(http.Client client, TileId tile) async {
    final url = Uri.parse(
      tileUrlTemplate.replaceAll('{z}', '${tile.z}').replaceAll('{x}', '${tile.x}').replaceAll('{y}', '${tile.y}'),
    );
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await client
            .get(url, headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) return response.bodyBytes;
        throw TileDownloadException(tile);
      } catch (e) {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Forgets an area and deletes the tiles no other saved area needs.
  static Future<void> delete(String id) async {
    final all = await regions();
    final gone = all.where((r) => r.id == id).firstOrNull;
    if (gone == null) return;
    final rest = all.where((r) => r.id != id).toList();
    await _writeRegions(rest);

    final kept = <TileId>{
      for (final r in rest) ...tilesCovering(r.polygon, minSavedZoom, r.maxZoom, limit: 1 << 30).tiles,
    };
    for (final tile in tilesCovering(gone.polygon, minSavedZoom, gone.maxZoom, limit: 1 << 30).tiles) {
      if (!kept.contains(tile)) await _delete(fileFor(tile)!);
    }
  }
}

/// The network tile provider, except that a tile saved on the device is read from disk.
class OfflineTileProvider extends NetworkTileProvider {
  OfflineTileProvider._() : super(httpClient: http.Client());

  /// One shared instance: the map layers are rebuilt often and each would otherwise open its own client.
  static final OfflineTileProvider shared = OfflineTileProvider._();

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final file = TileStore.fileFor(TileId(coordinates.z, coordinates.x, coordinates.y));
    if (file != null && file.existsSync()) return FileImage(file);
    return super.getImageWithCancelLoadingSupport(coordinates, options, cancelLoading);
  }
}
