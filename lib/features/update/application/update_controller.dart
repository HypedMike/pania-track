import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pania_native/pania_native.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_info.dart';
import '../../../core/rust/api/updater.dart' as rust;
import '../../../core/rust/updater/progress.dart';
import '../../../core/settings/settings.dart';
import '../domain/latest_release.dart';

enum UpdatePhase { idle, needsPermission, downloading, failed }

class UpdateState {
  const UpdateState({
    this.release,
    this.currentVersion = '',
    this.phase = UpdatePhase.idle,
    this.error = '',
    this.progress,
  });

  /// A newer release, once one was found.
  final LatestRelease? release;
  final String currentVersion;
  final UpdatePhase phase;
  final String error;
  final Progress? progress;

  UpdateState copyWith({
    LatestRelease? release,
    UpdatePhase? phase,
    String? error,
    Progress? Function()? progress,
    bool clearRelease = false,
  }) => UpdateState(
    release: clearRelease ? null : (release ?? this.release),
    currentVersion: currentVersion,
    phase: phase ?? this.phase,
    error: error ?? this.error,
    progress: progress == null ? this.progress : progress(),
  );
}

/// Checks GitHub once per launch (if enabled in settings) and offers the update. On Android the
/// APK is downloaded by the Rust core and handed to the system installer.
class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState build() {
    Future.microtask(_check);
    return const UpdateState();
  }

  Future<void> _check() async {
    if (latestReleaseUrl.isEmpty || !ref.read(settingsProvider).checkForUpdates) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final latest = await fetchLatestRelease(latestReleaseUrl);
      if (isNewerVersion(latest.version, info.version)) {
        state = UpdateState(release: latest, currentVersion: info.version);
      }
    } catch (_) {
      // Offline or rate limited: try again next launch.
    }
  }

  void dismiss() => state = UpdateState(currentVersion: state.currentVersion);

  /// Downloads the APK and opens Android's installer; asks for the install permission first if needed.
  Future<void> install() async {
    final release = state.release;
    if (release == null) return;
    if (!PaniaNative.supported) {
      await openExternal(release.downloadUrl);
      dismiss();
      return;
    }
    try {
      if (!await PaniaNative.canInstall()) {
        state = state.copyWith(phase: UpdatePhase.needsPermission);
        return;
      }
      state = state.copyWith(phase: UpdatePhase.downloading, progress: () => null);
      final dir = await PaniaNative.prepareUpdateDir();
      await for (final progress in rust.downloadUpdate(url: release.downloadUrl, dir: dir)) {
        state = state.copyWith(progress: () => progress);
      }
      await PaniaNative.installApk(p.join(dir, rust.updateFileName()));
      // The system installer is on screen now; it takes it from here.
      dismiss();
    } catch (e) {
      state = state.copyWith(phase: UpdatePhase.failed, error: '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> openInstallSettings() async {
    try {
      await PaniaNative.openInstallSettings();
    } catch (_) {
      state = state.copyWith(phase: UpdatePhase.failed);
    }
  }

  Future<void> openInBrowser() async {
    final release = state.release;
    if (release != null) await openExternal(release.downloadUrl);
    dismiss();
  }
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
