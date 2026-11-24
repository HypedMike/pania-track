import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

import '../tiles/tile_store.dart';

/// OpenStreetMap raster tiles, darkened in the dark theme. Tiles saved on the device are read from disk.
class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: tileUrlTemplate,
      tileProvider: OfflineTileProvider.shared,
      userAgentPackageName: 'com.michelesaladino.pania',
      tileBuilder: dark ? darkModeTileBuilder : null,
    );
  }
}

/// The attribution OpenStreetMap asks for, bottom left.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SimpleAttributionWidget(
      source: Text('© OpenStreetMap', style: TextStyle(color: scheme.onSurface)),
      backgroundColor: scheme.surface.withValues(alpha: 0.8),
      alignment: Alignment.bottomLeft,
    );
  }
}
