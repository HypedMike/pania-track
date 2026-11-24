import 'dart:convert';

import 'package:pania_native/pania_native.dart';

import '../../features/trail/domain/gps_coordinate.dart';
import '../i18n/i18n.dart';

/// What the native service needs to alert on its own when the person leaves a trail.
class OffTrackGuard {
  const OffTrackGuard({required this.thresholdM, required this.track, required this.title, required this.text});

  /// Farther than this from the trail counts as off it.
  final double thresholdM;

  /// The trail as [latitude, longitude] pairs.
  final List<List<double>> track;

  /// Notification texts, already translated; `{m}` in [text] becomes the distance.
  final String title;
  final String text;

  Map<String, Object?> toJson() => {'thresholdM': thresholdM, 'track': track, 'title': title, 'text': text};
}

/// What the native side needs to show live stats in the status notification, the Android 16 Live
/// Update and the widget. It computes the numbers itself from the GPS fixes, so they keep updating
/// with the screen off.
class LiveInfo {
  const LiveInfo({
    required this.mode,
    required this.title,
    required this.labels,
    this.baseDistanceM = 0,
    this.baseAscentM = 0,
    this.baseElapsedMs = 0,
  });

  /// `recording` or `tour`.
  final String mode;

  /// Notification and widget title: "Recording trail" or the name of the trail being followed.
  final String title;

  /// Translated captions: distance, time, climb, left, arrival, done.
  final Map<String, String> labels;

  /// What a resumed recording already has, so the numbers carry on instead of restarting.
  final double baseDistanceM;
  final double baseAscentM;
  final int baseElapsedMs;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'title': title,
    'labels': labels,
    'baseDistanceM': baseDistanceM,
    'baseAscentM': baseAscentM,
    'baseElapsedMs': baseElapsedMs,
  };

  /// The captions shown by the native status notification and widget, in the app's language.
  static Map<String, String> currentLabels() => {
    'distance': I18n.t('common.distance'),
    'time': I18n.t('common.duration'),
    'climb': I18n.t('live.climb'),
    'left': I18n.t('tour.remaining'),
    'arrival': I18n.t('tour.eta'),
    'done': I18n.t('live.done'),
  };
}

class TakenPoints {
  const TakenPoints({required this.points, required this.running, this.error});
  final List<GpsCoordinate> points;
  final bool running;
  final String? error;
}

/// The native recorder: an Android foreground service that keeps collecting GPS points with the
/// screen off. Points are buffered natively until [takePoints] collects them.
abstract final class BackgroundRecorder {
  /// Only Android has the native service; elsewhere the app polls the position itself.
  static bool get supported => PaniaNative.supported;

  /// Starts the service. With [guard] it also watches the fixes against a trail and raises a
  /// notification by itself when the person strays, which keeps working with the screen off.
  static Future<void> start(int intervalMs, {OffTrackGuard? guard, LiveInfo? live}) async {
    // The notification permission only affects whether the status notification is visible.
    await PaniaNative.requestNotificationPermission().catchError((_) => false);
    await PaniaNative.startRecorder(
      intervalMs: intervalMs,
      guardJson: guard == null ? null : jsonEncode(guard.toJson()),
      liveJson: live == null ? null : jsonEncode(live.toJson()),
    );
  }

  static Future<void> stop() => PaniaNative.stopRecorder();

  /// Returns, and removes from the native buffer, the points recorded since the last call.
  static Future<TakenPoints> takePoints() async {
    final result = await PaniaNative.takePoints();
    return TakenPoints(
      running: result.running,
      error: result.error,
      points: [
        for (final p in result.points)
          GpsCoordinate(
            latitude: p.latitude,
            longitude: p.longitude,
            altitude: p.altitude,
            accuracy: p.accuracy,
            timestamp: DateTime.fromMillisecondsSinceEpoch(p.timeMs, isUtc: true),
          ),
      ],
    );
  }

  static Future<LiveUpdateStatus> liveUpdateStatus() => PaniaNative.liveUpdateStatus();
  static Future<void> openLiveUpdateSettings() => PaniaNative.openLiveUpdateSettings();
}
