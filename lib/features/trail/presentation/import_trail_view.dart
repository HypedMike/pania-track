import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/gps/track_files.dart';
import '../../../core/gps/trail_stats.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/rust/analysis/geo.dart' show Activity;
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/trail_controller.dart';
import '../domain/gps_coordinate.dart';
import '../domain/trail.dart';
import 'trail_map.dart';
import 'trail_widgets.dart';

String _formatSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).round().clamp(1, 1 << 30)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

class _Picked {
  const _Picked(this.name, this.size, this.track);
  final String name;
  final int size;
  final ParsedTrack track;
}

/// Pick a GPX or KML file, preview it and save it as a trail.
class ImportTrailView extends ConsumerStatefulWidget {
  const ImportTrailView({super.key});

  @override
  ConsumerState<ImportTrailView> createState() => _ImportTrailViewState();
}

class _ImportTrailViewState extends ConsumerState<ImportTrailView> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  _Picked? _picked;
  Activity _activity = Activity.foot;
  bool _nameFromFile = false;
  bool _join = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final file = result?.files.single;
      if (file == null || file.bytes == null) return;
      final track = parseTrackFile(utf8.decode(file.bytes!, allowMalformed: true), file.name);
      final fallback = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      setState(() {
        _picked = _Picked(file.name, file.size, track);
        _name.text = track.name ?? fallback;
        _nameFromFile = track.name != null;
        _join = true;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _save() async {
    final picked = _picked;
    if (picked == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final track = picked.track;
      final all = [for (final s in track.segments) ...s];
      final parts = _join || track.segments.length == 1 ? [all] : track.segments;
      final created = <Trail>[];
      for (var i = 0; i < parts.length; i++) {
        created.add(
          await ref
              .read(trailsProvider.notifier)
              .createTrail(
                NewTrail(
                  name: parts.length > 1 ? '${_name.text.trim()} (${i + 1})' : _name.text,
                  description: _description.text,
                  source: TrailSource.imported,
                  activity: _activity,
                  coordinates: parts[i],
                  // Waypoints belong to the file as a whole; keep them with the first trail.
                  waypoints: i == 0 ? track.waypoints : const [],
                ),
              ),
        );
      }
      if (!mounted) return;
      context.goTo(created.length == 1 ? Routes.trailDetail(created.first.id) : Routes.home, replace: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final picked = _picked;
    return PageScaffold(
      title: t('import.title'),
      onBack: context.goBack,
      backLabel: t('common.cancel'),
      body: picked == null
          ? PageColumn(
              gap: 16,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.lineStrong, width: 2),
                    ),
                    child: Column(
                      children: [
                        Text(t('import.chooseFile'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Text(t('import.fileTypes'), style: TextStyle(fontSize: 14, color: c.muted)),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ErrorText(_error!),
              ],
            )
          : _form(context, t, c, picked),
    );
  }

  Widget _form(BuildContext context, TFunction t, AppColors c, _Picked picked) {
    final segments = picked.track.segments;
    // Segments are always previewed as one track; unjoined ones are split into separate trails on save.
    final all = <GpsCoordinate>[for (final s in segments) ...s];
    final stats = computeStats(all);
    return PageColumn(
      gap: 14,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Panel(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.routeTint, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.description_outlined, color: c.routeInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      picked.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${picked.track.format.name.toUpperCase()} · ${_formatSize(picked.size)} · ${t('common.pointsCount', {'n': all.length})}',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: _pick, child: Text(t('import.change'))),
            ],
          ),
        ),
        SizedBox(
          height: 176,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: TrailMap(coordinates: all, waypoints: picked.track.waypoints, source: TrailSource.imported),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: StatTile(label: t('common.distance'), value: formatDistance(stats.distanceM)),
            ),
            Expanded(
              child: StatTile(
                label: t('common.elevationGain'),
                value: formatElevation(stats.elevationGainM, signed: true),
              ),
            ),
            Expanded(
              child: StatTile(label: t('common.duration'), value: formatDuration(stats.durationMs)),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(label: t('common.name'), controller: _name, onChanged: (_) => setState(() {})),
            if (_nameFromFile)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t('import.fromMetadata'), style: TextStyle(fontSize: 12, color: c.muted)),
              ),
          ],
        ),
        LabeledField(
          label: t('common.description'),
          controller: _description,
          hint: t('common.notesPlaceholder'),
          maxLines: 3,
        ),
        ActivityPicker(value: _activity, onChanged: (a) => setState(() => _activity = a), t: t),
        if (segments.length > 1)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _join,
            onChanged: (v) => setState(() => _join = v ?? true),
            title: Text(t('import.join', {'n': segments.length}), style: TextStyle(fontSize: 14, color: c.inkSoft)),
          ),
        if (_error != null) ErrorText(_error!),
        PrimaryButton(
          label: _saving
              ? t('common.saving')
              : (segments.length > 1 && !_join ? t('import.saveMany', {'n': segments.length}) : t('common.saveTrail')),
          onPressed: _saving || _name.text.trim().isEmpty ? null : _save,
        ),
      ],
    );
  }
}
