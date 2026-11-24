import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/background_recorder.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/recording_controller.dart';
import 'trail_map.dart';

/// Live recording: the map following the position, the clock and the numbers.
class RecordingView extends ConsumerStatefulWidget {
  const RecordingView({super.key});

  @override
  ConsumerState<RecordingView> createState() => _RecordingViewState();
}

class _RecordingViewState extends ConsumerState<RecordingView> {
  bool _follow = true;
  int _followKey = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Begin a new recording when opened fresh; reopening keeps the one in progress.
    Future.microtask(() => ref.read(recordingProvider.notifier).start());
    // Re-render every second so the clock advances.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(recordingProvider.notifier).pause();
    if (mounted) context.goTo(Routes.saveRecording);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final rec = ref.watch(recordingProvider);
    final controller = ref.read(recordingProvider.notifier);
    final stats = computeStats(rec.points);
    final elapsed = rec.elapsedMs;
    final paused = rec.status == RecordingStatus.paused;
    final idle = rec.status == RecordingStatus.idle;
    final startedLabel = rec.startedAt == null
        ? '…'
        : DateFormat.Hm(I18n.locale).format(DateTime.fromMillisecondsSinceEpoch(rec.startedAt!));
    final accuracy = rec.current?.accuracy;

    Widget roundButton({required IconData icon, required String tooltip, required VoidCallback? onTap}) => Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.lineStrong),
          ),
          child: Opacity(opacity: onTap == null ? 0.5 : 1, child: Icon(icon, size: 22)),
        ),
      ),
    );

    return MapSheetScreen(
      sheetFraction: 0.4,
      minSheetHeight: 330,
      centerTooltip: t('recording.centerMap'),
      onCenter: () => setState(() {
        _follow = true;
        _followKey++;
      }),
      map: TrailMap(
        coordinates: rec.points,
        waypoints: rec.waypoints,
        current: rec.current,
        fit: false,
        follow: _follow,
        followKey: _followKey,
        onUserMove: () {
          if (_follow) setState(() => _follow = false);
        },
      ),
      leftChip: MapChip(
        label: idle ? t('recording.starting') : (paused ? t('recording.paused') : t('recording.recording')),
        onTap: context.goBack,
        leading: StatusDot(color: paused ? c.muted : c.danger),
      ),
      rightChip: MapChip(
        label: accuracy != null ? t('recording.gpsAccuracy', {'m': accuracy.round()}) : t('recording.gpsWaiting'),
        leading: Icon(Icons.signal_cellular_alt, size: 16, color: c.brand),
      ),
      sheet: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('recording.newTrail', {'time': startedLabel}), style: TextStyle(fontSize: 13, color: c.muted)),
          Text(
            formatClock(elapsed),
            style: const TextStyle(
              fontSize: 52,
              height: 1.05,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Metric(label: t('common.distance'), value: formatDistance(stats.distanceM)),
              ),
              Expanded(
                child: Metric(label: t('recording.avgPace'), value: formatPace(stats.distanceM, elapsed)),
              ),
              Expanded(
                child: Metric(
                  label: t('common.elevationGain'),
                  value: formatElevation(stats.elevationGainM, signed: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(12)),
            child: Text(
              rec.error ??
                  t('recording.status', {
                    'points': t('common.pointsCount', {'n': rec.points.length}),
                    'waypoints': plural(t, 'common.waypoint', rec.waypoints.length),
                    'mode': BackgroundRecorder.supported ? t('recording.screenOff') : t('recording.keepOpen'),
                  }),
              style: TextStyle(fontSize: 13, color: c.inkSoft),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 12,
            children: [
              roundButton(
                icon: Icons.add_location_alt_outlined,
                tooltip: t('recording.addWaypoint'),
                onTap: idle ? null : controller.addWaypoint,
              ),
              Expanded(
                child: FilledButton.icon(
                  onPressed: idle ? null : (paused ? controller.resume : controller.pause),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.ink,
                    foregroundColor: c.onInk,
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                  ),
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
                  label: Text(paused ? t('common.resume') : t('recording.pause')),
                ),
              ),
              Expanded(
                child: FilledButton.icon(
                  onPressed: idle ? null : _finish,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.danger,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.stop, size: 16),
                  label: Text(t('recording.finish')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
