import 'package:http/http.dart' as http;

import '../../../core/routing/brouter.dart';
import '../../trail/domain/gps_coordinate.dart';
import 'route_analysis.dart';

/// Why a variant is offered. [balanced] is the recommended shortest-and-safest route.
enum VariantKind { balanced, gentlest, direct }

class RouteVariant {
  const RouteVariant({
    required this.id,
    required this.letter,
    required this.kind,
    required this.coordinates,
    required this.analysis,
  });

  final String id;

  /// Display letter: A, B, C.
  final String letter;
  final VariantKind kind;
  final List<GpsCoordinate> coordinates;
  final RouteAnalysis analysis;
}

class _Request {
  const _Request(this.profile, this.alternative, this.roads);
  final RoutingProfile profile;
  final int alternative;
  final bool roads;
}

/// Requests sent for every plan. BRouter's alternatives are other good paths for the same profile.
const List<_Request> _requests = [
  _Request(RoutingProfile.hikingMountain, 0, false),
  _Request(RoutingProfile.hikingMountain, 1, false),
  _Request(RoutingProfile.hikingMountain, 2, false),
  _Request(RoutingProfile.shortest, 0, true),
];

/// A gentler or more direct variant has to differ by at least this much to be worth showing.
const double _minSlopeGainPct = 2;
const double _minDistanceSaving = 0.03;

class _Candidate {
  _Candidate(this.coordinates, this.analysis);
  final List<GpsCoordinate> coordinates;
  final RouteAnalysis analysis;
}

bool _sameRoute(_Candidate a, _Candidate b) {
  final tolerance = a.analysis.distanceM * 0.01 > 30 ? a.analysis.distanceM * 0.01 : 30;
  return (a.analysis.distanceM - b.analysis.distanceM).abs() < tolerance &&
      (a.analysis.gainM - b.analysis.gainM).abs() < 10;
}

/// Routes through the checkpoints with several strategies and picks up to three variants:
/// the recommended one (shortest weighed by safety), the gentlest, and the most direct.
/// Throws only if no request succeeds.
Future<List<RouteVariant>> planRoutes(
  List<GpsCoordinate> checkpoints, {
  required bool loop,
  required bool avoidRoads,
  http.Client? client,
}) async {
  final points = loop && checkpoints.length > 1 ? [...checkpoints, checkpoints.first] : checkpoints;
  final requests = _requests.where((r) => !(avoidRoads && r.roads)).toList();
  final results = await Future.wait([
    for (final r in requests)
      fetchRoute(
        points,
        r.profile,
        r.alternative,
        client: client,
      ).then<(RoutedPath?, Object?)>((p) => (p, null), onError: (Object e) => (null, e)),
  ]);

  final candidates = <_Candidate>[];
  for (final (path, _) in results) {
    if (path == null || path.coordinates.length < 2) continue;
    final candidate = _Candidate(path.coordinates, analyzeRoute(path));
    if (!candidates.any((c) => _sameRoute(c, candidate))) candidates.add(candidate);
  }
  if (candidates.isEmpty) {
    final failure = results.where((r) => r.$2 != null).firstOrNull;
    throw failure?.$2 ?? Exception('No route');
  }

  final byCost = [...candidates]
    ..sort((a, b) => routeCost(a.analysis, avoidRoads).compareTo(routeCost(b.analysis, avoidRoads)));
  final best = byCost.first;
  final rest = byCost.skip(1).toList();
  final picked = <(VariantKind, _Candidate)>[(VariantKind.balanced, best)];

  final gentlestList = [...rest]..sort((a, b) => a.analysis.maxSlopePct.compareTo(b.analysis.maxSlopePct));
  final gentlest = gentlestList.firstOrNull;
  if (gentlest != null && gentlest.analysis.maxSlopePct <= best.analysis.maxSlopePct - _minSlopeGainPct) {
    picked.add((VariantKind.gentlest, gentlest));
  }
  final directList = [
    for (final c in rest)
      if (!picked.any((p) => identical(p.$2, c))) c,
  ]..sort((a, b) => a.analysis.distanceM.compareTo(b.analysis.distanceM));
  final direct = directList.firstOrNull;
  if (direct != null && direct.analysis.distanceM <= best.analysis.distanceM * (1 - _minDistanceSaving)) {
    picked.add((VariantKind.direct, direct));
  }

  return [
    for (var i = 0; i < picked.length; i++)
      RouteVariant(
        id: picked[i].$1.name,
        letter: String.fromCharCode(65 + i),
        kind: picked[i].$1,
        coordinates: picked[i].$2.coordinates,
        analysis: picked[i].$2.analysis,
      ),
  ];
}
