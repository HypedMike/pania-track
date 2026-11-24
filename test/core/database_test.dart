import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/database/database.dart';
import 'package:pania/core/rust/analysis/geo.dart' show Activity;
import 'package:pania/features/trail/data/trail_repository.dart';
import 'package:pania/features/trail/domain/gps_coordinate.dart';
import 'package:pania/features/trail/domain/trail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<String> _asset(String path) => File(path).readAsString();

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> open() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false, onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')),
    );
    await migrateDatabase(db, _asset);
    return db;
  }

  test('splits migrations into statements and drops comments', () {
    final statements = splitStatements(
      '-- a comment; with a semicolon\nCREATE TABLE a (x INT);\n\nALTER TABLE a ADD COLUMN y INT;',
    );
    expect(statements, ['CREATE TABLE a (x INT)', 'ALTER TABLE a ADD COLUMN y INT']);
  });

  test('every migration file applies and the schema ends up complete', () async {
    final db = await open();
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'])
        .toSet();
    expect(tables, containsAll(['trails', 'trail_coordinates', 'trail_waypoints', 'tour_runs', 'tour_run_fixes']));
    final columns = (await db.rawQuery('PRAGMA table_info(trails)')).map((r) => r['name']).toSet();
    expect(columns, containsAll(['source', 'activity', 'author_pubkey', 'shared_at', 'shared_event_id']));
    expect((await db.rawQuery('PRAGMA user_version')).first.values.first, migrationFiles.length);
  });

  test('applying the migrations twice changes nothing', () async {
    final db = await open();
    await migrateDatabase(db, _asset);
    expect((await db.rawQuery('PRAGMA user_version')).first.values.first, migrationFiles.length);
  });

  test('a database made by the earlier version of the app is kept as it is', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    // What the earlier app had after its five migrations: the tables, and sqlx's list.
    for (final file in migrationFiles) {
      for (final statement in splitStatements(await _asset(file))) {
        await db.execute(statement);
      }
    }
    await db.execute('CREATE TABLE _sqlx_migrations (version BIGINT PRIMARY KEY)');
    await db.execute('INSERT INTO _sqlx_migrations (version) VALUES (1),(2),(3),(4),(5)');
    await db.insert('trails', {'id': 'old', 'name': 'Old trail'});
    await migrateDatabase(db, _asset);
    expect((await db.query('trails')).single['name'], 'Old trail');
    expect((await db.rawQuery('PRAGMA user_version')).first.values.first, migrationFiles.length);
  });

  group('TrailRepository', () {
    Trail trail(String id) => Trail(
      id: id,
      name: 'Ridge',
      description: 'views',
      source: TrailSource.bookmarked,
      activity: Activity.bike,
      coordinates: [
        GpsCoordinate(
          latitude: 46,
          longitude: 11,
          altitude: 1000,
          timestamp: DateTime.utc(2026, 5, 1, 8),
          accuracy: 4.5,
        ),
        const GpsCoordinate(latitude: 46.001, longitude: 11.001),
      ],
      waypoints: const [Waypoint(latitude: 46, longitude: 11, name: 'Start')],
      author: const TrailAuthor(pubkey: 'ab', npub: 'npub1x', name: 'Giulia', dTag: 'd', eventId: 'e1'),
      sharedAt: DateTime.utc(2026, 5, 2),
      sharedEventId: 'ev',
    );

    test('saves and reads a trail back with everything it has', () async {
      final db = await open();
      final r = TrailRepository(() async => db);
      await r.save(trail('t1'));
      final back = (await r.getById('t1'))!;
      expect(back.name, 'Ridge');
      expect(back.source, TrailSource.bookmarked);
      expect(back.activity, Activity.bike);
      expect(back.coordinates, hasLength(2));
      expect(back.coordinates.first.altitude, 1000);
      expect(back.coordinates.first.accuracy, 4.5);
      expect(back.coordinates.first.timestamp, DateTime.utc(2026, 5, 1, 8));
      expect(back.coordinates.last.altitude, isNull);
      expect(back.waypoints.single.name, 'Start');
      expect(back.author?.name, 'Giulia');
      expect(back.author?.eventId, 'e1');
      expect(back.sharedAt, DateTime.utc(2026, 5, 2));
      expect(back.sharedEventId, 'ev');
    });

    test('saving again replaces the coordinates and waypoints', () async {
      final db = await open();
      final r = TrailRepository(() async => db);
      await r.save(trail('t1'));
      await r.save(
        trail('t1').copyWith(coordinates: [const GpsCoordinate(latitude: 1, longitude: 2)], waypoints: const []),
      );
      final back = (await r.getById('t1'))!;
      expect(back.coordinates, hasLength(1));
      expect(back.waypoints, isEmpty);
      expect(await r.getAll(), hasLength(1));
    });

    test('deleting a trail deletes its points', () async {
      final db = await open();
      final r = TrailRepository(() async => db);
      await r.save(trail('t1'));
      await r.remove('t1');
      expect(await r.getById('t1'), isNull);
      expect(await db.query('trail_coordinates'), isEmpty);
      expect(await db.query('trail_waypoints'), isEmpty);
    });
  });
}
