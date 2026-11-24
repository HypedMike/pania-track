import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/geocoding/photon.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/settings/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/toast.dart';
import '../../trail/domain/gps_coordinate.dart';

const Duration _debounce = Duration(milliseconds: 300);
const int _minChars = 2;

enum _Status { idle, loading, done, error }

IconData _iconOf(PlaceKind kind) => switch (kind) {
  PlaceKind.peak => Icons.landscape_outlined,
  PlaceKind.nature => Icons.park_outlined,
  PlaceKind.settlement => Icons.location_city_outlined,
  PlaceKind.other => Icons.place_outlined,
};

/// Search box with type-ahead results for towns, peaks and other places.
class PlaceSearch extends ConsumerStatefulWidget {
  const PlaceSearch({super.key, required this.onSelect, this.near, this.onClear});

  /// Results are ranked by distance from here (the map centre).
  final GpsCoordinate? Function()? near;
  final void Function(Place place) onSelect;

  /// Called when the user clears the box.
  final VoidCallback? onClear;

  @override
  ConsumerState<PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends ConsumerState<PlaceSearch> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _generation = 0;
  List<Place> _results = const [];
  _Status _status = _Status.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    final query = text.trim();
    final generation = ++_generation;
    if (query.length < _minChars) {
      setState(() {
        _results = const [];
        _status = _Status.idle;
      });
      return;
    }
    setState(() => _status = _Status.loading);
    _timer = Timer(_debounce, () async {
      try {
        final places = await searchPlaces(
          query,
          near: widget.near?.call(),
          language: ref.read(settingsProvider).language,
        );
        if (generation != _generation || !mounted) return;
        setState(() {
          _results = places;
          _status = _Status.done;
        });
      } catch (e) {
        if (generation != _generation || !mounted) return;
        final message = '$e'.replaceFirst('Exception: ', '');
        setState(() {
          _error = message;
          _status = _Status.error;
        });
        AppToast.show(message, level: ToastLevel.error);
      }
    });
  }

  void _choose(Place place) {
    _controller.text = place.name;
    _focus.unfocus();
    widget.onSelect(place);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final showList = _focus.hasFocus && _controller.text.trim().length >= _minChars && _status != _Status.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: c.surface,
          elevation: 3,
          shape: const StadiumBorder(),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search, size: 20, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (_results.isNotEmpty) _choose(_results.first);
                    },
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: t('search.placeholder'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  IconButton(
                    tooltip: t('search.clear'),
                    icon: Icon(Icons.close, size: 18, color: c.muted),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                      widget.onClear?.call();
                      _focus.requestFocus();
                    },
                  ),
              ],
            ),
          ),
        ),
        if (showList)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 288),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x2E162018), blurRadius: 24, offset: Offset(0, 6))],
            ),
            clipBehavior: Clip.antiAlias,
            child: _status == _Status.loading && _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(t('search.searching'), style: TextStyle(fontSize: 14, color: c.muted)),
                  )
                : _status == _Status.error
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error ?? '', style: TextStyle(fontSize: 14, color: c.danger)),
                  )
                : _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(t('search.noResults'), style: TextStyle(fontSize: 14, color: c.muted)),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final place in _results)
                        InkWell(
                          onTap: () => _choose(place),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(_iconOf(place.kind), size: 18, color: c.muted),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        place.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        '${place.kind == PlaceKind.peak ? '${t('search.peak')} · ' : ''}${place.context}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: c.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}
