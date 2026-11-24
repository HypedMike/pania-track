import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../tour/application/tour_controller.dart';
import '../../tour/presentation/tour_banner.dart';
import '../../trail/application/recording_controller.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/trail.dart';
import '../../trail/presentation/trail_widgets.dart';

enum _Filter { all, recorded, imported, planned, bookmarked }

/// The Trails tab: record, import or plan, and the list of saved trails.
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final trailsAsync = ref.watch(trailsProvider);
    final trails = trailsAsync.value ?? const <Trail>[];
    final recording = ref.watch(recordingProvider.select((r) => r.status));
    final tourTrailId = ref.watch(tourProvider.select((s) => s.active ? s.trailId : null));

    final stats = {for (final tr in trails) tr.id: computeStats(tr.coordinates)};
    final totalM = stats.values.fold<double>(0, (sum, s) => sum + s.distanceM);
    int count(TrailSource s) => trails.where((x) => x.source == s).length;
    final tabs = <(_Filter, String, int)>[
      (_Filter.all, t('home.filterAll'), trails.length),
      (_Filter.recorded, t('home.filterRecorded'), count(TrailSource.recorded)),
      (_Filter.imported, t('home.filterImported'), count(TrailSource.imported)),
      // Only shown once there is something to filter, so the row fits on a phone.
      if (count(TrailSource.planned) > 0) (_Filter.planned, t('home.filterPlanned'), count(TrailSource.planned)),
      if (count(TrailSource.bookmarked) > 0) (_Filter.bookmarked, t('home.filterSaved'), count(TrailSource.bookmarked)),
    ];
    final visible = _filter == _Filter.all ? trails : trails.where((x) => x.source.name == _filter.name).toList();

    Widget action(IconData icon, String label, VoidCallback? onTap, {bool filled = false}) => Expanded(
      child: Material(
        color: filled ? c.brand : c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: filled ? null : Border.all(color: c.lineStrong),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: filled ? Colors.white : c.ink),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: filled ? Colors.white : c.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return PageColumn(
      gap: 20,
      children: [
        LargeTitle(
          t('home.title'),
          subtitle: t('home.summary', {
            'trails': plural(t, 'common.trail', trails.length),
            'distance': formatDistance(totalM),
          }),
          leading: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logo.png', width: 28, height: 28),
                ),
                const SizedBox(width: 6),
                Text(
                  'Pania',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.brandFg),
                ),
              ],
            ),
          ),
          trailing: RoundIconButton(
            icon: Icons.tune,
            tooltip: t('home.settings'),
            onPressed: () => context.goTo(Routes.settings),
          ),
        ),
        if (recording != RecordingStatus.idle)
          Material(
            color: c.danger,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.goTo(Routes.record),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const StatusDot(color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          recording == RecordingStatus.paused ? t('banner.paused') : t('banner.inProgress'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                    Text(
                      t('banner.open'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (tourTrailId != null) TourBanner(onOpen: () => context.goTo(Routes.tour(tourTrailId)), t: t),
        Column(
          children: [
            Row(
              spacing: 10,
              children: [
                action(
                  Icons.fiber_manual_record_outlined,
                  t('home.record'),
                  recording != RecordingStatus.idle || tourTrailId != null ? null : () => context.goTo(Routes.record),
                  filled: true,
                ),
                action(Icons.file_upload_outlined, t('home.import'), () => context.goTo(Routes.importTrail)),
                action(Icons.route_outlined, t('home.plan'), () => context.goTo(Routes.plan)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t('home.actionsHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ],
        ),
        if (trails.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (id, label, n) in tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => setState(() => _filter = id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: id == _filter ? c.ink : c.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: id == _filter ? null : Border.all(color: c.lineStrong),
                        ),
                        child: Text(
                          '$label · $n',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: id == _filter ? FontWeight.w600 : FontWeight.w500,
                            color: id == _filter ? c.onInk : c.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (trailsAsync.isLoading && trails.isEmpty) Text(t('common.loading'), style: TextStyle(color: c.muted)),
        if (trailsAsync.hasError)
          Text(t('home.loadError', {'error': '${trailsAsync.error}'}), style: TextStyle(color: c.danger)),
        if (!trailsAsync.isLoading && !trailsAsync.hasError && trails.isEmpty)
          Panel(
            padding: const EdgeInsets.all(20),
            child: Text(
              t('home.empty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
        for (final trail in visible) _TrailListItem(trail: trail, stats: stats[trail.id]!, t: t),
      ],
    );
  }
}

class _TrailListItem extends StatelessWidget {
  const _TrailListItem({required this.trail, required this.stats, required this.t});

  final Trail trail;
  final TrailStats stats;
  final TFunction t;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.goTo(Routes.trailDetail(trail.id)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            TrailPreview(coordinates: trail.coordinates, source: trail.source),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trail.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SourceBadge(trail.source, t: t),
                      Pill(t('activity.${trail.activity.name}')),
                      Text(formatDate(trail.createdAt), style: TextStyle(fontSize: 13, color: c.muted)),
                    ],
                  ),
                  if (trail.coordinates.length > 1) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${formatDistance(stats.distanceM)}'
                      '${stats.elevationGainM != null ? ' · ${formatElevation(stats.elevationGainM, signed: true)}' : ''}'
                      '${stats.durationMs != null ? ' · ${formatDuration(stats.durationMs)}' : ''}',
                      style: TextStyle(fontSize: 14, color: c.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
