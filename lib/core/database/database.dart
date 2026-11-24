import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// The migrations, in order. Append new files to the end; never edit one that has shipped.
const List<String> migrationFiles = [
  'assets/migrations/001_create_trails.sql',
  'assets/migrations/002_trail_source_waypoints.sql',
  'assets/migrations/003_trail_activity.sql',
  'assets/migrations/004_trail_sharing.sql',
  'assets/migrations/005_analysis.sql',
];

/// Splits a migration file into statements (comments dropped).
List<String> splitStatements(String sql) {
  final withoutComments = sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
  return withoutComments.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// Applies the migrations a database has not seen. A database made by the earlier (Tauri)
/// version of the app has the same tables and a `_sqlx_migrations` list instead of a version
/// number; its migrations count as applied.
Future<void> migrateDatabase(Database db, Future<String> Function(String) load) async {
  final row = await db.rawQuery('PRAGMA user_version');
  var version = (row.first.values.first as int?) ?? 0;
  if (version == 0) {
    final legacy = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='_sqlx_migrations'");
    if (legacy.isNotEmpty) {
      final max = await db.rawQuery('SELECT MAX(version) AS v FROM _sqlx_migrations');
      version = (max.first['v'] as int?) ?? 0;
    }
  }
  if (version < migrationFiles.length) {
    await db.transaction((txn) async {
      for (var v = version + 1; v <= migrationFiles.length; v++) {
        for (final statement in splitStatements(await load(migrationFiles[v - 1]))) {
          await txn.execute(statement);
        }
      }
    });
  }
  await db.execute('PRAGMA user_version = ${migrationFiles.length}');
}

Future<String> loadAsset(String path) => rootBundle.loadString(path);

Future<Database>? _connection;

/// The shared SQLite connection, opened (and migrated) on first use. It lives in the app's
/// private files folder, where the earlier version of the app kept `pania.db`.
Future<Database> getDatabase() {
  return _connection ??= _open().onError<Object>((error, stack) {
    _connection = null; // allow a retry
    Error.throwWithStackTrace(error, stack);
  });
}

Future<Database> _open() async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = await openDatabase(
    p.join(dir.path, 'pania.db'),
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
  );
  await migrateDatabase(db, loadAsset);
  return db;
}
