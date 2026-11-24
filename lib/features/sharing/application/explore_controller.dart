import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rust/analysis/geo.dart';
import '../data/sharing_api.dart';

enum LengthFilter {
  any(null, null),
  short(null, 5),
  medium(5, 15),
  long(15, null);

  const LengthFilter(this.minKm, this.maxKm);

  /// Length bucket in km; null means open-ended.
  final double? minKm;
  final double? maxKm;

  String get labelKey => switch (this) {
    LengthFilter.any => 'explore.lengthAny',
    LengthFilter.short => 'explore.lengthShort',
    LengthFilter.medium => 'explore.lengthMedium',
    LengthFilter.long => 'explore.lengthLong',
  };
}

const List<int> radiiKm = [5, 10, 25, 50];

class ExploreFilters {
  const ExploreFilters({this.radiusKm = 10, this.length = LengthFilter.any, this.activity, this.difficulty = const []});

  final int radiusKm;
  final LengthFilter length;

  /// Null means both.
  final Activity? activity;
  final List<Difficulty> difficulty;

  ExploreFilters copyWith({
    int? radiusKm,
    LengthFilter? length,
    Activity? Function()? activity,
    List<Difficulty>? difficulty,
  }) => ExploreFilters(
    radiusKm: radiusKm ?? this.radiusKm,
    length: length ?? this.length,
    activity: activity == null ? this.activity : activity(),
    difficulty: difficulty ?? this.difficulty,
  );
}

class SearchCenter {
  const SearchCenter(this.lat, this.lon);
  final double lat;
  final double lon;
}

class ExploreState {
  const ExploreState({
    this.filters = const ExploreFilters(),
    this.center,
    this.results = const [],
    this.loading = false,
    this.error,
    this.searched = false,
    this.selectedId,
  });

  final ExploreFilters filters;

  /// Where the last search was centered; null until the user has a position or moves the map.
  final SearchCenter? center;
  final List<SharedTrail> results;
  final bool loading;
  final String? error;

  /// False until the first search finishes, so "nothing found" is not shown before searching.
  final bool searched;
  final String? selectedId;

  ExploreState copyWith({
    ExploreFilters? filters,
    SearchCenter? center,
    List<SharedTrail>? results,
    bool? loading,
    String? Function()? error,
    bool? searched,
    String? Function()? selectedId,
  }) => ExploreState(
    filters: filters ?? this.filters,
    center: center ?? this.center,
    results: results ?? this.results,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error(),
    searched: searched ?? this.searched,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
  );
}

class ExploreController extends Notifier<ExploreState> {
  // Answers can arrive out of order when filters change quickly; only the latest one is kept.
  int _latest = 0;

  @override
  ExploreState build() => const ExploreState();

  void setFilters(ExploreFilters filters) {
    state = state.copyWith(filters: filters);
    if (state.center != null) search();
  }

  /// Searches around [center] (or the previous center) with the current filters.
  Future<void> search([SearchCenter? center]) async {
    final where = center ?? state.center;
    if (where == null) return;
    final request = ++_latest;
    state = state.copyWith(center: where, loading: true, error: () => null);
    final f = state.filters;
    try {
      final results = await SharingApi.explore(
        ExploreQuery(
          lat: where.lat,
          lon: where.lon,
          radiusKm: f.radiusKm.toDouble(),
          minLengthKm: f.length.minKm,
          maxLengthKm: f.length.maxKm,
          activity: f.activity,
          difficulty: f.difficulty,
        ),
      );
      if (request != _latest) return;
      state = state.copyWith(results: results, loading: false, searched: true, selectedId: () => null);
    } catch (e) {
      if (request != _latest) return;
      state = state.copyWith(loading: false, searched: true, error: () => errorText(e), results: const []);
    }
  }

  void select(String? eventId) => state = state.copyWith(selectedId: () => eventId);
}

/// Rust errors arrive as plain text.
String errorText(Object e) {
  final text = '$e';
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

final exploreProvider = NotifierProvider<ExploreController, ExploreState>(ExploreController.new);
