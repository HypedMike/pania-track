import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/osm_tile_layer.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../../trail/presentation/trail_map.dart';
import '../application/plan_controller.dart';
import '../domain/route_planner.dart';

const LatLng _defaultCenter = LatLng(41.9028, 12.4964);
const double _defaultZoom = 6;

/// Zoom used when centring on a point, close enough to see paths.
const double localZoom = 14;

/// A request to move the map. Change [key] to repeat the same move.
class MapFocus {
  const MapFocus({required this.key, required this.center, this.zoom, this.bounds});

  final int key;
  final GpsCoordinate center;
  final double? zoom;

  /// Fitted instead of [zoom] when given.
  final LatLngBounds? bounds;
}

/// A checkpoint pin: a numbered ring.
class _Pin extends StatelessWidget {
  const _Pin(this.label, this.palette);

  final String label;
  final MapPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: palette.halo,
      shape: BoxShape.circle,
      border: Border.all(color: palette.ink, width: 3),
      boxShadow: const [BoxShadow(color: Color(0x40162018), blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
    ),
  );
}

/// The planner's map: checkpoints (draggable), route variants, the user's position and a searched place.
class PlanMap extends StatefulWidget {
  const PlanMap({
    super.key,
    required this.checkpoints,
    required this.variants,
    this.selectedId,
    this.onlySelected = false,
    this.cursor,
    this.position,
    this.place,
    this.focus,
    this.onViewChange,
    this.onAdd,
    this.onMove,
  });

  final List<Checkpoint> checkpoints;
  final List<RouteVariant> variants;

  /// Variant drawn on top and fully opaque. Others are drawn faded.
  final String? selectedId;

  /// Show only the selected variant (the checkpoint screen).
  final bool onlySelected;

  /// Point picked on the steepness profile.
  final GpsCoordinate? cursor;

  /// The user's position, drawn as a blue dot.
  final GpsCoordinate? position;

  /// A searched place, drawn as a ring so the user can tap it to add a checkpoint.
  final GpsCoordinate? place;
  final MapFocus? focus;
  final void Function(GpsCoordinate center)? onViewChange;

  /// Tapping the map adds a checkpoint; markers can be dragged. Omit for a read-only map.
  final void Function(GpsCoordinate point)? onAdd;
  final void Function(String id, GpsCoordinate point)? onMove;

  @override
  State<PlanMap> createState() => _PlanMapState();
}

class _PlanMapState extends State<PlanMap> {
  final MapController _controller = MapController();
  bool _ready = false;
  int _handledFocus = -1;

  /// Where a checkpoint is while it is being dragged.
  final Map<String, LatLng> _dragging = {};

  @override
  void didUpdateWidget(PlanMap old) {
    super.didUpdateWidget(old);
    _applyFocus();
  }

  void _applyFocus() {
    final focus = widget.focus;
    if (!_ready || focus == null || focus.key == _handledFocus) return;
    _handledFocus = focus.key;
    final bounds = focus.bounds;
    if (bounds != null) {
      _controller.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24), maxZoom: 16));
    } else {
      final zoom = focus.zoom ?? (_controller.camera.zoom < localZoom ? localZoom : _controller.camera.zoom);
      _controller.move(LatLng(focus.center.latitude, focus.center.longitude), zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _checkpointMarker(Checkpoint c, int i, MapPalette p) {
    final editable = widget.onMove != null;
    final pin = _Pin(checkpointLabel(i), p);
    if (!editable) return pin;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _dragging[c.id] = LatLng(c.latitude, c.longitude),
      onPanUpdate: (details) {
        final camera = MapCamera.of(context);
        final start = camera.latLngToScreenOffset(_dragging[c.id] ?? LatLng(c.latitude, c.longitude));
        setState(() => _dragging[c.id] = camera.screenOffsetToLatLng(start + details.delta));
      },
      onPanEnd: (_) {
        final end = _dragging.remove(c.id);
        if (end != null) widget.onMove!(c.id, GpsCoordinate(latitude: end.latitude, longitude: end.longitude));
        setState(() {});
      },
      child: pin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = MapPalette.of(context);
    final shown = widget.onlySelected
        ? widget.variants.where((v) => v.id == widget.selectedId).toList()
        : widget.variants;
    // Selected last so it is drawn on top.
    final ordered = [...shown]
      ..sort((a, b) => (a.id == widget.selectedId ? 1 : 0) - (b.id == widget.selectedId ? 1 : 0));
    final initial = [
      for (final c in widget.checkpoints) LatLng(c.latitude, c.longitude),
      for (final v in ordered)
        for (final c in v.coordinates) LatLng(c.latitude, c.longitude),
    ];

    Polyline line(RouteVariant v) {
      final selected = v.id == widget.selectedId;
      final (color, weight, pattern) = switch (v.kind) {
        VariantKind.balanced => (p.brand, 5.0, const StrokePattern.solid()),
        VariantKind.gentlest => (p.route, 4.0, StrokePattern.dashed(segments: const [10, 6])),
        VariantKind.direct => (p.alt, 4.0, StrokePattern.dashed(segments: const [2, 7])),
      };
      return Polyline(
        points: [for (final c in v.coordinates) LatLng(c.latitude, c.longitude)],
        strokeWidth: selected ? weight + 1 : weight,
        color: color.withValues(alpha: selected || widget.onlySelected ? 1 : 0.55),
        pattern: pattern,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      );
    }

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: _defaultZoom,
        initialCameraFit: initial.length > 1
            ? CameraFit.coordinates(coordinates: initial, padding: const EdgeInsets.all(32), maxZoom: 15)
            : null,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () {
          _ready = true;
          _applyFocus();
        },
        onTap: widget.onAdd == null
            ? null
            : (_, point) => widget.onAdd!(GpsCoordinate(latitude: point.latitude, longitude: point.longitude)),
        onPositionChanged: (camera, _) => widget.onViewChange?.call(
          GpsCoordinate(latitude: camera.center.latitude, longitude: camera.center.longitude),
        ),
      ),
      children: [
        const OsmTileLayer(),
        PolylineLayer(polylines: [for (final v in ordered) line(v)]),
        CircleLayer(
          circles: [
            if (widget.place != null)
              CircleMarker(
                point: LatLng(widget.place!.latitude, widget.place!.longitude),
                radius: 12,
                color: Colors.transparent,
                borderColor: p.ink,
                borderStrokeWidth: 3,
              ),
            if (widget.position != null) ...[
              CircleMarker(
                point: LatLng(widget.position!.latitude, widget.position!.longitude),
                radius: 18,
                color: p.route.withValues(alpha: 0.18),
              ),
              CircleMarker(
                point: LatLng(widget.position!.latitude, widget.position!.longitude),
                radius: 8,
                color: p.route,
                borderColor: p.halo,
                borderStrokeWidth: 3,
              ),
            ],
            if (widget.cursor != null)
              CircleMarker(
                point: LatLng(widget.cursor!.latitude, widget.cursor!.longitude),
                radius: 7,
                color: p.ink,
                borderColor: p.halo,
                borderStrokeWidth: 3,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < widget.checkpoints.length; i++)
              Marker(
                point:
                    _dragging[widget.checkpoints[i].id] ??
                    LatLng(widget.checkpoints[i].latitude, widget.checkpoints[i].longitude),
                width: 44,
                height: 44,
                child: Center(child: _checkpointMarker(widget.checkpoints[i], i, p)),
              ),
          ],
        ),
        const OsmAttribution(),
      ],
    );
  }
}
