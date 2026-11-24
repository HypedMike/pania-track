import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/analysis/geo.dart' show Activity;
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/recording_controller.dart';
import '../application/trail_controller.dart';
import '../domain/trail.dart';
import 'trail_map.dart';
import 'trail_widgets.dart';

/// Name and save a finished recording.
class SaveRecordingView extends ConsumerStatefulWidget {
  const SaveRecordingView({super.key});

  @override
  ConsumerState<SaveRecordingView> createState() => _SaveRecordingViewState();
}

class _SaveRecordingViewState extends ConsumerState<SaveRecordingView> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  Activity _activity = Activity.foot;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Nothing to save when opened without a recording (e.g. after a restart).
    Future.microtask(() {
      if (mounted && ref.read(recordingProvider).status == RecordingStatus.idle) {
        context.goTo(Routes.home, replace: true);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final rec = ref.read(recordingProvider);
    if (rec.points.isEmpty) {
      setState(() => _error = t('save.noPoints'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final trail = await ref
          .read(trailsProvider.notifier)
          .createTrail(
            NewTrail(
              name: _name.text,
              description: _description.text,
              source: TrailSource.recorded,
              activity: _activity,
              coordinates: rec.points,
              waypoints: rec.waypoints,
            ),
          );
      if (!mounted) return;
      // Leave first: clearing the session while still here would trigger the redirect home.
      context.goTo(Routes.trailDetail(trail.id), replace: true);
      ref.read(recordingProvider.notifier).discard();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _saving = false;
        });
      }
    }
  }

  Future<void> _resume() async {
    await ref.read(recordingProvider.notifier).resume();
    if (mounted) context.goTo(Routes.record, replace: true);
  }

  Future<void> _discard() async {
    final t = ref.read(tProvider);
    final ok = await confirmDialog(
      context,
      message: t('save.confirmDiscard'),
      confirmLabel: t('save.discard'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    context.goTo(Routes.home, replace: true);
    ref.read(recordingProvider.notifier).discard();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final rec = ref.watch(recordingProvider);
    if (rec.status == RecordingStatus.idle) return const Scaffold(body: SizedBox.shrink());
    final stats = computeStats(rec.points);
    String fmt(int ms) => DateFormat.Hm(I18n.locale).format(DateTime.fromMillisecondsSinceEpoch(ms));

    return Scaffold(
      body: SafeArea(
        child: PageColumn(
          gap: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('save.title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                if (rec.startedAt != null)
                  Text(
                    t('save.today', {'from': fmt(rec.startedAt!), 'to': fmt(DateTime.now().millisecondsSinceEpoch)}),
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
              ],
            ),
            if (rec.points.isNotEmpty)
              SizedBox(
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: TrailMap(coordinates: rec.points, waypoints: rec.waypoints),
                ),
              ),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                StatTile(label: t('common.distance'), value: formatDistance(stats.distanceM)),
                StatTile(
                  label: t('save.movingTime'),
                  value: formatClock(rec.elapsedMs).replaceFirst(RegExp(r'^00:'), ''),
                ),
                StatTile(label: t('common.elevationGain'), value: formatElevation(stats.elevationGainM, signed: true)),
                StatTile(label: t('save.points'), value: '${rec.points.length}'),
              ],
            ),
            LabeledField(
              label: t('common.name'),
              controller: _name,
              hint: t('save.namePlaceholder'),
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            ActivityPicker(value: _activity, onChanged: (a) => setState(() => _activity = a), t: t),
            LabeledField(
              label: t('common.description'),
              controller: _description,
              hint: t('common.notesPlaceholder'),
              maxLines: 3,
            ),
            if (_error != null) ErrorText(_error!),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: SecondaryButton(label: t('common.resume'), onPressed: _resume),
                ),
                Expanded(
                  child: PrimaryButton(
                    label: _saving ? t('common.saving') : t('common.saveTrail'),
                    onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _discard,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              child: Text(t('save.discard')),
            ),
          ],
        ),
      ),
    );
  }
}
