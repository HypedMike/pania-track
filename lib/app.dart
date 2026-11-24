import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/settings/settings.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/toast.dart';
import 'features/update/presentation/update_prompt.dart';

class PaniaApp extends ConsumerWidget {
  const PaniaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Pania',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      scaffoldMessengerKey: AppToast.messengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: Locale(settings.language.name),
      supportedLocales: const [Locale('en'), Locale('it')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: UpdatePrompt(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
