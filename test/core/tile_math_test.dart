import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pania/core/tiles/tile_math.dart';

void main() {
  test('tile numbers match the slippy map scheme', () {
    // Rome at zoom 10 is tile 547/380.
    expect(tileX(12.4964, 10), 547);
    expect(tileY(41.9028, 10), 380);
  });

  test('a small square gives a few tiles per zoom, more at higher zoom', () {
    const square = [LatLng(41.90, 12.49), LatLng(41.90, 12.51), LatLng(41.92, 12.51), LatLng(41.92, 12.49)];
    final low = tilesCovering(square, 10, 12);
    final high = tilesCovering(square, 10, 15);
    expect(low.exceeded, isFalse);
    expect(high.tiles.length, greaterThan(low.tiles.length));
    expect(low.tiles.where((t) => t.z == 10), isNotEmpty);
  });

  test('a huge area is reported as exceeded', () {
    const big = [LatLng(40, 10), LatLng(40, 14), LatLng(44, 14), LatLng(44, 10)];
    expect(tilesCovering(big, 10, 16).exceeded, isTrue);
  });

  test('formats sizes', () {
    expect(formatBytes(500 * 1024), '500 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
