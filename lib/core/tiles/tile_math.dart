import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Lowest zoom saved for an area: below this the tiles are too coarse to matter.
const int minSavedZoom = 10;

/// Zoom levels the person can save up to.
const List<int> savedZoomLevels = [13, 14, 15, 16];

/// The most tiles one saved area may hold. OpenStreetMap's public servers are not meant for bulk
/// downloads, so one area stays small.
const int maxTilesPerArea = 3000;

/// Typical size of one OpenStreetMap raster tile.
const int averageTileBytes = 16 * 1024;

/// A map tile: zoom [z], column [x], row [y].
class TileId {
  const TileId(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) => other is TileId && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

int tileX(double lng, int z) => (((lng + 180) / 360) * (1 << z)).floor().clamp(0, (1 << z) - 1);

int tileY(double lat, int z) {
  final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z);
  return y.floor().clamp(0, (1 << z) - 1);
}

double _tileLng(num x, int z) => x / (1 << z) * 360 - 180;

double _tileLat(num y, int z) {
  final n = math.pi - 2 * math.pi * y / (1 << z);
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

/// Ray casting: is the point inside the polygon (implicitly closed)?
bool pointInPolygon(double lat, double lng, List<LatLng> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.latitude > lat) != (b.latitude > lat) &&
        lng < (b.longitude - a.longitude) * (lat - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

/// Past this many tiles in the bounding box a zoom level is not even scanned.
const int _scanLimit = 300000;

/// Tiles that touch [polygon], from [minZoom] to [maxZoom]. Stops after [limit] tiles
/// (a [TileCount.exceeded] result) so a huge shape does not freeze the app.
TileCount tilesCovering(List<LatLng> polygon, int minZoom, int maxZoom, {int limit = maxTilesPerArea}) {
  final tiles = <TileId>[];
  if (polygon.length < 3) return TileCount(tiles, false);
  final south = polygon.map((p) => p.latitude).reduce(math.min);
  final north = polygon.map((p) => p.latitude).reduce(math.max);
  final west = polygon.map((p) => p.longitude).reduce(math.min);
  final east = polygon.map((p) => p.longitude).reduce(math.max);

  for (var z = minZoom; z <= maxZoom; z++) {
    final x0 = tileX(west, z), x1 = tileX(east, z);
    final y0 = tileY(north, z), y1 = tileY(south, z);
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > _scanLimit) return TileCount(tiles, true);
    final vertexTiles = {for (final p in polygon) TileId(z, tileX(p.longitude, z), tileY(p.latitude, z))};
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final id = TileId(z, x, y);
        final w = _tileLng(x, z), e = _tileLng(x + 1, z);
        final n = _tileLat(y, z), s = _tileLat(y + 1, z);
        final touches =
            vertexTiles.contains(id) ||
            pointInPolygon((n + s) / 2, (w + e) / 2, polygon) ||
            pointInPolygon(n, w, polygon) ||
            pointInPolygon(n, e, polygon) ||
            pointInPolygon(s, w, polygon) ||
            pointInPolygon(s, e, polygon);
        if (!touches) continue;
        if (tiles.length >= limit) return TileCount(tiles, true);
        tiles.add(id);
      }
    }
  }
  return TileCount(tiles, false);
}

/// The tiles of an area, and whether the area had more than allowed.
class TileCount {
  const TileCount(this.tiles, this.exceeded);

  final List<TileId> tiles;
  final bool exceeded;

  int get estimatedBytes => tiles.length * averageTileBytes;
}

/// "812 KB", "12.4 MB", "1.2 GB".
String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${math.max(1, (bytes / 1024).round())} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
