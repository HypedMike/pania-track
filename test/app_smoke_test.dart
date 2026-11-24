import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pania/app.dart';
import 'package:pania/core/database/database.dart';
import 'package:pania/core/database/providers.dart';
import 'package:pania/core/settings/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('the app starts on the trail list and moves between its tabs', (tester) async {
    SharedPreferences.setMockInitialValues({'pania.language': 'en', 'pania.checkForUpdates': false});
    final prefs = await SharedPreferences.getInstance();

    late Database db;
    await tester.runAsync(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await migrateDatabase(db, (path) => File(path).readAsString());
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(() async => db),
        ],
        child: const PaniaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Home: empty list, the three actions.
    expect(find.text('Trails'), findsWidgets);
    expect(find.text('Record'), findsOneWidget);
    expect(find.text('Import GPX'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);

    await tester.tap(find.text('Stats'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Insights'), findsWidgets);

    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Create profile'), findsWidgets);

    // The settings page opens from the home tab's button.
    await tester.tap(find.text('Trails'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Theme'), findsWidgets);

    await tester.runAsync(db.close);
  });
}
