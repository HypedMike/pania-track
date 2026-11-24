import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/providers.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/analysis/geo.dart';
import '../data/trail_repository.dart';
import '../domain/gps_coordinate.dart';
import '../domain/trail.dart';

final trailRepositoryProvider = Provider<TrailRepository>((ref) => TrailRepository(ref.watch(databaseProvider)));

/// Fields the user provides; the controller generates the rest.
class NewTrail {
  const NewTrail({
    required this.name,
    required this.source,
    required this.activity,
    required this.coordinates,
    this.description = '',
    this.waypoints = const [],
    this.author,
    this.sharedAt,
    this.sharedEventId,
  });

  final String name;
  final String description;
  final TrailSource source;
  final Activity activity;
  final List<GpsCoordinate> coordinates;
  final List<Waypoint> waypoints;
  final TrailAuthor? author;
  final DateTime? sharedAt;
  final String? sharedEventId;
}

/// All trails, newest first.
class TrailsController extends AsyncNotifier<List<Trail>> {
  TrailRepository get _repo => ref.read(trailRepositoryProvider);

  @override
  Future<List<Trail>> build() => _repo.getAll();

  List<Trail> get _current => state.value ?? const [];

  Future<void> reload() async {
    state = await AsyncValue.guard(_repo.getAll);
  }

  /// Validates, saves and adds a new trail. Throws on invalid input or failure.
  Future<Trail> createTrail(NewTrail input) async {
    final name = input.name.trim();
    if (name.isEmpty) throw Exception(I18n.t('error.nameRequired'));
    final now = DateTime.now();
    final trail = Trail(
      id: const Uuid().v4(),
      name: name,
      description: input.description.trim(),
      source: input.source,
      activity: input.activity,
      coordinates: input.coordinates,
      waypoints: input.waypoints,
      author: input.author,
      sharedAt: input.sharedAt,
      sharedEventId: input.sharedEventId,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(trail);
    state = AsyncData([trail, ..._current]);
    return trail;
  }

  /// Saves a changed copy of an existing trail.
  Future<Trail> updateTrail(Trail updated) async {
    final name = updated.name.trim();
    if (name.isEmpty) throw Exception(I18n.t('error.nameRequired'));
    final saved = updated.copyWith(name: name, description: updated.description.trim());
    await _repo.save(saved);
    state = AsyncData([for (final t in _current) t.id == saved.id ? saved : t]);
    return saved;
  }

  Future<void> deleteTrail(String id) async {
    await _repo.remove(id);
    state = AsyncData([
      for (final t in _current)
        if (t.id != id) t,
    ]);
  }
}

final trailsProvider = AsyncNotifierProvider<TrailsController, List<Trail>>(TrailsController.new);

/// One trail by id, from the loaded list.
final trailProvider = Provider.family<Trail?, String>((ref, id) {
  final trails = ref.watch(trailsProvider).value;
  if (trails == null) return null;
  for (final t in trails) {
    if (t.id == id) return t;
  }
  return null;
});
