import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pania_native/pania_native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/rust/api/core.dart';
import 'core/rust/frb_generated.dart';
import 'core/settings/settings.dart';

/// Starts the Rust core: where it may keep files, and how it reaches the Android Keystore for the
/// Nostr secret key. Without a keystore (desktop development) secrets fall back to a plain file.
Future<void> _startCore() async {
  await RustLib.init();
  final dir = await getApplicationSupportDirectory();
  await initCore(
    configDir: dir.path,
    keystoreAvailable: PaniaNative.supported,
    secretGet: (key) async {
      try {
        return await PaniaNative.getSecret(key);
      } catch (_) {
        return null;
      }
    },
    secretSet: (key, value) async {
      try {
        await PaniaNative.setSecret(key, value);
        return '';
      } catch (e) {
        return '$e';
      }
    },
    secretDelete: (key) async {
      try {
        await PaniaNative.deleteSecret(key);
      } catch (_) {}
    },
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  await _startCore();
  runApp(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)], child: const PaniaApp()));
}
