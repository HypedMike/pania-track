// Calls the real Rust core through the generated bridge, with the library built for this
// machine (`cargo build` in rust/). Skipped when it has not been built.
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/rust/analysis.dart' show TrackInput;
import 'package:pania/core/rust/analysis/geo.dart';
import 'package:pania/core/rust/api/analysis.dart';
import 'package:pania/core/rust/api/core.dart';
import 'package:pania/core/rust/api/identity.dart';
import 'package:pania/core/rust/api/sharing.dart';
import 'package:pania/core/rust/api/tracks.dart';
import 'package:pania/core/rust/api/updater.dart';
import 'package:pania/core/rust/frb_generated.dart';
import 'package:pania/core/rust/identity/keys.dart';
import 'package:pania/core/rust/tracks/gpx.dart' as gpx;
import 'package:pania/core/rust/tracks/simplify.dart';

const _library = 'rust/target/debug/librust_lib_pania.so';

/// A walk north at [speedMs], one fix every [everyS] seconds, [count] fixes.
List<Fix> walk(double speedMs, int everyS, int count, {double climbPerFix = 0.2}) => [
  for (var i = 0; i < count; i++)
    Fix(
      latitude: 46 + (i * everyS * speedMs) / 111195,
      longitude: 11,
      altitude: 1000 + i * climbPerFix,
      timeMs: 1700000000000 + i * everyS * 1000,
    ),
];

void main() {
  final available = File(_library).existsSync();

  setUpAll(() async {
    if (!available) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(_library));
    final dir = Directory.systemTemp.createTempSync('pania-core-test');
    // No keystore: secrets go to a plain file in `dir`, like a desktop development build.
    await initCore(
      configDir: dir.path,
      keystoreAvailable: false,
      secretGet: (_) async => null,
      secretSet: (_, _) async => '',
      secretDelete: (_) async {},
    );
  });

  group('analysis', () {
    test('analyses a walk', () async {
      final a = await analyzeTrail(fixes: walk(1.2, 5, 400), activity: Activity.foot);
      expect(a.motion.hasTime, true);
      expect(a.motion.distanceM, closeTo(1.2 * 5 * 399, 20));
      expect(a.motion.stops, isEmpty);
      expect(a.climbs, isNotNull);
      expect(a.quality.score, greaterThan(80));
    }, skip: !available);

    test('builds a pace model and predicts with it', () async {
      final model = await paceModel(
        tracks: [TrackInput(activity: Activity.foot, fixes: walk(1.3, 5, 600, climbPerFix: 0))],
        activity: Activity.foot,
      );
      expect(model.flatSpeedMs, closeTo(1.3, 0.1));
      final profile = await paceProfile(fixes: walk(1.0, 5, 200), model: model);
      expect(profile.totalM, closeTo(995, 10));
      // The walk to predict climbs, so it takes longer than flat ground would.
      expect(profile.seconds.last, greaterThan(profile.totalM / model.flatSpeedMs));
    }, skip: !available);
  });

  group('tracks', () {
    test('simplifies a straight line to its ends', () async {
      final points = [for (var i = 0; i < 50; i++) Point(latitude: 46 + i * 1e-4, longitude: 11)];
      final result = await simplifyTrack(points: points);
      expect(result.kept.length, 2);
      expect(result.report.originalPoints, BigInt.from(50));
    }, skip: !available);

    test('writes GPX without timestamps', () {
      final text = writeGpx(
        name: 'Ridge & views',
        description: '',
        points: [
          const Point(latitude: 46, longitude: 11, altitude: 1000),
          const Point(latitude: 46.001, longitude: 11),
        ],
        waypoints: [const gpx.Waypoint(latitude: 46, longitude: 11, name: 'Start')],
      );
      expect(text, contains('<gpx'));
      expect(text, contains('Ridge &amp; views'));
      expect(text, isNot(contains('<time>')));
    }, skip: !available);

    test('grades difficulty', () {
      expect(assessDifficulty(activity: Activity.foot, distanceM: 3000, gainM: 100).name, 'easy');
      expect(assessDifficulty(activity: Activity.foot, distanceM: 25000, gainM: 1800).name, 'hard');
    }, skip: !available);
  });

  group('identity', () {
    test('creates, signs and removes an identity', () async {
      final npub = await nostrCreateIdentity();
      expect(npub, startsWith('npub1'));
      expect(await nostrIdentityNpub(), npub);
      expect(await nostrExportSecret(), startsWith('nsec1'));
      final signed = await nostrSignEvent(
        event: const UnsignedEvent(kind: 1, content: 'hello', tags: []),
      );
      expect(signed, contains('"sig"'));
      await nostrRemoveIdentity();
      expect(await nostrIdentityNpub(), isNull);
    }, skip: !available);

    test('refuses a secret key that is not one', () async {
      await expectLater(
        nostrImportIdentity(secret: 'not a key'),
        throwsA(predicate((e) => '$e'.contains('invalid secret key'))),
      );
    }, skip: !available);
  });

  group('sharing and updater', () {
    test('keeps a relay list', () async {
      final defaults = await relaysReset();
      expect(defaults.length, greaterThanOrEqualTo(5));
      final added = await relaysAdd(url: 'wss://relay.example.com');
      expect(added, contains('wss://relay.example.com'));
      expect(await relaysRemove(url: 'wss://relay.example.com'), isNot(contains('wss://relay.example.com')));
      await expectLater(relaysAdd(url: 'ws://insecure.example.com'), throwsA(anything));
    }, skip: !available);

    test('only accepts release APKs of this project', () {
      expect(isReleaseApkUrl(url: 'https://github.com/HypedMike/pania-track/releases/download/v1.0.0/pania.apk'), true);
      expect(isReleaseApkUrl(url: 'https://evil.example/pania.apk'), false);
      expect(updateFileName(), endsWith('.apk'));
    }, skip: !available);
  });

  test('the Float64List type is what terrain data uses', () {
    expect(Float64List.fromList([1, 2]).length, 2);
  });
}
