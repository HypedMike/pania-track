import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../profile/domain/profile.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/trail.dart';
import '../../trail/presentation/trail_map.dart';
import '../../trail/presentation/trail_widgets.dart';
import '../application/explore_controller.dart';
import '../data/sharing_api.dart';
import 'difficulty_badge.dart';

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: context.colors.muted)),
      Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    ],
  );
}

/// A trail shared by someone else, with the button that saves a copy to this device.
class SharedTrailView extends ConsumerStatefulWidget {
  const SharedTrailView({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<SharedTrailView> createState() => _SharedTrailViewState();
}

class _SharedTrailViewState extends ConsumerState<SharedTrailView> {
  bool _saving = false;

  Future<void> _bookmark(SharedTrail trail, Trail? saved) async {
    final t = ref.read(tProvider);
    setState(() => _saving = true);
    try {
      final author = TrailAuthor(
        pubkey: trail.authorPubkey,
        npub: trail.authorNpub,
        name: trail.authorName,
        dTag: trail.dTag,
        eventId: trail.eventId,
      );
      final controller = ref.read(trailsProvider.notifier);
      if (saved != null) {
        await controller.updateTrail(
          saved.copyWith(
            name: trail.name,
            description: trail.description,
            activity: trail.activity,
            coordinates: sharedCoordinates(trail),
            waypoints: sharedWaypoints(trail),
            author: author,
          ),
        );
      } else {
        await controller.createTrail(
          NewTrail(
            name: trail.name,
            description: trail.description,
            source: TrailSource.bookmarked,
            activity: trail.activity,
            coordinates: sharedCoordinates(trail),
            waypoints: sharedWaypoints(trail),
            author: author,
          ),
        );
      }
      if (mounted) showToast(context, t('shared.savedToast'));
    } catch (e) {
      if (mounted) showToast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyNpub(String npub) async {
    final t = ref.read(tProvider);
    await Clipboard.setData(ClipboardData(text: npub));
    if (mounted) showToast(context, t('profile.copied'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final results = ref.watch(exploreProvider).results;
    final found = results.where((r) => r.eventId == widget.eventId);
    final trail = found.isEmpty ? null : found.first;
    final trails = ref.watch(trailsProvider).value ?? const <Trail>[];

    if (trail == null) {
      return PageScaffold(
        onBack: context.goBack,
        backLabel: t('shared.back'),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(t('shared.notFound'), style: TextStyle(color: c.muted)),
        ),
      );
    }

    final coordinates = sharedCoordinates(trail);
    final stats = computeStats(coordinates);
    // The same original (author + trail id), possibly saved from an older version of it.
    final saved = trails
        .where((x) => x.author?.pubkey == trail.authorPubkey && x.author?.dTag == trail.dTag)
        .firstOrNull;
    final upToDate = saved?.author?.eventId == trail.eventId;
    final f = trail.fidelity;
    final reported = f.points != null && f.originalPoints != null && f.removedPct != null && f.maxErrorM != null;

    return PageScaffold(
      onBack: context.goBack,
      backLabel: t('shared.back'),
      body: PageColumn(
        gap: 14,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(trail.name, style: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DifficultyBadge(trail.difficulty, t: t),
              Pill(t('activity.${trail.activity.name}')),
              Text(
                t('explore.away', {'n': trail.awayKm.toStringAsFixed(1)}),
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ],
          ),
          Panel(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('shared.author'), style: TextStyle(fontSize: 12, color: c.muted)),
                      Text(
                        trail.authorName ?? t('explore.anonymous'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        shortNpub(trail.authorNpub),
                        style: TextStyle(fontSize: 13, color: c.muted, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                RoundIconButton(
                  icon: Icons.copy,
                  tooltip: t('profile.copyKey'),
                  onPressed: () => _copyNpub(trail.authorNpub),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 288,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: TrailMap(coordinates: coordinates, waypoints: sharedWaypoints(trail)),
            ),
          ),
          Panel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: _Stat(t('common.distance'), formatDistance(trail.distanceM))),
                Expanded(child: _Stat(t('detail.gain'), formatElevation(trail.gainM, signed: true))),
                Expanded(child: _Stat(t('detail.highest'), formatElevation(stats.highestM))),
              ],
            ),
          ),
          ElevationProfile(coordinates: coordinates, t: t),
          if (trail.description.isNotEmpty)
            Text(trail.description, style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft)),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('shared.fidelityTitle'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  reported
                      ? t('shared.fidelityText', {
                          'kept': f.points!.round(),
                          'total': f.originalPoints!.round(),
                          'removed': f.removedPct,
                          'max': f.maxErrorM,
                          'p95': f.p95ErrorM ?? f.maxErrorM!,
                        })
                      : t('shared.fidelityNone'),
                  style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
                ),
              ],
            ),
          ),
          if (saved != null && upToDate) ...[
            Text(
              t('shared.saved'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.brandFg),
            ),
            SecondaryButton(label: t('shared.openSaved'), onPressed: () => context.goTo(Routes.trailDetail(saved.id))),
          ] else
            PrimaryButton(
              icon: Icons.bookmark_border,
              label: _saving ? t('common.saving') : (saved != null ? t('shared.updateSaved') : t('shared.bookmark')),
              onPressed: _saving ? null : () => _bookmark(trail, saved),
            ),
        ],
      ),
    );
  }
}
