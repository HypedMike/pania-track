import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/osm_tile_layer.dart';
import '../domain/gps_coordinate.dart';
import '../domain/trail.dart';

const LatLng _defaultCenter = LatLng(41.9028, 12.4964);
const double _defaultZoom = 6;
const double _liveZoom = 16;
const Color _amber = Color(0xFFF59E0B);

/// Colours written as plain values, per theme.
class MapPalette {
  const MapPalette({
    required this.ink,
    required this.route,
    required this.brand,
    required this.halo,
    required this.alt,
  });

  final Color ink;
  final Color route;
  final Color brand;
  final Color halo;
  final Color alt;

  static const light = MapPalette(
    ink: Color(0xFF16201B),
    route: Color(0xFF2F6FDB),
    brand: Color(0xFF127A4B),
    halo: Color(0xFFFFFFFF),
    alt: Color(0xFFB45309),
  );
  static const dark = MapPalette(
    ink: Color(0xFFE8EDE9),
    route: Color(0xFF6A9BF0),
    brand: Color(0xFF4CC38A),
    halo: Color(0xFF0F1512),
    alt: Color(0xFFF59E0B),
  );

  static MapPalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

LatLng toLatLng(GpsCoordinate c) => LatLng(c.latitude, c.longitude);

/// A trail on an OpenStreetMap map. Also shows a live position, a covered part and a guide line
/// (tours).
class TrailMap extends StatefulWidget {
  const TrailMap({
    super.key,
    required this.coordinates,
    this.waypoints = const [],
    this.source = TrailSource.recorded,
    this.fit = true,
    this.completed = const [],
    this.guideLine = const [],
    this.current,
    this.follow = false,
    this.followKey = 0,
    this.onUserMove,
    this.interactive = true,
  });

  final List<GpsCoordinate> coordinates;
  final List<Waypoint> waypoints;

  /// Imported trails are drawn blue, the others green.
  final TrailSource source;

  /// Fit the whole trail in view. Turn off for live maps, which follow [current] instead.
  final bool fit;

  /// The part of the trail already covered, drawn over it in a muted colour (tours).
  final List<GpsCoordinate> completed;

  /// A dashed line, e.g. from the live position back to the trail (tours).
  final List<GpsCoordinate> guideLine;

  /// Live position, drawn as a blue dot.
  final GpsCoordinate? current;
  final bool follow;

  /// Change to re-centre on the live position.
  final int followKey;
  final VoidCallback? onUserMove;
  final bool interactive;

  @override
  State<TrailMap> createState() => _TrailMapState();
}

class _TrailMapState extends State<TrailMap> {
  final MapController _controller = MapController();
  bool _ready = false;

  List<LatLng> get _positions => widget.coordinates.map(toLatLng).toList();

  void _fit() {
    final positions = _positions;
    if (!_ready || !widget.fit || positions.isEmpty) return;
    _controller.fitCamera(
      CameraFit.coordinates(coordinates: positions, padding: const EdgeInsets.all(24), maxZoom: 18),
    );
  }

  void _follow() {
    final current = widget.current;
    if (!_ready || !widget.follow || current == null) return;
    final zoom = _controller.camera.zoom;
    _controller.move(toLatLng(current), zoom < _liveZoom ? _liveZoom : zoom);
  }

  @override
  void didUpdateWidget(TrailMap old) {
    super.didUpdateWidget(old);
    if (widget.fit && (old.coordinates.length != widget.coordinates.length || old.fit != widget.fit)) _fit();
    if (widget.follow && (old.current != widget.current || old.followKey != widget.followKey || !old.follow)) {
      _follow();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MapPalette.of(context);
    final positions = _positions;
    final start = positions.isEmpty ? null : positions.first;
    final end = positions.length > 1 ? positions.last : null;
    final current = widget.current == null ? null : toLatLng(widget.current!);
    final line = widget.source == TrailSource.imported ? p.route : p.brand;
    final initial = current ?? start ?? _defaultCenter;

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: initial,
        initialZoom: current != null ? _liveZoom : (start != null ? 13 : _defaultZoom),
        interactionOptions: InteractionOptions(
          flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
        ),
        onMapReady: () {
          _ready = true;
          _fit();
          _follow();
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) widget.onUserMove?.call();
        },
      ),
      children: [
        const OsmTileLayer(),
        if (positions.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: positions,
                strokeWidth: 5,
                color: line,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        if (widget.completed.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.completed.map(toLatLng).toList(),
                strokeWidth: 5,
                color: p.ink.withValues(alpha: 0.4),
                strokeCap: StrokeCap.round,
              ),
            ],
          ),
        if (widget.guideLine.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.guideLine.map(toLatLng).toList(),
                strokeWidth: 4,
                color: p.alt,
                pattern: StrokePattern.dashed(segments: const [2, 9]),
                strokeCap: StrokeCap.round,
              ),
            ],
          ),
        CircleLayer(
          circles: [
            if (start != null)
              CircleMarker(point: start, radius: 7, color: p.halo, borderColor: p.ink, borderStrokeWidth: 3),
            if (end != null && current == null)
              CircleMarker(point: end, radius: 7, color: p.ink, borderColor: p.halo, borderStrokeWidth: 3),
            for (final w in widget.waypoints)
              CircleMarker(point: toLatLng(w), radius: 6, color: _amber, borderColor: p.halo, borderStrokeWidth: 2),
            if (current != null) ...[
              CircleMarker(point: current, radius: 20, color: p.route.withValues(alpha: 0.18)),
              CircleMarker(point: current, radius: 9, color: p.route, borderColor: p.halo, borderStrokeWidth: 3),
            ],
          ],
        ),
        const OsmAttribution(),
      ],
    );
  }
}
