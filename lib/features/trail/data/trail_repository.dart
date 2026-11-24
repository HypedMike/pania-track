import 'package:sqflite/sqflite.dart';

import '../../../core/rust/analysis/geo.dart';
import '../domain/gps_coordinate.dart';
import '../domain/trail.dart';

const _trailColumns =
    'id, name, description, source, activity, created_at, updated_at, author_pubkey, author_npub, '
    'author_name, author_d_tag, author_event_id, shared_at, shared_event_id';

/// Reads and writes trails in SQLite.
class TrailRepository {
  TrailRepository(this._open);

  final Future<Database> Function() _open;

  GpsCoordinate _coordinate(Map<String, Object?> row) => GpsCoordinate(
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    altitude: (row['altitude'] as num?)?.toDouble(),
    timestamp: row['timestamp'] == null ? null : DateTime.tryParse(row['timestamp'] as String),
    accuracy: (row['accuracy'] as num?)?.toDouble(),
  );

  TrailAuthor? _author(Map<String, Object?> row) {
    final pubkey = row['author_pubkey'] as String?;
    final npub = row['author_npub'] as String?;
    final dTag = row['author_d_tag'] as String?;
    if (pubkey == null || pubkey.isEmpty || npub == null || npub.isEmpty || dTag == null || dTag.isEmpty) {
      return null;
    }
    final name = row['author_name'] as String?;
    return TrailAuthor(
      pubkey: pubkey,
      npub: npub,
      name: (name == null || name.isEmpty) ? null : name,
      dTag: dTag,
      eventId: row['author_event_id'] as String? ?? '',
    );
  }

  Future<Trail> _hydrate(Database db, Map<String, Object?> row) async {
    final id = row['id'] as String;
    final coordinates = await db.rawQuery(
      'SELECT latitude, longitude, altitude, timestamp, accuracy FROM trail_coordinates WHERE trail_id = ? ORDER BY position',
      [id],
    );
    final waypoints = await db.rawQuery(
      'SELECT latitude, longitude, altitude, name, timestamp FROM trail_waypoints WHERE trail_id = ? ORDER BY position',
      [id],
    );
    final sharedAt = row['shared_at'] as String?;
    final sharedEvent = row['shared_event_id'] as String?;
    return Trail(
      id: id,
      name: row['name'] as String,
      description: row['description'] as String? ?? '',
      source: TrailSource.values.firstWhere((s) => s.name == row['source'], orElse: () => TrailSource.recorded),
      activity: row['activity'] == 'bike' ? Activity.bike : Activity.foot,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      coordinates: coordinates.map(_coordinate).toList(),
      waypoints: waypoints.map((r) => Waypoint.at(_coordinate(r), r['name'] as String? ?? '')).toList(),
      author: _author(row),
      sharedAt: sharedAt == null || sharedAt.isEmpty ? null : DateTime.tryParse(sharedAt),
      sharedEventId: sharedEvent == null || sharedEvent.isEmpty ? null : sharedEvent,
    );
  }

  Future<List<Trail>> getAll() async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_trailColumns FROM trails ORDER BY created_at DESC');
    return [for (final row in rows) await _hydrate(db, row)];
  }

  Future<Trail?> getById(String id) async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_trailColumns FROM trails WHERE id = ?', [id]);
    return rows.isEmpty ? null : _hydrate(db, rows.first);
  }

  /// Inserts the trail, or updates it (replacing its coordinates and waypoints) if the id already
  /// exists. All in one transaction.
  Future<void> save(Trail trail) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.rawInsert(
        '''INSERT INTO trails (id, name, description, source, activity,
             author_pubkey, author_npub, author_name, author_d_tag, author_event_id, shared_at, shared_event_id)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET
             name = excluded.name,
             description = excluded.description,
             source = excluded.source,
             activity = excluded.activity,
             author_pubkey = excluded.author_pubkey,
             author_npub = excluded.author_npub,
             author_name = excluded.author_name,
             author_d_tag = excluded.author_d_tag,
             author_event_id = excluded.author_event_id,
             shared_at = excluded.shared_at,
             shared_event_id = excluded.shared_event_id,
             updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')''',
        [
          trail.id,
          trail.name,
          trail.description,
          trail.source.name,
          trail.activity.name,
          trail.author?.pubkey,
          trail.author?.npub,
          trail.author?.name,
          trail.author?.dTag,
          trail.author?.eventId,
          trail.sharedAt?.toUtc().toIso8601String(),
          trail.sharedEventId,
        ],
      );
      await txn.delete('trail_coordinates', where: 'trail_id = ?', whereArgs: [trail.id]);
      final batch = txn.batch();
      for (var i = 0; i < trail.coordinates.length; i++) {
        final c = trail.coordinates[i];
        batch.insert('trail_coordinates', {
          'trail_id': trail.id,
          'position': i,
          'latitude': c.latitude,
          'longitude': c.longitude,
          'altitude': c.altitude,
          'timestamp': c.timestamp?.toUtc().toIso8601String(),
          'accuracy': c.accuracy,
        });
      }
      batch.delete('trail_waypoints', where: 'trail_id = ?', whereArgs: [trail.id]);
      for (var i = 0; i < trail.waypoints.length; i++) {
        final w = trail.waypoints[i];
        batch.insert('trail_waypoints', {
          'trail_id': trail.id,
          'position': i,
          'latitude': w.latitude,
          'longitude': w.longitude,
          'altitude': w.altitude,
          'name': w.name,
          'timestamp': w.timestamp?.toUtc().toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> remove(String id) async {
    final db = await _open();
    await db.delete('trails', where: 'id = ?', whereArgs: [id]);
  }
}
