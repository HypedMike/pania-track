/// Pania's Android side, over one method channel (`pania/native`).
///
/// - the GPS recording foreground service, its live-stats notification and widget;
/// - Keystore-backed secret storage (only the Rust core asks for secrets);
/// - the Android half of in-app updates (the download is done in Rust).
///
/// Everything reports "unsupported" off Android, and the app then falls back to polling the
/// position itself, to a development-only secret file, and to opening the download in a browser.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('pania/native');

/// A GPS point collected by the native service.
class NativePoint {
  const NativePoint({
    required this.latitude,
    required this.longitude,
    required this.timeMs,
    this.altitude,
    this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? altitude;
  final double? accuracy;

  /// Milliseconds since the epoch.
  final int timeMs;

  factory NativePoint.fromMap(Map<Object?, Object?> map) => NativePoint(
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
    altitude: (map['altitude'] as num?)?.toDouble(),
    accuracy: (map['accuracy'] as num?)?.toDouble(),
    timeMs: (map['time'] as num).toInt(),
  );
}

/// What [PaniaNative.takePoints] returns.
class TakeResult {
  const TakeResult({required this.points, required this.running, this.error});

  /// Points recorded since the previous call; they are removed from the native buffer.
  final List<NativePoint> points;

  /// Whether the recording service is running.
  final bool running;

  /// Last error reported by the service (e.g. location turned off), if any.
  final String? error;
}

class LiveUpdateStatus {
  const LiveUpdateStatus({required this.supported, required this.enabled});

  /// Android 16 or newer, where Live Updates exist.
  final bool supported;

  /// Whether the person has Live Updates turned on for the app.
  final bool enabled;

  static const none = LiveUpdateStatus(supported: false, enabled: false);
}

/// The Android-only features. Static: there is one native side.
abstract final class PaniaNative {
  /// Only Android has the native service.
  static bool get supported => Platform.isAndroid;

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) =>
      _channel.invokeMethod<T>(method, args);

  // ---- Recorder ---------------------------------------------------------------------------

  /// Asks for the notification permission the status notification needs (Android 13+).
  /// Recording works without it; the person just would not see that it runs.
  static Future<bool> requestNotificationPermission() async =>
      supported && (await _call<bool>('recorder.requestPermissions') ?? false);

  /// Starts the foreground service. With [guardJson] it also watches the fixes against a trail and
  /// raises a notification by itself when the person strays (see `OffTrackGuard.kt`); [liveJson]
  /// configures the live stats (see `LiveStats.kt`).
  static Future<void> startRecorder({
    required int intervalMs,
    String? guardJson,
    String? liveJson,
  }) => _call<void>('recorder.start', {
    'intervalMs': intervalMs,
    'guardJson': guardJson,
    'liveJson': liveJson,
  });

  static Future<void> stopRecorder() => _call<void>('recorder.stop');

  /// Returns, and removes from the native buffer, the points recorded since the last call.
  static Future<TakeResult> takePoints() async {
    final raw = await _call<Map<Object?, Object?>>('recorder.takePoints');
    final points = (raw?['points'] as List? ?? const [])
        .map((p) => NativePoint.fromMap(p as Map<Object?, Object?>))
        .toList();
    return TakeResult(
      points: points,
      running: raw?['running'] == true,
      error: raw?['error'] as String?,
    );
  }

  /// Whether Live Updates exist on this phone (Android 16+) and are turned on for the app.
  static Future<LiveUpdateStatus> liveUpdateStatus() async {
    if (!supported) return LiveUpdateStatus.none;
    try {
      final raw = await _call<Map<Object?, Object?>>(
        'recorder.liveUpdateStatus',
      );
      return LiveUpdateStatus(
        supported: raw?['supported'] == true,
        enabled: raw?['enabled'] == true,
      );
    } on PlatformException {
      return LiveUpdateStatus.none;
    }
  }

  /// Opens the system screen where the person can turn Live Updates on.
  static Future<void> openLiveUpdateSettings() =>
      _call<void>('recorder.openLiveUpdateSettings');

  // ---- Secrets ----------------------------------------------------------------------------

  static Future<String?> getSecret(String key) =>
      _call<String>('secrets.get', {'key': key});

  static Future<void> setSecret(String key, String value) =>
      _call<void>('secrets.set', {'key': key, 'value': value});

  static Future<void> deleteSecret(String key) =>
      _call<void>('secrets.delete', {'key': key});

  // ---- Installer --------------------------------------------------------------------------

  /// Whether the person has allowed this app to install packages ("install unknown apps").
  static Future<bool> canInstall() async =>
      (await _call<bool>('installer.canInstall')) ?? false;

  /// Opens the system screen where the person allows this app to install packages.
  static Future<void> openInstallSettings() =>
      _call<void>('installer.openSettings');

  /// The app-private folder the installer may read APKs from; emptied first.
  static Future<String> prepareUpdateDir() async =>
      (await _call<String>('installer.updateDir'))!;

  /// Opens the system installer on a downloaded APK.
  static Future<void> installApk(String path) =>
      _call<void>('installer.install', {'path': path});
}
