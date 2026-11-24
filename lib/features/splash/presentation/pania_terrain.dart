import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Elevation grid of Pania della Croce (Apuan Alps, Tuscany), baked by `tool/bake_pania_terrain.py`
/// from open AWS Terrain Tiles. The summit sits in the middle of the square.
class PaniaTerrain {
  PaniaTerrain._(this.n, this.spacingMeters, this.minMeters, this.maxMeters, this._normalized);

  /// Cells per side.
  final int n;

  /// Distance between two cells, in metres.
  final int spacingMeters;
  final double minMeters;
  final double maxMeters;

  /// Heights scaled to 0 (lowest cell) .. 1 (highest cell), row-major, north row first.
  final Float32List _normalized;

  static const assetPath = 'assets/pania_terrain.bin';

  static Future<PaniaTerrain> load() async => PaniaTerrain.fromBytes(await rootBundle.load(assetPath));

  factory PaniaTerrain.fromBytes(ByteData data) {
    final n = data.getUint16(0, Endian.little);
    final spacing = data.getUint16(2, Endian.little);
    final metres = Float32List(n * n);
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < n * n; i++) {
      final m = data.getUint16(4 + i * 2, Endian.little) / 10;
      metres[i] = m;
      lo = math.min(lo, m);
      hi = math.max(hi, m);
    }
    final normalized = Float32List(n * n);
    for (var i = 0; i < metres.length; i++) {
      normalized[i] = (metres[i] - lo) / (hi - lo);
    }
    return PaniaTerrain._(n, spacing, lo, hi, normalized);
  }

  /// Normalised height (0..1) of the cell at [row], [col].
  double cell(int row, int col) => _normalized[row * n + col];

  /// Bilinear normalised height at [x], [z] in -1..1 (z = -1 is north).
  double at(double x, double z) {
    final fc = ((x + 1) / 2 * (n - 1)).clamp(0.0, n - 1.0);
    final fr = ((z + 1) / 2 * (n - 1)).clamp(0.0, n - 1.0);
    final c0 = fc.floor(), r0 = fr.floor();
    final c1 = math.min(c0 + 1, n - 1), r1 = math.min(r0 + 1, n - 1);
    final tc = fc - c0, tr = fr - r0;
    final top = cell(r0, c0) * (1 - tc) + cell(r0, c1) * tc;
    final bottom = cell(r1, c0) * (1 - tc) + cell(r1, c1) * tc;
    return top * (1 - tr) + bottom * tr;
  }
}
