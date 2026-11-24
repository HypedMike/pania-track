import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import 'translations.dart';

/// The languages the app is translated into. [locale] is the BCP 47 tag used for formatting.
enum AppLanguage {
  en('English', 'en_GB'),
  it('Italiano', 'it_IT');

  const AppLanguage(this.label, this.locale);

  final String label;
  final String locale;

  /// Picks a supported language from the device's preferences, defaulting to English.
  static AppLanguage detect() {
    final preferred = ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return AppLanguage.values.firstWhere((l) => l.name == preferred, orElse: () => AppLanguage.en);
  }
}

typedef TFunction = String Function(String key, [Map<String, Object?>? params]);

final RegExp _param = RegExp(r'\{(\w+)\}');

String translate(AppLanguage language, String key, [Map<String, Object?>? params]) {
  final dictionary = language == AppLanguage.it ? it : en;
  final text = dictionary[key] ?? en[key] ?? key;
  if (params == null) return text;
  return text.replaceAllMapped(_param, (m) => '${params[m[1]] ?? '{${m[1]}}'}');
}

/// Translation outside widgets (errors, formatters). Follows the language setting.
abstract final class I18n {
  static AppLanguage language = AppLanguage.en;

  static String t(String key, [Map<String, Object?>? params]) => translate(language, key, params);

  /// Locale for `intl` formatting in the current language.
  static String get locale => language.locale;
}

/// A `t` that rebuilds whoever watches it when the language changes.
final tProvider = Provider<TFunction>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return (key, [params]) => translate(language, key, params);
});

/// Singular/plural count label, e.g. `plural(t, 'common.trail', 3)` → "3 trails".
String plural(TFunction t, String base, int n) => t('$base.${n == 1 ? 'one' : 'other'}', {'n': n});
