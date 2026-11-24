import '../../../core/rust/analysis/geo.dart';
import 'gps_coordinate.dart';

/// Planned trails are drawn from checkpoints in the planner; they haven't been walked yet.
/// Bookmarked trails were saved from another person's shared trail (see [Trail.author]).
enum TrailSource { recorded, imported, planned, bookmarked }

/// Who made a bookmarked trail. Kept with the saved copy, even if the original disappears.
class TrailAuthor {
  const TrailAuthor({required this.pubkey, required this.npub, required this.dTag, required this.eventId, this.name});

  /// Public key, hex.
  final String pubkey;
  final String npub;
  final String? name;

  /// The trail's id on Nostr; with [pubkey] it identifies the original.
  final String dTag;

  /// The Nostr event this copy was saved from.
  final String eventId;
}

class Trail {
  const Trail({
    required this.id,
    required this.name,
    required this.source,
    required this.activity,
    required this.coordinates,
    required this.waypoints,
    this.description = '',
    this.createdAt,
    this.updatedAt,
    this.author,
    this.sharedAt,
    this.sharedEventId,
  });

  final String id;
  final String name;
  final String description;
  final TrailSource source;
  final Activity activity;

  /// Ordered points that make up the trail path.
  final List<GpsCoordinate> coordinates;
  final List<Waypoint> waypoints;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Set on trails saved from someone else (source is [TrailSource.bookmarked]).
  final TrailAuthor? author;

  /// When this trail was last published to Nostr, and the event that carries it.
  final DateTime? sharedAt;
  final String? sharedEventId;

  Trail copyWith({
    String? name,
    String? description,
    TrailSource? source,
    Activity? activity,
    List<GpsCoordinate>? coordinates,
    List<Waypoint>? waypoints,
    TrailAuthor? author,
    DateTime? sharedAt,
    String? sharedEventId,
    bool clearShared = false,
  }) => Trail(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    source: source ?? this.source,
    activity: activity ?? this.activity,
    coordinates: coordinates ?? this.coordinates,
    waypoints: waypoints ?? this.waypoints,
    createdAt: createdAt,
    updatedAt: updatedAt,
    author: author ?? this.author,
    sharedAt: clearShared ? null : (sharedAt ?? this.sharedAt),
    sharedEventId: clearShared ? null : (sharedEventId ?? this.sharedEventId),
  );
}
