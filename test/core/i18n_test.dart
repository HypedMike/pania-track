import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/i18n/i18n.dart';
import 'package:pania/core/i18n/translations.dart';

void main() {
  test('Italian has exactly the keys English has', () {
    expect(it.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'keys only in Italian');
    expect(en.keys.toSet().difference(it.keys.toSet()), isEmpty, reason: 'keys only in English');
  });

  test('both languages use the same {placeholders} for a key', () {
    final param = RegExp(r'\{(\w+)\}');
    for (final key in en.keys) {
      final english = param.allMatches(en[key]!).map((m) => m[1]).toSet();
      final italian = param.allMatches(it[key]!).map((m) => m[1]).toSet();
      expect(italian, english, reason: key);
    }
  });

  test('fills in parameters and leaves unknown ones visible', () {
    expect(translate(AppLanguage.en, 'common.pointsCount', {'n': 12}), '12 points');
    expect(translate(AppLanguage.it, 'common.pointsCount', {'n': 12}), '12 punti');
    expect(translate(AppLanguage.en, 'common.pointsCount'), '{n} points');
  });

  test('an unknown key shows the key', () {
    expect(translate(AppLanguage.en, 'no.such.key'), 'no.such.key');
  });

  test('singular and plural', () {
    String t(String key, [Map<String, Object?>? p]) => translate(AppLanguage.en, key, p);
    expect(plural(t, 'common.trail', 1), '1 trail');
    expect(plural(t, 'common.trail', 3), '3 trails');
  });
}
