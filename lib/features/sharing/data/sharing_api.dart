import '../../../core/rust/analysis/geo.dart';
import '../../../core/rust/api/sharing.dart' as rust;
import '../../../core/rust/sharing/trail_event.dart';
import '../../../core/rust/tracks/gpx.dart' as rust_gpx;
import '../../../core/rust/tracks/simplify.dart' as rust_track;
import '../../trail/domain/gps_coordinate.dart';
import '../../trail/domain/trail.dart';

export '../../../core/rust/api/sharing.dart' show ShareResult;
export '../../../core/rust/sharing/trail_event.dart' show ExploreQuery, SharedTrail, Fidelity;
export '../../../core/rust/tracks/difficulty.dart' show Difficulty;

/// A shared trail's points as the app's own coordinate type.
List<GpsCoordinate> sharedCoordinates(SharedTrail t) => [
  for (final p in t.coordinates) GpsCoordinate(latitude: p.latitude, longitude: p.longitude, altitude: p.altitude),
];

List<Waypoint> sharedWaypoints(SharedTrail t) => [
  for (final w in t.waypoints)
    Waypoint(latitude: w.latitude, longitude: w.longitude, altitude: w.altitude, name: w.name),
];

/// Sharing and exploring trails over Nostr. Everything happens in the Rust core
/// (`rust/src/sharing`): building and signing events, talking to relays, validating what comes back.
abstract final class SharingApi {
  static Future<List<String>> relaysList() => rust.relaysList();
  static Future<List<String>> relaysAdd(String url) => rust.relaysAdd(url: url);
  static Future<List<String>> relaysRemove(String url) => rust.relaysRemove(url: url);
  static Future<List<String>> relaysReset() => rust.relaysReset();

  /// Publishes a trail, signed with the user's key. Timestamps never leave the device.
  static Future<rust.ShareResult> shareTrail(Trail trail, {String? authorName}) => rust.shareTrail(
    trail: ShareInput(
      id: trail.id,
      name: trail.name,
      description: trail.description,
      activity: trail.activity,
      coordinates: [
        for (final c in trail.coordinates)
          rust_track.Point(latitude: c.latitude, longitude: c.longitude, altitude: c.altitude),
      ],
      waypoints: [
        for (final w in trail.waypoints)
          rust_gpx.Waypoint(latitude: w.latitude, longitude: w.longitude, altitude: w.altitude, name: w.name),
      ],
      authorName: authorName,
    ),
  );

  /// Asks relays to delete a shared trail. Returns the relays that took the request.
  static Future<List<String>> unshareTrail(String trailId) => rust.unshareTrail(trailId: trailId);

  static Future<List<SharedTrail>> explore(ExploreQuery query) => rust.exploreTrails(query: query);
}

Activity? activityOrNull(String id) => id == 'foot' ? Activity.foot : (id == 'bike' ? Activity.bike : null);
