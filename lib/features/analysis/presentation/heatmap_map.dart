import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/osm_tile_layer.dart';
import '../data/analysis_api.dart';

/// Drawing more than this many cells makes the map sluggish. The most visited are kept.
const int _maxDrawn = 4000;

/// Light to dark: once, a few times, often.
const List<Color> _ramp = [Color(0xFFF2CF5B), Color(0xFFE07B39), Color(0xFFC2410C), Color(0xFF9F2F1C)];

Color _color(int count, int max) {
  if (max <= 1) return _ramp[1];
  final t = (count - 1) / (max - 1);
  return _ramp[(t * _ramp.length).floor().clamp(0, _ramp.length - 1)];
}

/// Where the person has been, darker where they went more often; blank map is unexplored ground.
class HeatmapMap extends StatelessWidget {
  const HeatmapMap({super.key, required this.heatmap});

  final Heatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final b = heatmap.bounds;
    final cells = heatmap.cells.take(_maxDrawn);
    final bounds = b == null ? null : LatLngBounds(LatLng(b[0], b[1]), LatLng(b[2], b[3]));
    return FlutterMap(
      options: MapOptions(
        initialCenter: bounds?.center ?? const LatLng(41.9, 12.5),
        initialZoom: bounds != null ? 10 : 5,
        initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)),
      ),
      children: [
        const OsmTileLayer(),
        PolygonLayer(
          polygons: [
            for (final c in cells)
              Polygon(
                points: [
                  LatLng(c.latitude - heatmap.latStep / 2, c.longitude - heatmap.lonStep / 2),
                  LatLng(c.latitude - heatmap.latStep / 2, c.longitude + heatmap.lonStep / 2),
                  LatLng(c.latitude + heatmap.latStep / 2, c.longitude + heatmap.lonStep / 2),
                  LatLng(c.latitude + heatmap.latStep / 2, c.longitude - heatmap.lonStep / 2),
                ],
                color: _color(c.count, heatmap.maxCount).withValues(alpha: 0.6),
              ),
          ],
        ),
        const OsmAttribution(),
      ],
    );
  }
}
