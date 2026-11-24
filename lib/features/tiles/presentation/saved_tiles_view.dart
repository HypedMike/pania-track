import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/gps_service.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/tiles/tile_math.dart';
import '../../../core/tiles/tile_store.dart';
import '../../../core/ui/osm_tile_layer.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/presentation/trail_map.dart';

/// The areas saved on the device.
final savedTilesProvider = FutureProvider.autoDispose<List<SavedRegion>>((ref) => TileStore.regions());

/// Draw an area on a map, see how much space its tiles take, save it, and manage the saved areas.
class SavedTilesView extends ConsumerStatefulWidget {
  const SavedTilesView({super.key});

  @override
  ConsumerState<SavedTilesView> createState() => _SavedTilesViewState();
}

class _SavedTilesViewState extends ConsumerState<SavedTilesView> {
  static const double _mapHeight = 340;

  final MapController _map = MapController();
  final TextEditingController _name = TextEditingController();

  List<LatLng> _polygon = const [];
  List<Offset> _stroke = const [];
  bool _drawing = false;
  int _maxZoom = 15;
  TileCount? _count;

  bool _saving = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _map.dispose();
    super.dispose();
  }

  void _recount() {
    _count = _polygon.length < 3 ? null : tilesCovering(_polygon, minSavedZoom, _maxZoom);
  }

  void _startDraw() => setState(() {
    _drawing = true;
    _stroke = const [];
    _polygon = const [];
    _count = null;
    _error = null;
  });

  void _clear() => setState(() {
    _drawing = false;
    _stroke = const [];
    _polygon = const [];
    _count = null;
    _error = null;
  });

  void _drawUpdate(Offset point) {
    if (_stroke.isNotEmpty && (point - _stroke.last).distance < 6) return;
    setState(() => _stroke = [..._stroke, point]);
  }

  void _drawEnd(TFunction t) {
    var points = _stroke;
    if (points.length > 80) {
      final step = points.length / 80;
      points = [for (var i = 0; i < 80; i++) points[(i * step).floor()]];
    }
    setState(() {
      _drawing = false;
      _stroke = const [];
      if (points.length < 3) return;
      _polygon = [for (final point in points) _map.camera.screenOffsetToLatLng(point)];
      _recount();
      if (_name.text.trim().isEmpty) {
        final n = (ref.read(savedTilesProvider).value?.length ?? 0) + 1;
        _name.text = t('tiles.defaultName', {'n': n});
      }
    });
  }

  Future<void> _goToMe() async {
    try {
      await GpsService.ensurePermission();
      final me = await GpsService.currentPosition();
      _map.move(LatLng(me.latitude, me.longitude), 13);
    } catch (e) {
      if (mounted) showToast(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save(TFunction t) async {
    final name = _name.text.trim().isEmpty ? t('tiles.defaultName', {'n': 1}) : _name.text.trim();
    setState(() {
      _saving = true;
      _cancel = false;
      _done = 0;
      _total = _count?.tiles.length ?? 0;
      _error = null;
    });
    try {
      final saved = await TileStore.save(
        name: name,
        polygon: _polygon,
        maxZoom: _maxZoom,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
            });
          }
        },
        isCancelled: () => _cancel,
      );
      ref.invalidate(savedTilesProvider);
      if (!mounted) return;
      if (saved != null) {
        showToast(context, t('tiles.saved'));
        _name.clear();
        _clear();
      }
    } on TileDownloadException {
      if (mounted) setState(() => _error = t('tiles.failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(SavedRegion region, TFunction t) async {
    final ok = await confirmDialog(
      context,
      message: t('tiles.deleteConfirm', {'name': region.name}),
      confirmLabel: t('tiles.delete'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok) return;
    await TileStore.delete(region.id);
    ref.invalidate(savedTilesProvider);
  }

  void _show(SavedRegion region) {
    _map.fitCamera(
      CameraFit.bounds(bounds: LatLngBounds.fromPoints(region.polygon), padding: const EdgeInsets.all(32), maxZoom: 16),
    );
  }

  Widget _mapView(TFunction t, List<SavedRegion> saved) {
    final p = MapPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: _mapHeight,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: const MapOptions(
                initialCenter: LatLng(41.9028, 12.4964),
                initialZoom: 6,
                minZoom: 3,
                maxZoom: 18,
                interactionOptions: InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                const OsmTileLayer(),
                PolygonLayer(
                  polygons: [
                    for (final r in saved)
                      Polygon(
                        points: r.polygon,
                        color: p.brand.withValues(alpha: 0.12),
                        borderColor: p.brand.withValues(alpha: 0.6),
                        borderStrokeWidth: 1.5,
                      ),
                    if (_polygon.length >= 3)
                      Polygon(
                        points: _polygon,
                        color: p.route.withValues(alpha: 0.2),
                        borderColor: p.route,
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
                const OsmAttribution(),
              ],
            ),
            if (_drawing)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(() => _stroke = [d.localPosition]),
                  onPanUpdate: (d) => _drawUpdate(d.localPosition),
                  onPanEnd: (_) => _drawEnd(t),
                  child: CustomPaint(
                    painter: _StrokePainter(_stroke, p.route),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: MapChip(label: t('tiles.drawHint')),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview(TFunction t) {
    final c = context.colors;
    final count = _count;
    if (count == null) {
      return Text(t('tiles.previewEmpty'), style: TextStyle(fontSize: 14, color: c.muted));
    }
    if (count.exceeded) {
      return Text(t('tiles.tooMany', {'max': maxTilesPerArea}), style: TextStyle(fontSize: 14, color: c.danger));
    }
    return Row(
      children: [
        Icon(Icons.download_for_offline_outlined, color: c.brandFg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            t('tiles.preview', {'n': count.tiles.length, 'size': formatBytes(count.estimatedBytes)}),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final saved = ref.watch(savedTilesProvider).value ?? const <SavedRegion>[];
    final count = _count;
    final canSave = count != null && !count.exceeded && count.tiles.isNotEmpty && !_saving;
    final date = DateFormat.yMMMd(I18n.locale);

    return PageScaffold(
      title: t('tiles.title'),
      onBack: context.goBack,
      backLabel: t('common.back'),
      body: PageColumn(
        gap: 16,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(t('tiles.intro'), style: TextStyle(fontSize: 14, color: c.muted)),
          _mapView(t, saved),
          Row(
            children: [
              Expanded(
                child: SmallButton(
                  label: _polygon.isEmpty ? t('tiles.draw') : t('tiles.redraw'),
                  primary: true,
                  onPressed: _saving ? null : _startDraw,
                ),
              ),
              const SizedBox(width: 8),
              SmallButton(
                label: t('tiles.clear'),
                onPressed: _saving || (_polygon.isEmpty && !_drawing) ? null : _clear,
              ),
              const SizedBox(width: 8),
              SmallButton(label: t('tiles.location'), onPressed: _goToMe),
            ],
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedChoice<int>(
                  label: t('tiles.detail'),
                  options: [for (final z in savedZoomLevels) (z, '$z')],
                  value: _maxZoom,
                  onChanged: (z) => setState(() {
                    _maxZoom = z;
                    _recount();
                  }),
                ),
                const SizedBox(height: 4),
                Text(t('tiles.detailHint'), style: TextStyle(fontSize: 12, color: c.muted)),
                const SizedBox(height: 16),
                _preview(t),
                if (_polygon.length >= 3) ...[
                  const SizedBox(height: 16),
                  LabeledField(label: t('tiles.name'), controller: _name),
                ],
                const SizedBox(height: 16),
                if (_saving) ...[
                  LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                  const SizedBox(height: 8),
                  Text(
                    t('tiles.saving', {'done': _done, 'total': _total}),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(label: t('common.cancel'), onPressed: () => setState(() => _cancel = true)),
                ] else
                  PrimaryButton(
                    label: t('tiles.save'),
                    icon: Icons.download,
                    onPressed: canSave ? () => _save(t) : null,
                  ),
                if (_error != null) ...[const SizedBox(height: 8), ErrorText(_error!)],
                const SizedBox(height: 12),
                Text(t('tiles.policy'), style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('tiles.list'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (saved.isEmpty) ...[
                  const SizedBox(height: 4),
                  Text(t('tiles.listEmpty'), style: TextStyle(fontSize: 14, color: c.muted)),
                ] else ...[
                  Text(
                    t('tiles.total', {'size': formatBytes(saved.fold(0, (sum, r) => sum + r.bytes))}),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                  for (final r in saved)
                    InkWell(
                      onTap: () => _show(r),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  Text(
                                    t('tiles.item', {
                                      'n': r.tiles,
                                      'size': formatBytes(r.bytes),
                                      'date': date.format(r.savedAt),
                                    }),
                                    style: TextStyle(fontSize: 13, color: c.muted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: t('tiles.delete'),
                              icon: Icon(Icons.delete_outline, color: c.danger),
                              onPressed: _saving ? null : () => _delete(r, t),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The line being drawn, closed back to its start.
class _StrokePainter extends CustomPainter {
  _StrokePainter(this.points, this.color);

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      points.last,
      points.first,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.points != points || old.color != color;
}
