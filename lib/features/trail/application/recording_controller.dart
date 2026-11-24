import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/gps/background_recorder.dart';
import '../../../core/gps/capture_lock.dart';
import '../../../core/gps/gps_service.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings.dart';
import '../domain/gps_coordinate.dart';

/// How often the app collects points from the native service while visible.
const Duration _drainInterval = Duration(seconds: 1);
const String _storageKey = 'pania.recording';

enum RecordingStatus { idle, recording, paused }

class RecordingState {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.points = const [],
    this.waypoints = const [],
    this.startedAt,
    this.accumulatedMs = 0,
    this.resumedAt,
    this.current,
    this.error,
  });

  final RecordingStatus status;
  final List<GpsCoordinate> points;
  final List<Waypoint> waypoints;

  /// Wall-clock time the recording began, in ms.
  final int? startedAt;

  /// Active time accumulated before the current run, in ms (pauses excluded).
  final int accumulatedMs;

  /// When the current run started, or null while paused.
  final int? resumedAt;

  /// Latest GPS reading, whether or not it was added to the track.
  final GpsCoordinate? current;
  final String? error;

  /// Active recording time in ms, excluding pauses.
  int get elapsedMs => accumulatedMs + (resumedAt == null ? 0 : DateTime.now().millisecondsSinceEpoch - resumedAt!);

  RecordingState copyWith({
    RecordingStatus? status,
    List<GpsCoordinate>? points,
    List<Waypoint>? waypoints,
    int? accumulatedMs,
    int? Function()? resumedAt,
    GpsCoordinate? current,
    String? Function()? error,
  }) => RecordingState(
    status: status ?? this.status,
    points: points ?? this.points,
    waypoints: waypoints ?? this.waypoints,
    startedAt: startedAt,
    accumulatedMs: accumulatedMs ?? this.accumulatedMs,
    resumedAt: resumedAt == null ? this.resumedAt : resumedAt(),
    current: current ?? this.current,
    error: error == null ? this.error : error(),
  );

  Map<String, Object?> toJson() => {
    'status': status.name,
    'points': [for (final p in points) p.toJson()],
    'waypoints': [for (final w in waypoints) w.toJson()],
    'startedAt': startedAt,
    'accumulatedMs': accumulatedMs,
    'resumedAt': resumedAt,
  };

  static RecordingState? fromJson(String text) {
    try {
      final j = jsonDecode(text) as Map<String, Object?>;
      return RecordingState(
        status: RecordingStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => RecordingStatus.idle),
        points: [for (final p in (j['points'] as List)) GpsCoordinate.fromJson((p as Map).cast())],
        waypoints: [for (final w in (j['waypoints'] as List)) Waypoint.fromJson((w as Map).cast())],
        startedAt: (j['startedAt'] as num?)?.toInt(),
        accumulatedMs: (j['accumulatedMs'] as num?)?.toInt() ?? 0,
        resumedAt: (j['resumedAt'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A track point keeps its GPS accuracy (rounded), so the recording's quality can be judged later.
GpsCoordinate _toTrackPoint(GpsCoordinate fix) =>
    fix.accuracy == null ? fix : fix.copyWith(accuracy: (fix.accuracy! * 10).round() / 10);

class RecordingController extends Notifier<RecordingState> {
  Timer? _timer;
  bool _busy = false;
  bool _starting = false;

  @override
  RecordingState build() {
    ref.onDispose(_stopTimer);
    final saved = ref.read(sharedPreferencesProvider).getString(_storageKey);
    final restored = saved == null ? null : RecordingState.fromJson(saved);
    if (restored != null && restored.status != RecordingStatus.idle) {
      // The native service may still be recording after the app was recreated: pick it back up.
      Future.microtask(reattach);
      return restored;
    }
    return const RecordingState();
  }

  void _set(RecordingState next) {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    if (next.status == RecordingStatus.idle) {
      prefs.remove(_storageKey);
    } else {
      prefs.setString(_storageKey, jsonEncode(next.toJson()));
    }
  }

  int get _intervalMs => ref.read(settingsProvider).recordIntervalMs;

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Live stats context for the native notification and widget; a resumed recording carries on from what it has.
  LiveInfo _liveInfo() {
    final stats = computeStats(state.points);
    return LiveInfo(
      mode: 'recording',
      title: I18n.t('live.recording'),
      labels: LiveInfo.currentLabels(),
      baseDistanceM: stats.distanceM,
      baseAscentM: stats.elevationGainM ?? 0,
      baseElapsedMs: state.elapsedMs,
    );
  }

  /// Adds fixes to the track; fixes that arrive while paused only update the live position.
  void _addFixes(List<GpsCoordinate> fixes, {required bool keep}) {
    if (fixes.isEmpty) return;
    _set(state.copyWith(current: fixes.last, points: keep ? [...state.points, ...fixes.map(_toTrackPoint)] : null));
  }

  /// Collects what the native service buffered. Points recorded before a pause are kept.
  Future<void> _drainNative() async {
    if (_busy) return;
    _busy = true;
    try {
      final taken = await BackgroundRecorder.takePoints();
      _addFixes(taken.points, keep: state.status != RecordingStatus.idle);
      if (taken.error != null) {
        _set(state.copyWith(error: () => taken.error));
      } else if (taken.points.isNotEmpty) {
        _set(state.copyWith(error: () => null));
      }
      // The service is gone while we think we're recording (e.g. the system stopped it).
      if (!taken.running && state.status == RecordingStatus.recording && taken.error == null) {
        await BackgroundRecorder.start(_intervalMs, live: _liveInfo());
      }
    } catch (e) {
      _set(state.copyWith(error: () => '$e'));
    } finally {
      _busy = false;
    }
  }

  /// Foreground-only fallback used where the native service is unavailable.
  Future<void> _pollPosition() async {
    if (_busy || state.status != RecordingStatus.recording) return;
    _busy = true;
    try {
      final fix = await GpsService.currentPosition();
      _addFixes([fix], keep: state.status == RecordingStatus.recording);
      _set(state.copyWith(error: () => null));
    } catch (e) {
      _set(state.copyWith(error: () => '$e'));
    } finally {
      _busy = false;
    }
  }

  void _startTimer() {
    _stopTimer();
    final tick = BackgroundRecorder.supported ? _drainNative : _pollPosition;
    tick();
    _timer = Timer.periodic(
      BackgroundRecorder.supported ? _drainInterval : Duration(milliseconds: _intervalMs),
      (_) => tick(),
    );
  }

  Future<void> _beginCapture() async {
    if (BackgroundRecorder.supported) await BackgroundRecorder.start(_intervalMs, live: _liveInfo());
    _startTimer();
  }

  Future<void> _endCapture() async {
    _stopTimer();
    if (!BackgroundRecorder.supported) return;
    await BackgroundRecorder.stop().catchError((_) {});
    await _drainNative();
  }

  Future<void> start() async {
    if (state.status != RecordingStatus.idle || _starting) return;
    if (!CaptureLock.claim(CaptureOwner.recording)) {
      state = state.copyWith(error: () => I18n.t('error.tourActive'));
      return;
    }
    _starting = true;
    state = state.copyWith(error: () => null);
    try {
      await GpsService.ensurePermission();
      // Drop anything left in the native buffer by an earlier, abandoned session.
      if (BackgroundRecorder.supported) await BackgroundRecorder.takePoints().then((_) {}, onError: (_) {});
      final now = DateTime.now().millisecondsSinceEpoch;
      _set(RecordingState(status: RecordingStatus.recording, startedAt: now, resumedAt: now));
      await _beginCapture();
    } catch (e) {
      _stopTimer();
      CaptureLock.release(CaptureOwner.recording);
      _set(RecordingState(error: '$e'));
    } finally {
      _starting = false;
    }
  }

  Future<void> pause() async {
    if (state.status != RecordingStatus.recording) return;
    _set(state.copyWith(status: RecordingStatus.paused, accumulatedMs: state.elapsedMs, resumedAt: () => null));
    await _endCapture();
  }

  Future<void> resume() async {
    if (state.status != RecordingStatus.paused) return;
    _set(
      state.copyWith(
        status: RecordingStatus.recording,
        resumedAt: () => DateTime.now().millisecondsSinceEpoch,
        error: () => null,
      ),
    );
    try {
      await _beginCapture();
    } catch (e) {
      _set(state.copyWith(error: () => '$e'));
    }
  }

  Future<void> addWaypoint() async {
    try {
      final point = (state.current ?? await GpsService.currentPosition()).copyWith(dropAccuracy: true);
      _set(
        state.copyWith(waypoints: [...state.waypoints, Waypoint.at(point, 'Waypoint ${state.waypoints.length + 1}')]),
      );
    } catch (e) {
      _set(state.copyWith(error: () => '$e'));
    }
  }

  /// Clears everything and stops capturing.
  Future<void> discard() async {
    _stopTimer();
    CaptureLock.release(CaptureOwner.recording);
    _set(const RecordingState());
    if (BackgroundRecorder.supported) {
      await BackgroundRecorder.stop().catchError((_) {});
      await BackgroundRecorder.takePoints().then((_) {}, onError: (_) {});
    }
  }

  /// Picks a restored session back up after the app was recreated.
  Future<void> reattach() async {
    CaptureLock.claim(CaptureOwner.recording);
    try {
      if (state.status == RecordingStatus.recording) {
        await _beginCapture();
      } else if (state.status == RecordingStatus.paused && BackgroundRecorder.supported) {
        // Collect points the service recorded before it was paused.
        await _drainNative();
      }
    } catch (e) {
      _set(state.copyWith(error: () => '$e'));
    }
  }
}

final recordingProvider = NotifierProvider<RecordingController, RecordingState>(RecordingController.new);
