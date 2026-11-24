import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pania/features/splash/presentation/pania_terrain.dart';

void main() {
  final terrain = PaniaTerrain.fromBytes(File(PaniaTerrain.assetPath).readAsBytesSync().buffer.asByteData());

  test('covers a real elevation range', () {
    expect(terrain.n, 80);
    expect(terrain.minMeters, inInclusiveRange(100, 500));
    expect(terrain.maxMeters, inInclusiveRange(1750, 1900));
  });

  test('the summit is in the middle', () {
    expect(terrain.at(0, 0), greaterThan(0.97));
    expect(terrain.at(0.9, 0.9), lessThan(terrain.at(0, 0)));
  });

  test('sampling stays inside the grid', () {
    expect(terrain.at(-5, 5), inInclusiveRange(0.0, 1.0));
  });
}
