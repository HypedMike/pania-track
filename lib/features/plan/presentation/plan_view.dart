import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/geocoding/photon.dart';
import '../../../core/gps/gps_service.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../application/plan_controller.dart';
import 'place_search.dart';
import 'plan_map.dart';
import 'route_badges.dart';
import 'steepness_profile.dart';

/// A tap this close to a searched place adds a checkpoint named after it.
const double _placeSnapM = 80;

/// How long a locate/search notice replaces the hint.
const Duration _noticeDuration = Duration(seconds: 4);

/// Elevation of the route point closest to [p], if the route has elevation data.
double? _nearestAltitude(GpsCoordinate p, List<GpsCoordinate> route) {
  GpsCoordinate? best;
  var bestD = double.infinity;
  for (final c in route) {
    final d = haversine(p, c);
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best?.altitude;
}

/// Draw a route from checkpoints on a map; the router finds the paths, the steepness is shown.
class PlanView extends ConsumerStatefulWidget {
  const PlanView({super.key});

  @override
  ConsumerState<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<PlanView> {
  GpsCoordinate? _position;
  bool _locating = false;
  MapFocus? _focus;
  Place? _place;
  String? _notice;
  Timer? _noticeTimer;
  GpsCoordinate? _center;
  int _focusKey = 0;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    // Start on the user's position for a new plan; stay quiet if it isn't available.
    if (ref.read(planProvider).checkpoints.isEmpty) Future.microtask(() => _locate(silent: true));
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _moveTo(GpsCoordinate center, {double? zoom, LatLngBounds? bounds}) {
    setState(() => _focus = MapFocus(key: ++_focusKey, center: center, zoom: zoom, bounds: bounds));
  }

  void _showNotice(String text) {
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(_noticeDuration, () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _locate({required bool silent}) async {
    setState(() => _locating = true);
    try {
      await GpsService.ensurePermission();
      final fix = await GpsService.currentPosition();
      if (!mounted) return;
      setState(() {
        _position = fix;
        _center = fix;
      });
      _moveTo(fix);
    } catch (e) {
      if (!silent && mounted) _showNotice('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _add(GpsCoordinate p) {
    final place = _place;
    final named =
        place != null &&
        haversine(p, GpsCoordinate(latitude: place.latitude, longitude: place.longitude)) <= _placeSnapM;
    ref
        .read(planProvider.notifier)
        .addCheckpoint(
          named ? GpsCoordinate(latitude: place.latitude, longitude: place.longitude) : p,
          name: named ? place.name : null,
        );
  }

  void _showPlace(Place p) {
    setState(() => _place = p);
    final center = GpsCoordinate(latitude: p.latitude, longitude: p.longitude);
    if (p.kind == PlaceKind.peak || !p.hasBounds) {
      _moveTo(center, zoom: p.kind == PlaceKind.peak ? 15 : null);
    } else {
      _moveTo(center, bounds: LatLngBounds(LatLng(p.south!, p.west!), LatLng(p.north!, p.east!)));
    }
  }

  void _cancel() {
    ref.read(planProvider.notifier).reset();
    context.goBack();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final plan = ref.watch(planProvider);
    final controller = ref.read(planProvider.notifier);
    final route = plan.variants.firstOrNull;
    final hint = plan.checkpoints.isEmpty ? t('plan.hintStart') : t('plan.hintNext');
    final top = MediaQuery.of(context).padding.top;

    Widget floating({required Widget child, double? width}) => Material(
      color: c.surface,
      elevation: 3,
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 44,
        width: width,
        child: Center(child: child),
      ),
    );

    return Scaffold(
      backgroundColor: c.map,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: PlanMap(
                    checkpoints: plan.checkpoints,
                    variants: plan.variants,
                    selectedId: route?.id,
                    onlySelected: true,
                    cursor: plan.cursor,
                    position: _position,
                    place: _place == null
                        ? null
                        : GpsCoordinate(latitude: _place!.latitude, longitude: _place!.longitude),
                    focus: _focus,
                    onViewChange: (center) => _center = center,
                    onAdd: _add,
                    onMove: controller.moveCheckpoint,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: top + 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      floating(
                        child: TextButton(
                          onPressed: _cancel,
                          child: Text(
                            t('common.cancel'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PlaceSearch(
                          near: () => _center,
                          onSelect: _showPlace,
                          onClear: () => setState(() => _place = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      floating(
                        width: 44,
                        child: IconButton(
                          tooltip: t('plan.undo'),
                          onPressed: plan.checkpoints.isEmpty ? null : controller.undo,
                          icon: const Icon(Icons.undo, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: top + 76,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _notice != null ? c.danger : c.ink,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _notice ?? hint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _notice != null ? Colors.white : c.onInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 44,
                  child: floating(
                    width: 44,
                    child: IconButton(
                      tooltip: t('plan.locate'),
                      onPressed: _locating ? null : () => _locate(silent: false),
                      icon: Icon(
                        _position != null ? Icons.my_location : Icons.location_searching,
                        size: 20,
                        color: _position != null ? c.route : c.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          CollapsibleSheet(
            collapsed: _collapsed,
            onCollapsedChange: (v) => setState(() => _collapsed = v),
            handleLabel: t(_collapsed ? 'plan.sheetShow' : 'plan.sheetHide'),
            summary: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: plan.status == PlanStatus.ready && route != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t(
                                  plan.loop && plan.checkpoints.length > 1 ? 'plan.summaryLoop' : 'plan.summaryOneWay',
                                  {
                                    'checkpoints': plural(t, 'plan.checkpoint', plan.checkpoints.length),
                                    'marked': (route.analysis.markedShare * 100).round(),
                                  },
                                ),
                                style: TextStyle(fontSize: 13, color: c.muted),
                              ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: formatDistance(route.analysis.distanceM),
                                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.ink),
                                    ),
                                    TextSpan(
                                      text: ' · ${climbAndTime(route.analysis)}',
                                      style: TextStyle(fontSize: 15, color: c.inkSoft),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : plan.status == PlanStatus.loading
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 12,
                                width: 190,
                                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(4)),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                height: 24,
                                width: 160,
                                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(4)),
                              ),
                            ],
                          )
                        : plan.status == PlanStatus.error
                        ? Text(plan.error ?? '', style: TextStyle(fontSize: 15, color: c.danger))
                        : Text(t('plan.empty'), style: TextStyle(fontSize: 15, color: c.muted)),
                  ),
                  if (plan.status == PlanStatus.ready && route != null) DifficultyChip(route.analysis.difficulty, t: t),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (plan.status == PlanStatus.loading)
                  SteepnessProfileSkeleton(t: t)
                else if (plan.status == PlanStatus.ready && route != null)
                  SteepnessProfile(
                    coordinates: route.coordinates,
                    checkpoints: [for (final cp in plan.checkpoints) cp.coordinate],
                    onCursor: controller.setCursor,
                    t: t,
                  ),
                const SizedBox(height: 12),
                if (plan.checkpoints.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < plan.checkpoints.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: c.line),
                          _CheckpointRow(
                            key: ValueKey(plan.checkpoints[i].id),
                            checkpoint: plan.checkpoints[i],
                            index: i,
                            altitude: route == null
                                ? null
                                : _nearestAltitude(plan.checkpoints[i].coordinate, route.coordinates),
                            t: t,
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(t('plan.loop')),
                      selected: plan.loop,
                      onSelected: controller.setLoop,
                      showCheckmark: true,
                    ),
                    FilterChip(
                      label: Text(t('plan.avoidRoads')),
                      selected: plan.avoidRoads,
                      onSelected: controller.setAvoidRoads,
                      showCheckmark: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  icon: Icons.arrow_forward,
                  label: plan.variants.length > 1 ? t('plan.compare', {'n': plan.variants.length}) : t('plan.review'),
                  onPressed: plan.status == PlanStatus.ready ? () => context.goTo(Routes.planRoutes) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One checkpoint of the list: its pin label, a name that can be edited in place, and a remove button.
class _CheckpointRow extends ConsumerStatefulWidget {
  const _CheckpointRow({
    super.key,
    required this.checkpoint,
    required this.index,
    required this.altitude,
    required this.t,
  });

  final Checkpoint checkpoint;
  final int index;
  final double? altitude;
  final TFunction t;

  @override
  ConsumerState<_CheckpointRow> createState() => _CheckpointRowState();
}

class _CheckpointRowState extends ConsumerState<_CheckpointRow> {
  bool _editing = false;
  late final TextEditingController _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _commit() {
    ref.read(planProvider.notifier).renameCheckpoint(widget.checkpoint.id, _draft.text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final c = context.colors;
    final name = checkpointName(widget.checkpoint, widget.index, t);
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.ink, width: 2),
              ),
              child: Text(
                checkpointLabel(widget.index),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _editing
                  ? TextField(
                      controller: _draft,
                      autofocus: true,
                      maxLength: 60,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _commit(),
                      onTapOutside: (_) => _commit(),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        hintText: checkpointName(widget.checkpoint.copyWith(name: () => null), widget.index, t),
                      ),
                    )
                  : InkWell(
                      onTap: () {
                        _draft.text = widget.checkpoint.name ?? '';
                        setState(() => _editing = true);
                      },
                      child: Semantics(
                        label: t('plan.rename', {'name': name}),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: widget.checkpoint.name != null ? c.ink : c.inkSoft,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.edit_outlined, size: 14, color: c.muted),
                          ],
                        ),
                      ),
                    ),
            ),
            if (widget.altitude != null)
              Text(formatElevation(widget.altitude), style: TextStyle(fontSize: 13, color: c.muted)),
            IconButton(
              tooltip: t('plan.remove', {'name': name}),
              onPressed: () => ref.read(planProvider.notifier).removeCheckpoint(widget.checkpoint.id),
              icon: Icon(Icons.close, size: 16, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
