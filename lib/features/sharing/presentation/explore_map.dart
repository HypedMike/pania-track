import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/osm_tile_layer.dart';
import '../../trail/presentation/trail_map.dart';
import '../data/sharing_api.dart';
import 'difficulty_badge.dart';

const LatLng _defaultCenter = LatLng(41.9028, 12.4964);

/// Map of shared trails: one marker per trail start, the selected trail's path drawn in full.
class ExploreMap extends StatefulWidget {
  const ExploreMap({
    super.key,
    required this.results,
    required this.selectedId,
    required this.me,
    required this.onSelect,
    required this.onCenter,
  });

  final List<SharedTrail> results;
  final String? selectedId;

  /// The user's own position, when known.
  final LatLng? me;
  final ValueChanged<String> onSelect;
  final void Function(double lat, double lon) onCenter;

  @override
  State<ExploreMap> createState() => _ExploreMapState();
}

class _ExploreMapState extends State<ExploreMap> {
  final MapController _controller = MapController();
  bool _ready = false;

  List<LatLng> get _fitPoints => [
    for (final r in widget.results)
      if (r.coordinates.isNotEmpty) LatLng(r.coordinates.first.latitude, r.coordinates.first.longitude),
    if (widget.me != null) widget.me!,
  ];

  void _fit() {
    final points = _fitPoints;
    if (!_ready || points.isEmpty) return;
    _controller.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(36), maxZoom: 14));
  }

  @override
  void didUpdateWidget(ExploreMap old) {
    super.didUpdateWidget(old);
    if (old.results != widget.results || old.me != widget.me) _fit();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MapPalette.of(context);
    SharedTrail? selected;
    for (final r in widget.results) {
      if (r.eventId == widget.selectedId) selected = r;
    }
    final markers = [
      for (final r in widget.results)
        if (r.coordinates.isNotEmpty)
          Marker(
            point: LatLng(r.coordinates.first.latitude, r.coordinates.first.longitude),
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => widget.onSelect(r.eventId),
              child: Center(
                child: Container(
                  width: r.eventId == widget.selectedId ? 24 : 18,
                  height: r.eventId == widget.selectedId ? 24 : 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: difficultyColor(context, r.difficulty),
                    border: Border.all(color: p.halo, width: 3),
                  ),
                ),
              ),
            ),
          ),
    ];
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: widget.me ?? _defaultCenter,
        initialZoom: widget.me != null ? 11 : 6,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () {
          _ready = true;
          _fit();
        },
        onMapEvent: (event) {
          if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
            final c = event.camera.center;
            widget.onCenter(c.latitude, c.longitude);
          }
        },
      ),
      children: [
        const OsmTileLayer(),
        if (selected != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final c in selected.coordinates) LatLng(c.latitude, c.longitude)],
                strokeWidth: 5,
                color: difficultyColor(context, selected.difficulty),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
        if (widget.me != null)
          CircleLayer(
            circles: [
              CircleMarker(point: widget.me!, radius: 7, color: p.route, borderColor: p.halo, borderStrokeWidth: 3),
            ],
          ),
        const OsmAttribution(),
      ],
    );
  }
}
