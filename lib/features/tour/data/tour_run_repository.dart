import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../../core/rust/analysis/geo.dart' show Fix;
import '../../../core/rust/analysis/pace.dart' show Profile;

/// A tour that was followed: the plan made at the start, and (separately) the GPS fixes recorded.
class TourRun {
  const TourRun({
    required this.id,
    required this.trailId,
    required this.startedAt,
    required this.plannedSpeedMs,
    this.endedAt,
    this.planProfile,
    this.targetArrivalMs,
    this.finished = false,
  });

  final String id;
  final String trailId;

  /// Milliseconds since the epoch.
  final int startedAt;
  final int? endedAt;

  /// Constant speed the plan assumed, m/s.
  final double plannedSpeedMs;

  /// The slope-aware plan, when the person had enough recordings to build one.
  final Profile? planProfile;
  final int? targetArrivalMs;

  /// The person got to the end of the trail.
  final bool finished;
}

const _runColumns = 'id, trail_id, started_at, ended_at, planned_speed_ms, plan_profile, target_arrival, finished';

String _iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
int? _ms(Object? iso) => iso == null ? null : DateTime.tryParse(iso as String)?.millisecondsSinceEpoch;

Profile? _parseProfile(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final j = jsonDecode(json) as Map<String, Object?>;
    return Profile(
      stepM: (j['stepM'] as num).toDouble(),
      totalM: (j['totalM'] as num).toDouble(),
      seconds: Float64List.fromList([for (final s in (j['seconds'] as List)) (s as num).toDouble()]),
    );
  } catch (_) {
    return null;
  }
}

String _profileJson(Profile p) => jsonEncode({'stepM': p.stepM, 'totalM': p.totalM, 'seconds': p.seconds.toList()});

TourRun _toRun(Map<String, Object?> row) => TourRun(
  id: row['id'] as String,
  trailId: row['trail_id'] as String,
  startedAt: _ms(row['started_at'])!,
  endedAt: _ms(row['ended_at']),
  plannedSpeedMs: (row['planned_speed_ms'] as num).toDouble(),
  planProfile: _parseProfile(row['plan_profile'] as String?),
  targetArrivalMs: _ms(row['target_arrival']),
  finished: row['finished'] == 1,
);

class TourRunRepository {
  TourRunRepository(this._open);

  final Future<Database> Function() _open;

  Future<void> create(TourRun run) async {
    final db = await _open();
    await db.insert('tour_runs', {
      'id': run.id,
      'trail_id': run.trailId,
      'started_at': _iso(run.startedAt),
      'planned_speed_ms': run.plannedSpeedMs,
      'plan_profile': run.planProfile == null ? null : _profileJson(run.planProfile!),
      'target_arrival': run.targetArrivalMs == null ? null : _iso(run.targetArrivalMs!),
    });
  }

  Future<TourRun?> get(String id) async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_runColumns FROM tour_runs WHERE id = ?', [id]);
    return rows.isEmpty ? null : _toRun(rows.first);
  }

  Future<List<TourRun>> listForTrail(String trailId) async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_runColumns FROM tour_runs WHERE trail_id = ? ORDER BY started_at DESC', [
      trailId,
    ]);
    return rows.map(_toRun).toList();
  }

  /// Every ended tour, newest first.
  Future<List<TourRun>> listAll() async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT $_runColumns FROM tour_runs ORDER BY started_at DESC');
    return rows.map(_toRun).toList();
  }

  /// Adds fixes after the ones already stored.
  Future<void> appendFixes(String runId, List<Fix> fixes) async {
    if (fixes.isEmpty) return;
    final db = await _open();
    await db.transaction((txn) async {
      final counted = await txn.rawQuery('SELECT COUNT(*) AS n FROM tour_run_fixes WHERE run_id = ?', [runId]);
      final first = (counted.first['n'] as int?) ?? 0;
      final batch = txn.batch();
      for (var i = 0; i < fixes.length; i++) {
        final f = fixes[i];
        batch.insert('tour_run_fixes', {
          'run_id': runId,
          'position': first + i,
          'latitude': f.latitude,
          'longitude': f.longitude,
          'altitude': f.altitude,
          'time_ms': f.timeMs?.toInt() ?? 0,
          'accuracy': f.accuracy,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Fix>> getFixes(String runId) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT latitude, longitude, altitude, time_ms, accuracy FROM tour_run_fixes WHERE run_id = ? ORDER BY position',
      [runId],
    );
    return [
      for (final r in rows)
        Fix(
          latitude: (r['latitude'] as num).toDouble(),
          longitude: (r['longitude'] as num).toDouble(),
          altitude: (r['altitude'] as num?)?.toDouble(),
          timeMs: (r['time_ms'] as num).toInt(),
          accuracy: (r['accuracy'] as num?)?.toDouble(),
        ),
    ];
  }

  Future<int> countFixes(String runId) async {
    final db = await _open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM tour_run_fixes WHERE run_id = ?', [runId]);
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<void> end(String runId, {required bool finished}) async {
    final db = await _open();
    await db.rawUpdate('UPDATE tour_runs SET ended_at = ?, finished = ? WHERE id = ?', [
      _iso(DateTime.now().millisecondsSinceEpoch),
      finished ? 1 : 0,
      runId,
    ]);
  }

  Future<void> remove(String id) async {
    final db = await _open();
    await db.delete('tour_runs', where: 'id = ?', whereArgs: [id]);
  }
}
