import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

/// OpenStreetMap raster tiles, darkened in the dark theme.
class OsmTileLayer extends StatelessWidget {
  const OsmTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.michelesaladino.pania',
      tileBuilder: dark ? darkModeTileBuilder : null,
    );
  }
}

/// The attribution OpenStreetMap asks for, bottom left.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) =>
      const SimpleAttributionWidget(source: Text('© OpenStreetMap'), alignment: Alignment.bottomLeft);
}
