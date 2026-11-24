import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/capture_lock.dart';
import '../../../core/gps/track_files.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/analysis/geo.dart' show Activity;
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/toast.dart';
import '../../../core/ui/widgets.dart';
import '../../profile/domain/profile.dart';
import '../../sharing/data/sharing_api.dart';
import '../../sharing/presentation/share_trail_dialog.dart';
import '../../tour/application/tour_controller.dart';
import '../../tour/data/tour_run_repository.dart';
import '../application/trail_controller.dart';
import '../domain/trail.dart';
import 'trail_map.dart';
import 'trail_widgets.dart';

final _runsProvider = FutureProvider.autoDispose.family<List<TourRun>, String>((ref, trailId) async {
  // A tour that ends on this trail adds a run, so look again when the tour state changes.
  ref.watch(tourProvider.select((s) => s.active));
  try {
    return await ref.read(tourRunRepositoryProvider).listForTrail(trailId);
  } catch (_) {
    return const [];
  }
});

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

/// One trail: map, numbers, profile, tour, analysis, sharing, edit and export.
class TrailDetailView extends ConsumerStatefulWidget {
  const TrailDetailView({super.key, required this.trailId});

  final String trailId;

  @override
  ConsumerState<TrailDetailView> createState() => _TrailDetailViewState();
}

class _TrailDetailViewState extends ConsumerState<TrailDetailView> {
  bool _editing = false;
  final _name = TextEditingController();
  final _description = TextEditingController();
  Activity _activity = Activity.foot;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _startEditing(Trail trail) {
    _name.text = trail.name;
    _description.text = trail.description;
    setState(() {
      _activity = trail.activity;
      _error = null;
      _editing = true;
    });
  }

  Future<void> _saveEdits(Trail trail) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(trailsProvider.notifier)
          .updateTrail(trail.copyWith(name: _name.text, description: _description.text, activity: _activity));
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startTour() {
    final t = ref.read(tProvider);
    if (CaptureLock.heldBy == CaptureOwner.recording) {
      AppToast.show(t('error.recordingActive'), level: ToastLevel.error);
      return;
    }
    context.goTo(Routes.tour(widget.trailId));
  }

  Future<void> _delete(Trail trail) async {
    final t = ref.read(tProvider);
    final ok = await confirmDialog(
      context,
      message: t('detail.confirmDelete', {'name': trail.name}),
      confirmLabel: t('detail.delete'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      // A trail that is public should not silently stay public after it is gone from the phone.
      if (trail.sharedAt != null) {
        final remove = await confirmDialog(
          context,
          message: t('share.askRemove'),
          confirmLabel: t('share.stop'),
          cancelLabel: t('common.cancel'),
        );
        if (remove) await SharingApi.unshareTrail(trail.id).catchError((Object _) => <String>[]);
      }
      await ref.read(trailsProvider.notifier).deleteTrail(trail.id);
      if (mounted) context.goTo(Routes.home, replace: true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final trailsAsync = ref.watch(trailsProvider);
    final trail = ref.watch(trailProvider(widget.trailId));
    final touringHere = ref.watch(tourProvider.select((s) => s.active && s.trailId == widget.trailId));
    final runs = (ref.watch(_runsProvider(widget.trailId)).value ?? const <TourRun>[])
        .where((r) => r.endedAt != null)
        .toList();

    if (trail == null) {
      return PageScaffold(
        onBack: context.goBack,
        backLabel: t('detail.trails'),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            trailsAsync.isLoading ? t('common.loading') : t('detail.notFound'),
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    }

    final stats = computeStats(trail.coordinates);
    final pointCount = trail.coordinates.length;
    final n = NumberFormat.decimalPattern(I18n.locale);

    return PageScaffold(
      onBack: context.goBack,
      backLabel: t('detail.trails'),
      action: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            RoundIconButton(
              icon: Icons.ios_share,
              tooltip: t('detail.share'),
              size: 40,
              onPressed: () => shareGpx(trail),
            ),
            PopupMenuButton<String>(
              tooltip: t('detail.more'),
              icon: const Icon(Icons.more_horiz),
              onSelected: (_) => _delete(trail),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    t('detail.delete'),
                    style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: PageColumn(
        gap: 14,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          if (_editing) ...[
            LabeledField(
              label: t('common.name'),
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            ActivityPicker(value: _activity, onChanged: (a) => setState(() => _activity = a), t: t),
            LabeledField(label: t('common.description'), controller: _description, maxLines: 3),
            if (_error != null) ErrorText(_error!),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: SecondaryButton(label: t('common.cancel'), onPressed: () => setState(() => _editing = false)),
                ),
                Expanded(
                  child: PrimaryButton(
                    label: _saving ? t('common.saving') : t('detail.save'),
                    onPressed: _saving || _name.text.trim().isEmpty ? null : () => _saveEdits(trail),
                  ),
                ),
              ],
            ),
          ] else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trail.name,
                  style: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SourceBadge(trail.source, t: t),
                    Pill(t('activity.${trail.activity.name}')),
                    Text(
                      '${t('detail.pointsLine', {
                        'date': formatDate(trail.createdAt),
                        'points': t('common.pointsCount', {'n': n.format(pointCount)}),
                      })}'
                      '${trail.waypoints.isNotEmpty ? ' · ${plural(t, 'common.waypoint', trail.waypoints.length)}' : ''}',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
                if (trail.author != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 13, color: c.muted),
                        children: [
                          TextSpan(
                            text: '${t('shared.createdBy', {'name': trail.author!.name ?? t('explore.anonymous')})} · ',
                          ),
                          TextSpan(
                            text: shortNpub(trail.author!.npub),
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (trail.sharedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${t('share.shared')}${trail.updatedAt != null && trail.updatedAt!.millisecondsSinceEpoch > trail.sharedAt!.millisecondsSinceEpoch + 1000 ? ' · ${t('share.editedSince')}' : ''}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.brandFg),
                    ),
                  ),
              ],
            ),
          if (pointCount > 0)
            SizedBox(
              height: 288,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: TrailMap(coordinates: trail.coordinates, waypoints: trail.waypoints, source: trail.source),
              ),
            ),
          if (!_editing && pointCount > 1)
            PrimaryButton(
              icon: Icons.play_arrow,
              label: touringHere ? t('tour.resume') : t('tour.start'),
              onPressed: _startTour,
            ),
          if (pointCount > 1)
            Panel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: _Stat(t('common.distance'), formatDistance(stats.distanceM))),
                  Expanded(child: _Stat(t('detail.gain'), formatElevation(stats.elevationGainM, signed: true))),
                  Expanded(child: _Stat(t('detail.highest'), formatElevation(stats.highestM))),
                  Expanded(child: _Stat(t('common.duration'), formatDuration(stats.durationMs))),
                ],
              ),
            ),
          ElevationProfile(coordinates: trail.coordinates, t: t),
          if (!_editing && pointCount > 1)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => context.goTo(Routes.trailAnalysis(trail.id)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t('analysis.open'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Flexible(
                    child: Text(
                      t('analysis.openHint'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          if (!_editing && runs.isNotEmpty)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('review.history'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  for (final r in runs) ...[
                    Divider(height: 1, color: c.line),
                    InkWell(
                      onTap: () => context.goTo(Routes.tourReview(r.id)),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${formatDate(DateTime.fromMillisecondsSinceEpoch(r.startedAt))}${r.finished ? '' : ' · ${t('review.unfinished')}'}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              formatDuration(r.endedAt! - r.startedAt),
                              style: TextStyle(fontSize: 14, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!_editing && trail.description.isNotEmpty)
            Text(trail.description, style: TextStyle(fontSize: 14, height: 1.5, color: c.inkSoft)),
          if (!_editing && _error != null) ErrorText(_error!),
          if (!_editing && trail.source != TrailSource.bookmarked && pointCount > 1)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: c.brandFg,
                side: BorderSide(color: c.brandFg, width: 2),
              ),
              onPressed: () => showShareTrailDialog(context, trail),
              child: Text(trail.sharedAt != null ? t('share.updateShared') : t('share.public')),
            ),
          if (!_editing)
            Row(
              spacing: 12,
              children: [
                Expanded(
                  flex: 1,
                  child: SecondaryButton(label: t('detail.edit'), onPressed: () => _startEditing(trail)),
                ),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    icon: Icons.download,
                    label: t('detail.exportGpx'),
                    onPressed: pointCount == 0 ? null : () => shareGpx(trail),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
