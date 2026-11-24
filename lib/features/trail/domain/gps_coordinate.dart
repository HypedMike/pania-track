import '../../../core/rust/analysis/geo.dart';

/// A point of a trail.
class GpsCoordinate {
  const GpsCoordinate({required this.latitude, required this.longitude, this.altitude, this.timestamp, this.accuracy});

  final double latitude;
  final double longitude;

  /// Elevation in meters above sea level.
  final double? altitude;

  /// When the point was recorded.
  final DateTime? timestamp;

  /// Horizontal accuracy the GPS reported, in meters. Kept for recordings so their quality can be
  /// judged later.
  final double? accuracy;

  GpsCoordinate copyWith({double? accuracy, bool dropAccuracy = false}) => GpsCoordinate(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    timestamp: timestamp,
    accuracy: dropAccuracy ? null : (accuracy ?? this.accuracy),
  );

  /// The shape the Rust analysis takes.
  Fix toFix() => Fix(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    timeMs: timestamp?.millisecondsSinceEpoch,
    accuracy: accuracy,
  );

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (altitude != null) 'altitude': altitude,
    if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
    if (accuracy != null) 'accuracy': accuracy,
  };

  factory GpsCoordinate.fromJson(Map<String, Object?> json) => GpsCoordinate(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    altitude: (json['altitude'] as num?)?.toDouble(),
    timestamp: json['timestamp'] == null ? null : DateTime.tryParse(json['timestamp'] as String),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
  );
}

/// A named point of interest along a trail.
class Waypoint extends GpsCoordinate {
  const Waypoint({
    required super.latitude,
    required super.longitude,
    required this.name,
    super.altitude,
    super.timestamp,
    super.accuracy,
  });

  final String name;

  Waypoint withName(String name) =>
      Waypoint(latitude: latitude, longitude: longitude, name: name, altitude: altitude, timestamp: timestamp);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'name': name};

  factory Waypoint.fromJson(Map<String, Object?> json) {
    final c = GpsCoordinate.fromJson(json);
    return Waypoint(
      latitude: c.latitude,
      longitude: c.longitude,
      altitude: c.altitude,
      timestamp: c.timestamp,
      name: json['name'] as String? ?? '',
    );
  }

  factory Waypoint.at(GpsCoordinate c, String name) =>
      Waypoint(latitude: c.latitude, longitude: c.longitude, altitude: c.altitude, timestamp: c.timestamp, name: name);
}
