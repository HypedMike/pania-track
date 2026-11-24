import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/gps_service.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/analysis/geo.dart';
import '../../../core/rust/tracks/difficulty.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/explore_controller.dart';
import 'difficulty_badge.dart';
import 'explore_map.dart';

/// Map and list of trails other people shared near you.
class ExploreView extends ConsumerStatefulWidget {
  const ExploreView({super.key});

  @override
  ConsumerState<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends ConsumerState<ExploreView> {
  LatLng? _me;
  bool _locationFailed = false;
  SearchCenter? _mapCenter;

  @override
  void initState() {
    super.initState();
    // First visit: search around the user. Later visits keep the previous results.
    if (ref.read(exploreProvider).center == null) Future.microtask(_useMyLocation);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locationFailed = false);
    try {
      await GpsService.ensurePermission();
      final p = await GpsService.currentPosition();
      if (!mounted) return;
      setState(() => _me = LatLng(p.latitude, p.longitude));
      ref.read(exploreProvider.notifier).search(SearchCenter(p.latitude, p.longitude));
    } catch (_) {
      if (mounted) setState(() => _locationFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final state = ref.watch(exploreProvider);
    final controller = ref.read(exploreProvider.notifier);
    final f = state.filters;

    void toggleDifficulty(Difficulty d) => controller.setFilters(
      f.copyWith(
        difficulty: f.difficulty.contains(d)
            ? [
                for (final x in f.difficulty)
                  if (x != d) x,
              ]
            : [...f.difficulty, d],
      ),
    );

    return PageColumn(
      gap: 16,
      children: [
        LargeTitle(t('explore.title'), subtitle: t('explore.subtitle')),
        SizedBox(
          height: (MediaQuery.of(context).size.height * 0.4).clamp(256, 480),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ExploreMap(
                    results: state.results,
                    selectedId: state.selectedId,
                    me: _me,
                    onSelect: controller.select,
                    onCenter: (lat, lon) => _mapCenter = SearchCenter(lat, lon),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MapButton(label: t('explore.myLocation'), onPressed: _useMyLocation, filled: false),
                      _MapButton(
                        label: t('explore.searchHere'),
                        onPressed: () {
                          final center = _mapCenter;
                          if (center != null) controller.search(center);
                        },
                        filled: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_locationFailed) Text(t('explore.locationDenied'), style: TextStyle(fontSize: 14, color: c.muted)),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChipRow<int>(
                label: t('explore.within'),
                options: [
                  for (final n in radiiKm) (n, t('explore.km', {'n': n})),
                ],
                selected: [f.radiusKm],
                onToggle: (n) => controller.setFilters(f.copyWith(radiusKm: n)),
              ),
              const SizedBox(height: 12),
              ChipRow<LengthFilter>(
                label: t('explore.length'),
                options: [for (final l in LengthFilter.values) (l, t(l.labelKey))],
                selected: [f.length],
                onToggle: (l) => controller.setFilters(f.copyWith(length: l)),
              ),
              const SizedBox(height: 12),
              ChipRow<Activity?>(
                label: t('explore.activity'),
                options: [
                  (null, t('explore.activityAll')),
                  (Activity.foot, t('activity.foot')),
                  (Activity.bike, t('activity.bike')),
                ],
                selected: [f.activity],
                onToggle: (a) => controller.setFilters(f.copyWith(activity: () => a)),
              ),
              const SizedBox(height: 12),
              ChipRow<Difficulty>(
                label: t('explore.difficulty'),
                options: [for (final d in Difficulty.values) (d, t('difficulty.${d.name}'))],
                selected: f.difficulty,
                onToggle: toggleDifficulty,
              ),
            ],
          ),
        ),
        if (state.loading) Text(t('explore.searching'), style: TextStyle(fontSize: 14, color: c.muted)),
        if (!state.loading && state.error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnTint, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('explore.error', {'error': state.error}), style: TextStyle(fontSize: 14, color: c.warnInk)),
                TextButton(
                  onPressed: () => context.goTo(Routes.nostrSettings),
                  child: Text(t('explore.relaySettings')),
                ),
              ],
            ),
          ),
        if (!state.loading && state.error == null && state.searched && state.results.isEmpty)
          Panel(
            child: Text(t('explore.empty'), style: TextStyle(fontSize: 14, color: c.muted)),
          ),
        if (!state.loading && state.results.isNotEmpty)
          Text(
            t('explore.results', {'n': state.results.length}),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        for (final r in state.results)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.goTo(Routes.exploreTrail(r.eventId)),
            onFocusChange: (focused) => focused ? controller.select(r.eventId) : null,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: r.eventId == state.selectedId ? c.brandFg : c.line,
                  width: r.eventId == state.selectedId ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    '${formatDistance(r.distanceM)} · ${t('explore.away', {'n': r.awayKm.toStringAsFixed(1)})} · '
                    '${r.authorName != null ? t('explore.by', {'name': r.authorName}) : t('explore.anonymous')}',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      DifficultyBadge(r.difficulty, t: t),
                      const SizedBox(width: 8),
                      Pill(t('activity.${r.activity.name}')),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.label, required this.onPressed, required this.filled});

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: filled ? c.brand : c.surface,
      elevation: 2,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: c.lineStrong)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: filled ? Colors.white : c.ink),
          ),
        ),
      ),
    );
  }
}
