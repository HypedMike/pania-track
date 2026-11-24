import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../trail/application/trail_controller.dart';
import '../../trail/domain/trail.dart';
import '../data/analysis_api.dart';

/// The analysis of one trail, computed in Rust.
final trailAnalysisProvider = FutureProvider.autoDispose.family<TrailAnalysis, String>((ref, id) {
  final trail = ref.watch(trailProvider(id));
  if (trail == null) return Future.error(StateError('trail not found'));
  return AnalysisApi.analyzeTrail(trail.coordinates, trail.activity);
});

/// Groups of trails that follow the same route, for the groups that include [id].
final sameRouteProvider = FutureProvider.autoDispose.family<List<RouteGroup>, String>((ref, id) async {
  final trails = ref.watch(trailsProvider).value ?? const <Trail>[];
  final candidates = [
    for (final t in trails)
      if (t.coordinates.length > 1) TrailForAnalysis(id: t.id, activity: t.activity, coordinates: t.coordinates),
  ];
  if (!candidates.any((c) => c.id == id)) return const [];
  try {
    final all = await AnalysisApi.groupRoutes(candidates);
    return [
      for (final g in all)
        if (g.members.any((m) => m.id == id)) g,
    ];
  } catch (_) {
    return const [];
  }
});
