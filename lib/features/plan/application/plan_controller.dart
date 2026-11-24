import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/ui/toast.dart';
import '../../trail/domain/gps_coordinate.dart';
import '../domain/route_planner.dart';

class Checkpoint {
  const Checkpoint({required this.id, required this.latitude, required this.longitude, this.name});

  final String id;
  final double latitude;
  final double longitude;

  /// Set by the user (or from a searched place); otherwise a default name is shown.
  final String? name;

  GpsCoordinate get coordinate => GpsCoordinate(latitude: latitude, longitude: longitude);

  Checkpoint copyWith({double? latitude, double? longitude, String? Function()? name}) => Checkpoint(
    id: id,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    name: name == null ? this.name : name(),
  );
}

/// The checkpoint's own name, or "Start" / "Checkpoint 3" by position.
String checkpointName(Checkpoint c, int index, TFunction t) {
  final name = c.name;
  if (name != null && name.isNotEmpty) return name;
  return index == 0 ? t('plan.start') : t('plan.checkpointN', {'n': index + 1});
}

String checkpointLabel(int index) => index == 0 ? 'S' : '${index + 1}';

const int _maxNameLength = 60;

enum PlanStatus { idle, loading, ready, error }

class PlanState {
  const PlanState({
    this.checkpoints = const [],
    this.loop = true,
    this.avoidRoads = true,
    this.status = PlanStatus.idle,
    this.error,
    this.variants = const [],
    this.selectedId,
    this.cursor,
  });

  final List<Checkpoint> checkpoints;

  /// Return to the first checkpoint at the end.
  final bool loop;
  final bool avoidRoads;
  final PlanStatus status;
  final String? error;

  /// Variants for the current checkpoints; the first is the recommended one.
  final List<RouteVariant> variants;
  final String? selectedId;

  /// Point picked on the steepness profile, shown as a dot on the map.
  final GpsCoordinate? cursor;

  RouteVariant? get selected => variants.where((v) => v.id == selectedId).firstOrNull ?? variants.firstOrNull;

  PlanState copyWith({
    List<Checkpoint>? checkpoints,
    bool? loop,
    bool? avoidRoads,
    PlanStatus? status,
    String? Function()? error,
    List<RouteVariant>? variants,
    String? Function()? selectedId,
    GpsCoordinate? Function()? cursor,
  }) => PlanState(
    checkpoints: checkpoints ?? this.checkpoints,
    loop: loop ?? this.loop,
    avoidRoads: avoidRoads ?? this.avoidRoads,
    status: status ?? this.status,
    error: error == null ? this.error : error(),
    variants: variants ?? this.variants,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    cursor: cursor == null ? this.cursor : cursor(),
  );
}

/// Waits for the user to stop tapping/dragging before asking the router.
const Duration _debounce = Duration(milliseconds: 500);

class PlanController extends Notifier<PlanState> {
  Timer? _timer;
  int _generation = 0;

  @override
  PlanState build() {
    ref.onDispose(() => _timer?.cancel());
    return const PlanState();
  }

  void _cancel() {
    _timer?.cancel();
    _generation++;
  }

  /// Re-plans after any change to the checkpoints or options.
  void _replan() {
    _cancel();
    if (state.checkpoints.length < 2) {
      state = state.copyWith(status: PlanStatus.idle, error: () => null, variants: const [], selectedId: () => null);
      return;
    }
    state = state.copyWith(status: PlanStatus.loading, error: () => null, cursor: () => null);
    final generation = _generation;
    _timer = Timer(_debounce, () async {
      final s = state;
      try {
        final variants = await planRoutes(
          [for (final c in s.checkpoints) c.coordinate],
          loop: s.loop,
          avoidRoads: s.avoidRoads,
        );
        if (generation != _generation) return;
        state = state.copyWith(
          status: PlanStatus.ready,
          variants: variants,
          selectedId: () => variants.firstOrNull?.id,
        );
      } catch (e) {
        if (generation != _generation) return;
        final message = '$e'.replaceFirst('Exception: ', '');
        state = state.copyWith(
          status: PlanStatus.error,
          error: () => message,
          variants: const [],
          selectedId: () => null,
        );
        AppToast.show(message, level: ToastLevel.error);
      }
    });
  }

  void addCheckpoint(GpsCoordinate point, {String? name}) {
    state = state.copyWith(
      checkpoints: [
        ...state.checkpoints,
        Checkpoint(id: const Uuid().v4(), latitude: point.latitude, longitude: point.longitude, name: name),
      ],
    );
    _replan();
  }

  /// An empty name goes back to the default. Names don't change the route, so no replanning.
  void renameCheckpoint(String id, String name) {
    final trimmed = name.trim();
    final value = trimmed.isEmpty
        ? null
        : (trimmed.length > _maxNameLength ? trimmed.substring(0, _maxNameLength) : trimmed);
    state = state.copyWith(
      checkpoints: [for (final c in state.checkpoints) c.id == id ? c.copyWith(name: () => value) : c],
    );
  }

  void moveCheckpoint(String id, GpsCoordinate point) {
    state = state.copyWith(
      checkpoints: [
        for (final c in state.checkpoints)
          c.id == id ? c.copyWith(latitude: point.latitude, longitude: point.longitude) : c,
      ],
    );
    _replan();
  }

  void removeCheckpoint(String id) {
    state = state.copyWith(
      checkpoints: [
        for (final c in state.checkpoints)
          if (c.id != id) c,
      ],
    );
    _replan();
  }

  /// Removes the most recently added checkpoint.
  void undo() {
    if (state.checkpoints.isEmpty) return;
    state = state.copyWith(checkpoints: state.checkpoints.sublist(0, state.checkpoints.length - 1));
    _replan();
  }

  void setLoop(bool loop) {
    state = state.copyWith(loop: loop);
    _replan();
  }

  void setAvoidRoads(bool avoid) {
    state = state.copyWith(avoidRoads: avoid);
    _replan();
  }

  void select(String id) => state = state.copyWith(selectedId: () => id, cursor: () => null);

  void setCursor(GpsCoordinate? p) => state = state.copyWith(cursor: () => p);

  void reset() {
    _cancel();
    state = const PlanState();
  }
}

final planProvider = NotifierProvider<PlanController, PlanState>(PlanController.new);
