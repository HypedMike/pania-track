import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/analysis/geo.dart' show Activity;
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../../trail/domain/trail.dart';
import '../application/plan_controller.dart';
import '../domain/route_analysis.dart';
import '../domain/route_planner.dart';
import 'plan_map.dart';
import 'route_badges.dart';
import 'steepness_profile.dart';

Color _swatch(AppColors c, VariantKind kind) => switch (kind) {
  VariantKind.balanced => c.brandFg,
  VariantKind.gentlest => c.route,
  VariantKind.direct => c.alt,
};

class _HazardNote extends StatelessWidget {
  const _HazardNote(this.hazard, this.t);

  final Hazard hazard;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = hazard.kind == HazardKind.steep
        ? t('variants.hazard.steep', {'n': hazard.value.round()})
        : t('variants.hazard.${hazard.kind.name}', {'d': formatDistance(hazard.value)});
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: Icon(Icons.warning_amber_rounded, size: 16, color: c.warnInk),
          ),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: c.warnInk)),
          ),
        ],
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.variant, required this.selected, required this.onSelect, required this.t});

  final RouteVariant variant;
  final bool selected;
  final VoidCallback onSelect;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = variant.analysis;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? c.brandFg : c.line, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? c.brand : c.muted,
                ),
                const SizedBox(width: 10),
                Container(
                  width: 16,
                  height: 4,
                  decoration: BoxDecoration(color: _swatch(c, variant.kind), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${variant.letter} · ${t('variants.kind.${variant.kind.name}')}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (variant.kind == VariantKind.balanced)
                  Pill(t('variants.recommended'), background: c.brandTint, foreground: c.brandTintInk),
              ],
            ),
            const SizedBox(height: 8),
            Text(routeLine(a), style: TextStyle(fontSize: 14, color: c.inkSoft)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                DifficultyChip(a.difficulty, t: t),
                InfoChip(t('variants.maxSlope', {'n': a.maxSlopePct.round()})),
                if (a.markedShare >= 0.05) InfoChip(t('variants.marked', {'n': (a.markedShare * 100).round()})),
                if (a.roadM >= 100) InfoChip(t('variants.roads', {'d': formatDistance(a.roadM)})),
              ],
            ),
            for (final h in a.hazards) _HazardNote(h, t),
          ],
        ),
      ),
    );
  }
}

/// The variants of a planned route side by side; the chosen one is saved as a trail.
class RouteVariantsView extends ConsumerStatefulWidget {
  const RouteVariantsView({super.key});

  @override
  ConsumerState<RouteVariantsView> createState() => _RouteVariantsViewState();
}

class _RouteVariantsViewState extends ConsumerState<RouteVariantsView> {
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Opened directly (or after the plan was reset): nothing to compare.
    Future.microtask(() {
      if (mounted && ref.read(planProvider).variants.isEmpty && !_saved) context.goTo(Routes.plan, replace: true);
    });
  }

  Future<void> _save(RouteVariant selected) async {
    final t = ref.read(tProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final plan = ref.read(planProvider);
      final waypoints = [
        for (var i = 0; i < plan.checkpoints.length; i++)
          Waypoint(
            latitude: plan.checkpoints[i].latitude,
            longitude: plan.checkpoints[i].longitude,
            name: checkpointName(plan.checkpoints[i], i, t),
          ),
      ];
      final trail = await ref
          .read(trailsProvider.notifier)
          .createTrail(
            NewTrail(
              name: t('variants.defaultName', {'date': formatDate(DateTime.now())}),
              source: TrailSource.planned,
              activity: Activity.foot,
              coordinates: selected.coordinates,
              waypoints: waypoints,
            ),
          );
      _saved = true;
      if (!mounted) return;
      context.goTo(Routes.trailDetail(trail.id), replace: true);
      ref.read(planProvider.notifier).reset();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final plan = ref.watch(planProvider);
    final selected = plan.selected;
    if (selected == null) return const Scaffold(body: SizedBox.shrink());
    return PageScaffold(
      title: t('variants.title'),
      onBack: context.goBack,
      backLabel: t('variants.back'),
      body: PageColumn(
        gap: 12,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        children: [
          SizedBox(
            height: 176,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PlanMap(
                checkpoints: plan.checkpoints,
                variants: plan.variants,
                selectedId: selected.id,
                cursor: plan.cursor,
              ),
            ),
          ),
          SteepnessProfile(
            coordinates: selected.coordinates,
            checkpoints: [for (final cp in plan.checkpoints) cp.coordinate],
            onCursor: ref.read(planProvider.notifier).setCursor,
            t: t,
          ),
          for (final v in plan.variants)
            _VariantCard(
              variant: v,
              selected: v.id == selected.id,
              onSelect: () => ref.read(planProvider.notifier).select(v.id),
              t: t,
            ),
          if (plan.variants.length == 1) Text(t('variants.onlyOne'), style: TextStyle(fontSize: 13, color: c.muted)),
          Text(t('variants.attribution'), style: TextStyle(fontSize: 12, color: c.muted)),
          if (_error != null) ErrorText(_error!),
          PrimaryButton(
            label: _saving ? t('common.saving') : t('variants.save', {'letter': selected.letter}),
            onPressed: _saving ? null : () => _save(selected),
          ),
        ],
      ),
    );
  }
}
