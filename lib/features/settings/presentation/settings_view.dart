import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/app_info.dart';
import '../../../core/gps/background_recorder.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/settings/settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../tour/application/tour_controller.dart';
import '../../trail/application/recording_controller.dart';

const List<(String, String)> _credits = [
  ('OpenStreetMap', 'https://www.openstreetmap.org/copyright'),
  ('BRouter', 'https://brouter.de'),
  ('Photon', 'https://photon.komoot.io'),
  ('Open-Meteo', 'https://open-meteo.com'),
];

String _intervalLabel(int seconds) => seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min';

final _versionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// True on Android 16+ when the person turned Live Updates off for the app. Checked again on return
/// from the system settings.
class _LiveUpdatesWatcher extends ConsumerStatefulWidget {
  const _LiveUpdatesWatcher({required this.builder});

  final Widget Function(bool off) builder;

  @override
  ConsumerState<_LiveUpdatesWatcher> createState() => _LiveUpdatesWatcherState();
}

class _LiveUpdatesWatcherState extends ConsumerState<_LiveUpdatesWatcher> with WidgetsBindingObserver {
  bool _off = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = await BackgroundRecorder.liveUpdateStatus();
    if (mounted) setState(() => _off = s.supported && !s.enabled);
  }

  @override
  Widget build(BuildContext context) => widget.builder(_off);
}

class _Option<T> extends StatelessWidget {
  const _Option({required this.options, required this.value, required this.onChanged});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (id, label) in options)
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => onChanged(id),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: id == value ? c.ink : c.surface,
                borderRadius: BorderRadius.circular(22),
                border: id == value ? null : Border.all(color: c.lineStrong),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: id == value ? FontWeight.w600 : FontWeight.w500,
                  color: id == value ? c.onInk : c.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Theme, language, recording interval, off-track distance, updates, relays and the About block.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  Widget _section(BuildContext context, String title, String hint, List<Widget> children) {
    final c = context.colors;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(hint, style: TextStyle(fontSize: 14, color: c.muted)),
          for (final child in children) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final settings = ref.read(settingsProvider.notifier);
    final recording = ref.watch(recordingProvider.select((r) => r.status == RecordingStatus.recording));
    final touring = ref.watch(tourProvider.select((r) => r.active));
    final version = ref.watch(_versionProvider).value ?? '';

    return PageScaffold(
      title: t('settings.title'),
      onBack: context.goBack,
      backLabel: t('common.back'),
      body: PageColumn(
        gap: 24,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          _section(context, t('settings.theme'), t('settings.themeHint'), [
            _Option<ThemeSetting>(
              options: [
                (ThemeSetting.system, t('settings.themeSystem')),
                (ThemeSetting.light, t('settings.themeLight')),
                (ThemeSetting.dark, t('settings.themeDark')),
              ],
              value: s.theme,
              onChanged: settings.setTheme,
            ),
          ]),
          _section(context, t('settings.language'), t('settings.languageHint'), [
            DropdownButtonFormField<AppLanguage>(
              initialValue: s.language,
              items: [for (final l in AppLanguage.values) DropdownMenuItem(value: l, child: Text(l.label))],
              onChanged: (l) => l == null ? null : settings.setLanguage(l),
            ),
          ]),
          _section(context, t('settings.gpsFrequency'), t('settings.gpsFrequencyHint'), [
            _Option<int>(
              options: [for (final n in recordIntervalsS) (n, _intervalLabel(n))],
              value: s.recordIntervalS,
              onChanged: settings.setRecordIntervalS,
            ),
            if (recording) Text(t('settings.recordingInProgress'), style: TextStyle(fontSize: 14, color: c.muted)),
          ]),
          _section(context, t('settings.offTrack'), t('settings.offTrackHint'), [
            _Option<int>(
              options: [for (final m in offTrackDistancesM) (m, '$m m')],
              value: s.offTrackM,
              onChanged: settings.setOffTrackM,
            ),
            if (touring) Text(t('settings.tourInProgress'), style: TextStyle(fontSize: 14, color: c.muted)),
          ]),
          _LiveUpdatesWatcher(
            builder: (off) => off
                ? _section(context, t('settings.liveUpdates'), t('settings.liveUpdatesHint'), [
                    SmallButton(
                      label: t('settings.liveUpdatesOpen'),
                      onPressed: () => BackgroundRecorder.openLiveUpdateSettings().catchError((_) {}),
                    ),
                  ])
                : const SizedBox.shrink(),
          ),
          _section(context, t('settings.updates'), t('settings.updatesHint'), [
            _Option<bool>(
              options: [(true, t('settings.on')), (false, t('settings.off'))],
              value: s.checkForUpdates,
              onChanged: settings.setCheckForUpdates,
            ),
            Text(t('settings.version', {'version': version}), style: TextStyle(fontSize: 14, color: c.muted)),
          ]),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.goTo(Routes.savedTiles),
            child: Panel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('settings.tiles'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(t('settings.tilesHint'), style: TextStyle(fontSize: 14, color: c.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.muted),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.goTo(Routes.intro),
            child: Panel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('settings.intro'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(t('settings.introHint'), style: TextStyle(fontSize: 14, color: c.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.muted),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.goTo(Routes.nostrSettings),
            child: Panel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('settings.nostr'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(t('settings.nostrHint'), style: TextStyle(fontSize: 14, color: c.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.muted),
                ],
              ),
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/logo.png', width: 48, height: 48),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('about.title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(
                            'pania · ${t('settings.version', {'version': version})}',
                            style: TextStyle(fontSize: 14, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(t('about.description'), style: TextStyle(fontSize: 14, color: c.inkSoft)),
                const SizedBox(height: 12),
                Text(t('about.privacy'), style: TextStyle(fontSize: 14, color: c.muted)),
                const SizedBox(height: 12),
                SecondaryButton(height: 48, label: t('about.source'), onPressed: () => openExternal(repoUrl)),
                const SizedBox(height: 12),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${t('about.credits')} ', style: TextStyle(fontSize: 12, color: c.muted)),
                    for (var i = 0; i < _credits.length; i++) ...[
                      if (i > 0) Text(' · ', style: TextStyle(fontSize: 12, color: c.muted)),
                      InkWell(
                        onTap: () => openExternal(_credits[i].$2),
                        child: Text(
                          _credits[i].$1,
                          style: TextStyle(fontSize: 12, color: c.brandFg, decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
