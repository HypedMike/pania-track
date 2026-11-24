import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/providers.dart';
import '../../../core/gps/background_recorder.dart';
import '../../../core/gps/capture_lock.dart';
import '../../../core/gps/gps_service.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/api/tracks.dart' as rust_tracks;
import '../../../core/rust/tracks/simplify.dart' as rust_simplify;
import '../../../core/settings/settings.dart';
import '../../../core/ui/toast.dart';
import '../../../core/weather/open_meteo.dart';
import '../../analysis/data/analysis_api.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../../trail/domain/trail.dart';
import '../data/tour_run_repository.dart';
import '../domain/off_track_monitor.dart';
import '../domain/pace_eta.dart';
import '../domain/tour_guidance.dart';
import '../domain/track_progress.dart';
import '../domain/warning_text.dart';

/// Time between GPS fixes during a tour: quick enough for directions, easy on the battery.
const int _tourIntervalMs = 3000;

/// How often the app collects points from the native service while visible.
const Duration _drainInterval = Duration(seconds: 1);

/// The forecast is fetched again after this long, or when the rest of the trail is far from where it was fetched.
const int _forecastMaxAgeMs = 30 * 60000;
const int _forecastRetryMs = 5 * 60000;
const double _forecastMoveM = 5000;

/// Fixes older than this update the state but no longer raise alerts in the app.
const int _staleFixMs = 30000;

/// A warning that goes away and comes back within this time is not announced again.
const int _announceCooldownMs = 10 * 60000;

/// Points sent to the native off-track guard are thinned to within this many meters of the trail.
const double _guardToleranceM = 5;
const int _guardMaxPoints = 4000;

/// The slope-aware plan needs this many legs of the person's own recordings to be worth using.
const int _minModelLegs = 20;

/// A tour with fewer fixes than this was an accidental start and is not kept.
const int _minRunFixes = 15;

const String _storageKey = 'pania.tour';

enum TourStatus { idle, active }

class TourState {
  const TourState({
    this.status = TourStatus.idle,
    this.trailId,
    this.trail,
    this.startedAt,
    this.targetArrivalMs,
    this.runId,
    this.current,
    this.lastFixMs,
    this.guidance,
    this.liveSpeedMs,
    this.offTrack = false,
    this.warnings = const [],
    this.error,
  });

  final TourStatus status;
  final String? trailId;

  /// The trail being followed. Loaded again from the database after the app was recreated.
  final Trail? trail;
  final int? startedAt;

  /// The time the person wants to arrive by, ms since the epoch.
  final int? targetArrivalMs;

  /// The saved record of this tour, for looking back at it.
  final String? runId;

  /// Latest GPS reading.
  final GpsCoordinate? current;

  /// Time of the latest fix, ms since the epoch.
  final int? lastFixMs;
  final TourGuidance? guidance;

  /// Speed over the last few minutes, m/s (null until there is enough to tell).
  final double? liveSpeedMs;
  final bool offTrack;
  final List<TourWarning> warnings;
  final String? error;

  bool get active => status == TourStatus.active;

  TourState copyWith({
    Trail? trail,
    GpsCoordinate? current,
    int? lastFixMs,
    TourGuidance? guidance,
    double? Function()? liveSpeedMs,
    bool? offTrack,
    List<TourWarning>? warnings,
    String? Function()? error,
  }) => TourState(
    status: status,
    trailId: trailId,
    trail: trail ?? this.trail,
    startedAt: startedAt,
    targetArrivalMs: targetArrivalMs,
    runId: runId,
    current: current ?? this.current,
    lastFixMs: lastFixMs ?? this.lastFixMs,
    guidance: guidance ?? this.guidance,
    liveSpeedMs: liveSpeedMs == null ? this.liveSpeedMs : liveSpeedMs(),
    offTrack: offTrack ?? this.offTrack,
    warnings: warnings ?? this.warnings,
    error: error == null ? this.error : error(),
  );
}

final tourRunRepositoryProvider = Provider<TourRunRepository>((ref) => TourRunRepository(ref.watch(databaseProvider)));

/// Following a trail: where to go next, when you will arrive, what to watch out for, and alerts
/// when you leave the trail. The calculations are in `domain/`; this runs them against the GPS.
class TourController extends Notifier<TourState> {
  Timer? _timer;
  bool _busy = false;
  bool _starting = false;

  // Working state that does not need to render anything.
  TrackIndex? _index;
  List<List<double>> _guardTrack = const [];
  double _plannedMs = 0;

  /// What the person's own pace model expects of each stretch of this trail, when there is one.
  Profile? _paceProfile;

  /// Fixes not yet written to the saved tour.
  List<Fix> _pendingFixes = [];
  List<ProgressSample> _samples = [];
  ProgressSample? _firstSample;
  double? _lastAlongM;
  final OffTrackMonitor _monitor = OffTrackMonitor();
  List<HourForecast> _forecast = const [];
  int _forecastAt = 0;
  LatLon? _forecastFrom;
  bool _forecastFetching = false;
  final Map<WarningKind, int> _announced = {};
  bool _arrivedAnnounced = false;

  TourRunRepository get _runs => ref.read(tourRunRepositoryProvider);
  Settings get _settings => ref.read(settingsProvider);

  @override
  TourState build() {
    ref.onDispose(_stopTimer);
    final saved = ref.read(sharedPreferencesProvider).getString(_storageKey);
    if (saved != null) {
      try {
        final j = jsonDecode(saved) as Map<String, Object?>;
        if (j['status'] == 'active' && j['trailId'] is String) {
          final restored = TourState(
            status: TourStatus.active,
            trailId: j['trailId'] as String,
            startedAt: (j['startedAt'] as num?)?.toInt(),
            targetArrivalMs: (j['targetArrivalMs'] as num?)?.toInt(),
            runId: j['runId'] as String?,
          );
          // The native service may still be recording after the app was recreated: pick it back up.
          Future.microtask(reattach);
          return restored;
        }
      } catch (_) {
        // Unreadable: start fresh.
      }
    }
    return const TourState();
  }

  void _persist() {
    final prefs = ref.read(sharedPreferencesProvider);
    if (state.status == TourStatus.idle) {
      prefs.remove(_storageKey);
    } else {
      prefs.setString(
        _storageKey,
        jsonEncode({
          'status': 'active',
          'trailId': state.trailId,
          'startedAt': state.startedAt,
          'targetArrivalMs': state.targetArrivalMs,
          'runId': state.runId,
        }),
      );
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _resetWorkingState() {
    _index = null;
    _guardTrack = const [];
    _paceProfile = null;
    _pendingFixes = [];
    _samples = [];
    _firstSample = null;
    _lastAlongM = null;
    _monitor.reset();
    _forecast = const [];
    _forecastAt = 0;
    _forecastFrom = null;
    _announced.clear();
    _arrivedAnnounced = false;
  }

  void _setupTrail(Trail trail) {
    _resetWorkingState();
    _index = buildTrackIndex([for (final c in trail.coordinates) latLonOf(c)]);
    _plannedMs = plannedSpeedMs(trail.coordinates, trail.activity);
  }

  /// The trail as the native service needs it: thinned out, as [latitude, longitude] pairs.
  Future<List<List<double>>> _prepareGuardTrack(Trail trail) async {
    List<List<double>> pairs;
    try {
      final simplified = await rust_tracks.simplifyTrack(
        points: [
          for (final c in trail.coordinates)
            rust_simplify.Point(latitude: c.latitude, longitude: c.longitude, altitude: c.altitude),
        ],
        options: const rust_simplify.Options(toleranceM: _guardToleranceM, altitudeToleranceM: 4, minStepM: 2),
      );
      pairs = [
        for (final i in simplified.kept)
          [trail.coordinates[i.toInt()].latitude, trail.coordinates[i.toInt()].longitude],
      ];
    } catch (_) {
      pairs = [
        for (final c in trail.coordinates) [c.latitude, c.longitude],
      ];
    }
    if (pairs.length > _guardMaxPoints) {
      final step = (pairs.length / _guardMaxPoints).ceil();
      pairs = [
        for (var i = 0; i < pairs.length; i++)
          if (i % step == 0 || i == pairs.length - 1) pairs[i],
      ];
    }
    return pairs;
  }

  OffTrackGuard _offTrackGuard() => OffTrackGuard(
    thresholdM: _settings.offTrackM.toDouble(),
    track: _guardTrack,
    title: I18n.t('tour.alert.title'),
    text: I18n.t('tour.alert.text', {'m': '{m}'}),
  );

  /// The slope-aware plan for a trail: how long each stretch should take for this person, from their
  /// own recordings of the same activity. `null` when there is too little to go on; the tour then
  /// uses the constant planned speed.
  Future<Profile?> _buildPaceProfile(Trail trail) async {
    try {
      final all = await ref.read(trailRepositoryProvider).getAll();
      final recorded = [
        for (final t in all)
          if (t.activity == trail.activity && t.coordinates.any((c) => c.timestamp != null))
            TrailForAnalysis(id: t.id, activity: t.activity, coordinates: t.coordinates),
      ];
      final model = await AnalysisApi.paceModel(recorded, trail.activity);
      if (model.legsUsed.toInt() < _minModelLegs) return null;
      return await AnalysisApi.paceProfile(trail.coordinates, model);
    } catch (_) {
      return null;
    }
  }

  /// Writes the fixes collected since the last time to the saved tour. Failures are not worth interrupting a tour for.
  void _flushRunFixes(String? runId) {
    if (runId == null || _pendingFixes.isEmpty) return;
    final batch = _pendingFixes;
    _pendingFixes = [];
    _runs.appendFixes(runId, batch).catchError((Object _) {});
  }

  LiveInfo _liveInfo(Trail? trail) => LiveInfo(
    mode: 'tour',
    title: (trail?.name.isNotEmpty ?? false) ? trail!.name : I18n.t('tour.title'),
    labels: LiveInfo.currentLabels(),
  );

  /// Takes in the GPS fixes in order, then recomputes what the person sees.
  void _ingest(List<GpsCoordinate> fixes) {
    final trail = state.trail;
    final index = _index;
    if (trail == null || index == null || fixes.isEmpty) return;
    final threshold = _settings.offTrackM.toDouble();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final fix in fixes) {
      final time = fix.timestamp?.millisecondsSinceEpoch ?? now;
      final projection = projectOnTrack(index, latLonOf(fix), _lastAlongM);
      _lastAlongM = projection.alongM;
      // Progress while off the trail says nothing about the pace along it.
      if (projection.offTrackM <= threshold) {
        final sample = ProgressSample(time, projection.alongM);
        _firstSample ??= sample;
        _samples.add(sample);
      }
      final verdict = _monitor.onFix(projection.offTrackM, fix.accuracy, threshold, time);
      // Fixes collected after the screen was off are old news: the notification already went out.
      if (now - time < _staleFixMs) _handleOffTrack(verdict, projection.offTrackM);
    }
    final cutoff = now - 10 * 60000;
    if (_samples.isNotEmpty && _samples.first.time < cutoff) {
      _samples = _samples.where((s) => s.time >= cutoff).toList();
    }
    _pendingFixes.addAll(toFixes(fixes));
    _flushRunFixes(state.runId);
    final last = fixes.last;
    state = state.copyWith(current: last, lastFixMs: last.timestamp?.millisecondsSinceEpoch ?? now, error: () => null);
    _evaluate();
  }

  /// What the person is told when they stray. On Android the service shows the notification itself.
  void _handleOffTrack(OffTrackVerdict? verdict, double offTrackM) {
    if (verdict == OffTrackVerdict.alert || verdict == OffTrackVerdict.remind) {
      final text = I18n.t('tour.alert.text', {'m': (offTrackM / 5).round() * 5});
      AppToast.show(I18n.t('tour.alert.title'), description: text, level: ToastLevel.warning);
      HapticFeedback.vibrate();
    } else if (verdict == OffTrackVerdict.back) {
      AppToast.dismiss();
      AppToast.show(I18n.t('tour.backOnTrack'), level: ToastLevel.success);
    }
  }

  /// Recomputes guidance, arrival time and warnings from the last fix and the clock.
  void _evaluate() {
    final trail = state.trail;
    final index = _index;
    final current = state.current;
    final lastFixMs = state.lastFixMs;
    if (trail == null || index == null || current == null || lastFixMs == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final live = recentSpeedMs(_samples, now);
    var speedMs = chooseSpeedMs(
      live,
      averageSpeedMs(_firstSample, _samples.isEmpty ? null : _samples.last),
      _plannedMs,
    );
    // With the person's own pace model, the rest of the trail is timed stretch by stretch
    // (a climb ahead takes longer), scaled by how today is going against the model.
    final profile = _paceProfile;
    if (profile != null && _firstSample != null && _lastAlongM != null) {
      final fromModel = profileSpeedMs(profile, _lastAlongM!, _firstSample!.alongM, (now - _firstSample!.time) / 1000);
      if (fromModel != null) speedMs = fromModel;
    }
    final guidance = computeGuidance(
      GuidanceInput(
        index: index,
        waypoints: trail.waypoints,
        position: current,
        previousAlongM: _lastAlongM,
        speedMs: speedMs,
        nowMs: now,
        offTrackThresholdM: _settings.offTrackM.toDouble(),
      ),
    );
    final warnings = computeWarnings(
      WarningInput(
        guidance: guidance,
        offTrack: _monitor.offTrack,
        nowMs: now,
        lastFixMs: lastFixMs,
        targetArrivalMs: state.targetArrivalMs,
        position: current,
        destination: trail.coordinates.last,
        forecast: _forecast,
      ),
    );
    state = state.copyWith(
      guidance: guidance,
      liveSpeedMs: () => live,
      offTrack: _monitor.offTrack,
      warnings: warnings,
    );
    _announce(warnings, now);
    if (guidance.arrived && !_arrivedAnnounced) {
      _arrivedAnnounced = true;
      AppToast.show(I18n.t('tour.arrived'), level: ToastLevel.success);
    }
    _refreshForecast(guidance, now);
  }

  /// Shows new warnings once (off-track is handled by the monitor).
  void _announce(List<TourWarning> warnings, int now) {
    for (final w in warnings) {
      if (w.kind == WarningKind.offTrack || w.kind == WarningKind.noGps) continue;
      final last = _announced[w.kind];
      if (last != null && now - last < _announceCooldownMs) continue;
      _announced[w.kind] = now;
      AppToast.show(
        warningText(w),
        level: w.level == WarningLevel.danger ? ToastLevel.error : ToastLevel.warning,
        duration: const Duration(seconds: 10),
      );
    }
  }

  /// The forecast around the middle of what is left of the trail, refreshed as the person moves.
  Future<void> _refreshForecast(TourGuidance guidance, int now) async {
    final index = _index;
    if (_forecastFetching || index == null || guidance.arrived) return;
    final middle = pointAtDistance(index, guidance.alongM + guidance.remainingM / 2);
    final moved = _forecastFrom == null ? double.infinity : _approxDistanceM(_forecastFrom!, middle);
    if (now - _forecastAt < _forecastMaxAgeMs && moved < _forecastMoveM) return;
    _forecastFetching = true;
    try {
      _forecast = await fetchForecast(middle.latitude, middle.longitude);
      _forecastFrom = middle;
      _forecastAt = now;
    } catch (_) {
      // Offline in the mountains is normal; keep the old forecast and try again soon.
      _forecastAt = now - _forecastMaxAgeMs + _forecastRetryMs;
    } finally {
      _forecastFetching = false;
    }
    if (state.active) _evaluate();
  }

  /// Collects what the native service buffered.
  Future<void> _drainNative() async {
    if (_busy) return;
    _busy = true;
    try {
      final taken = await BackgroundRecorder.takePoints();
      if (taken.points.isNotEmpty) {
        _ingest(taken.points);
      } else {
        _evaluate();
      }
      if (taken.error != null) state = state.copyWith(error: () => taken.error);
      // The service is gone while the tour is on (e.g. the system stopped it): start it again.
      if (!taken.running && state.active && taken.error == null) {
        await BackgroundRecorder.start(_tourIntervalMs, guard: _offTrackGuard(), live: _liveInfo(state.trail));
      }
    } catch (e) {
      state = state.copyWith(error: () => '$e');
    } finally {
      _busy = false;
    }
  }

  /// Foreground-only fallback used where the native service is unavailable.
  Future<void> _pollPosition() async {
    if (_busy || !state.active) return;
    _busy = true;
    try {
      _ingest([await GpsService.currentPosition()]);
    } catch (e) {
      state = state.copyWith(error: () => '$e');
      _evaluate();
    } finally {
      _busy = false;
    }
  }

  Future<void> _beginCapture() async {
    if (BackgroundRecorder.supported) {
      await BackgroundRecorder.start(_tourIntervalMs, guard: _offTrackGuard(), live: _liveInfo(state.trail));
    }
    _stopTimer();
    final tick = BackgroundRecorder.supported ? _drainNative : _pollPosition;
    tick();
    _timer = Timer.periodic(
      BackgroundRecorder.supported ? _drainInterval : const Duration(milliseconds: _tourIntervalMs),
      (_) => tick(),
    );
  }

  Future<void> start(Trail trail, int? targetArrivalMs) async {
    if (state.status != TourStatus.idle || _starting) return;
    if (trail.coordinates.length < 2) return;
    if (!CaptureLock.claim(CaptureOwner.tour)) {
      state = state.copyWith(error: () => I18n.t('error.recordingActive'));
      return;
    }
    _starting = true;
    state = state.copyWith(error: () => null);
    try {
      await GpsService.ensurePermission();
      // Drop anything left in the native buffer by an earlier, abandoned session.
      if (BackgroundRecorder.supported) await BackgroundRecorder.takePoints().then((_) {}, onError: (_) {});
      _setupTrail(trail);
      _guardTrack = await _prepareGuardTrack(trail);
      _paceProfile = await _buildPaceProfile(trail);
      // The plan made now is kept with the tour, so it can be compared with what happened.
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final run = TourRun(
        id: const Uuid().v4(),
        trailId: trail.id,
        startedAt: startedAt,
        plannedSpeedMs: _plannedMs,
        planProfile: _paceProfile,
        targetArrivalMs: targetArrivalMs,
      );
      final saved = await _runs.create(run).then((_) => true, onError: (_) => false);
      state = TourState(
        status: TourStatus.active,
        trailId: trail.id,
        trail: trail,
        startedAt: startedAt,
        targetArrivalMs: targetArrivalMs,
        runId: saved ? run.id : null,
      );
      _persist();
      await _beginCapture();
    } catch (e) {
      _stopTimer();
      _resetWorkingState();
      CaptureLock.release(CaptureOwner.tour);
      state = TourState(error: '$e');
      _persist();
    } finally {
      _starting = false;
    }
  }

  /// Ends the tour and stops GPS capture. Returns the id of the saved tour, or null when none was kept.
  Future<String?> stop() async {
    final runId = state.runId;
    final arrived = state.guidance?.arrived == true;
    _stopTimer();
    CaptureLock.release(CaptureOwner.tour);
    // Close the saved tour: a few fixes are an accidental start and are not worth keeping.
    String? keptRunId;
    if (runId != null) {
      try {
        final batch = _pendingFixes;
        _pendingFixes = [];
        await _runs.appendFixes(runId, batch);
        await _runs.end(runId, finished: arrived);
        if (await _runs.countFixes(runId) >= _minRunFixes) {
          keptRunId = runId;
        } else {
          await _runs.remove(runId);
        }
      } catch (_) {
        // Not being able to save the record must not keep the tour from ending.
      }
    }
    _resetWorkingState();
    AppToast.dismiss();
    state = const TourState();
    _persist();
    if (BackgroundRecorder.supported) {
      await BackgroundRecorder.stop().catchError((_) {});
      await BackgroundRecorder.takePoints().then((_) {}, onError: (_) {});
    }
    return keptRunId;
  }

  /// Picks a restored tour back up after the app was recreated.
  Future<void> reattach() async {
    final trailId = state.trailId;
    if (trailId == null) return;
    CaptureLock.claim(CaptureOwner.tour);
    try {
      final trail = await ref.read(trailRepositoryProvider).getById(trailId);
      if (trail == null || trail.coordinates.length < 2) {
        await stop();
        return;
      }
      _setupTrail(trail);
      _guardTrack = await _prepareGuardTrack(trail);
      // The plan made at the start stays the plan, so the arrival time does not jump.
      final runId = state.runId;
      _paceProfile = runId == null ? null : (await _runs.get(runId))?.planProfile;
      state = state.copyWith(trail: trail);
      await _beginCapture();
    } catch (e) {
      state = state.copyWith(error: () => '$e');
    }
  }
}

/// Rough distance in meters, fine for "has the person moved a few km".
double _approxDistanceM(LatLon a, LatLon b) {
  final dy = (b.latitude - a.latitude) * 111195;
  final dx = (b.longitude - a.longitude) * 111195 * math.cos(a.latitude * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

final tourProvider = NotifierProvider<TourController, TourState>(TourController.new);
