import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/i18n.dart';

/// Selectable GPS recording intervals, in seconds.
const List<int> recordIntervalsS = [1, 2, 5, 10, 30, 60];
const int defaultRecordIntervalS = 5;

/// Selectable distances from the trail, in meters, beyond which a tour raises an off-track alert.
const List<int> offTrackDistancesM = [25, 50, 100, 200];
const int defaultOffTrackM = 50;

enum ThemeSetting { system, light, dark }

class Settings {
  const Settings({
    required this.theme,
    required this.language,
    required this.recordIntervalS,
    required this.offTrackM,
    required this.checkForUpdates,
  });

  final ThemeSetting theme;
  final AppLanguage language;

  /// Seconds between points added to a track while recording.
  final int recordIntervalS;

  /// How far from the trail, in meters, a tour lets you stray before alerting.
  final int offTrackM;

  /// Look for a newer GitHub release when the app opens.
  final bool checkForUpdates;

  int get recordIntervalMs => recordIntervalS * 1000;

  ThemeMode get themeMode => switch (theme) {
    ThemeSetting.system => ThemeMode.system,
    ThemeSetting.light => ThemeMode.light,
    ThemeSetting.dark => ThemeMode.dark,
  };

  Settings copyWith({
    ThemeSetting? theme,
    AppLanguage? language,
    int? recordIntervalS,
    int? offTrackM,
    bool? checkForUpdates,
  }) => Settings(
    theme: theme ?? this.theme,
    language: language ?? this.language,
    recordIntervalS: recordIntervalS ?? this.recordIntervalS,
    offTrackM: offTrackM ?? this.offTrackM,
    checkForUpdates: checkForUpdates ?? this.checkForUpdates,
  );
}

/// Overridden at start-up with the opened preferences.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

class SettingsController extends Notifier<Settings> {
  static const _theme = 'pania.theme';
  static const _language = 'pania.language';
  static const _interval = 'pania.recordIntervalS';
  static const _offTrack = 'pania.offTrackM';
  static const _updates = 'pania.checkForUpdates';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Settings build() {
    final p = _prefs;
    final settings = Settings(
      theme: ThemeSetting.values.firstWhere((t) => t.name == p.getString(_theme), orElse: () => ThemeSetting.system),
      language: AppLanguage.values.firstWhere((l) => l.name == p.getString(_language), orElse: AppLanguage.detect),
      recordIntervalS: p.getInt(_interval) ?? defaultRecordIntervalS,
      offTrackM: p.getInt(_offTrack) ?? defaultOffTrackM,
      checkForUpdates: p.getBool(_updates) ?? true,
    );
    I18n.language = settings.language;
    return settings;
  }

  void setTheme(ThemeSetting theme) {
    _prefs.setString(_theme, theme.name);
    state = state.copyWith(theme: theme);
  }

  void setLanguage(AppLanguage language) {
    _prefs.setString(_language, language.name);
    I18n.language = language;
    state = state.copyWith(language: language);
  }

  void setRecordIntervalS(int seconds) {
    _prefs.setInt(_interval, seconds);
    state = state.copyWith(recordIntervalS: seconds);
  }

  void setOffTrackM(int meters) {
    _prefs.setInt(_offTrack, meters);
    state = state.copyWith(offTrackM: meters);
  }

  void setCheckForUpdates(bool enabled) {
    _prefs.setBool(_updates, enabled);
    state = state.copyWith(checkForUpdates: enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsController, Settings>(SettingsController.new);
