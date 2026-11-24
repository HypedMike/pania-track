import 'dart:typed_data';

import '../../../core/rust/analysis/geo.dart';
import '../../../core/rust/analysis/pace.dart';
import '../../../core/rust/analysis/quality.dart';
import '../../../core/rust/analysis/patterns.dart' as rust_patterns;
import '../../../core/rust/analysis/routes.dart';
import '../../../core/rust/analysis/tour_review.dart';
import '../../../core/rust/api/analysis.dart' as rust;
import '../../../core/rust/analysis.dart';
import '../../trail/domain/gps_coordinate.dart';

export '../../../core/rust/analysis.dart' show TrailAnalysis, TrackInput;
export '../../../core/rust/analysis/climbs.dart';
export '../../../core/rust/analysis/geo.dart' show Fix, Activity;
export '../../../core/rust/analysis/motion.dart';
export '../../../core/rust/analysis/pace.dart' show PaceModel, CurveBin, Profile, Fatigue;
export '../../../core/rust/analysis/patterns.dart' show Patterns, Bucket, WeatherEffect;
export '../../../core/rust/analysis/quality.dart';
export '../../../core/rust/analysis/routes.dart' show Heatmap, RouteGroup, Member, HeatCell;
export '../../../core/rust/analysis/tour_review.dart' show Plan, Review, Split;

/// What the analysis needs of a trail.
class TrailForAnalysis {
  const TrailForAnalysis({required this.id, required this.activity, required this.coordinates, this.weather});

  final String id;
  final Activity activity;
  final List<GpsCoordinate> coordinates;
  final rust_patterns.Weather? weather;
}

List<Fix> toFixes(List<GpsCoordinate> coords) => [for (final c in coords) c.toFix()];

List<GpsCoordinate> fromFixes(List<Fix> fixes) => [
  for (final f in fixes)
    GpsCoordinate(
      latitude: f.latitude,
      longitude: f.longitude,
      altitude: f.altitude,
      timestamp: f.timeMs == null ? null : DateTime.fromMillisecondsSinceEpoch(f.timeMs!.toInt(), isUtc: true),
      accuracy: f.accuracy,
    ),
];

/// The calculations on recorded tracks. They run in the Rust core (`rust/src/analysis`); this
/// only hands data over.
abstract final class AnalysisApi {
  static Future<TrailAnalysis> analyzeTrail(List<GpsCoordinate> coords, Activity activity) =>
      rust.analyzeTrail(fixes: toFixes(coords), activity: activity);

  /// The person's own pace model from their recorded trails.
  static Future<PaceModel> paceModel(List<TrailForAnalysis> trails, Activity activity) => rust.paceModel(
    tracks: [for (final t in trails) TrackInput(activity: t.activity, fixes: toFixes(t.coordinates))],
    activity: activity,
  );

  /// Predicted cumulative time along a trail for a pace model.
  static Future<Profile> paceProfile(List<GpsCoordinate> coords, PaceModel model, {double? stepM}) =>
      rust.paceProfile(fixes: toFixes(coords), model: model, stepM: stepM);

  static Future<Cleaned> cleanTrack(List<GpsCoordinate> coords, Activity activity, {List<double>? terrain}) =>
      rust.cleanTrack(
        fixes: toFixes(coords),
        activity: activity,
        terrain: terrain == null ? null : Float64List.fromList(terrain),
      );

  static Future<List<RouteGroup>> groupRoutes(List<TrailForAnalysis> trails, {double? minOverlap}) => rust.groupRoutes(
    trails: [for (final t in trails) RouteTrail(id: t.id, activity: t.activity, fixes: toFixes(t.coordinates))],
    minOverlap: minOverlap,
  );

  static Future<Heatmap> heatmap(List<TrailForAnalysis> trails, {double? cellM}) => rust.routeHeatmap(
    trails: [for (final t in trails) RouteTrail(id: t.id, activity: t.activity, fixes: toFixes(t.coordinates))],
    cellM: cellM,
  );

  static Future<rust_patterns.Patterns> patterns(List<TrailForAnalysis> trails, int tzOffsetMin) => rust.timePatterns(
    trails: [
      for (final t in trails)
        rust_patterns.PatternTrail(activity: t.activity, fixes: toFixes(t.coordinates), weather: t.weather),
    ],
    tzOffsetMin: tzOffsetMin,
  );

  static Future<Review?> reviewTour(List<GpsCoordinate> trail, List<Fix> run, Plan plan) =>
      rust.reviewTour(trail: toFixes(trail), run: run, plan: plan);
}
