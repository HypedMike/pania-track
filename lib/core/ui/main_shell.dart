import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// The four tabs: trails, explore, stats and profile, each keeping its own state.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final tabs = <(IconData, IconData, String)>[
      (Icons.landscape_outlined, Icons.landscape, t('nav.trails')),
      (Icons.explore_outlined, Icons.explore, t('nav.explore')),
      (Icons.bar_chart_outlined, Icons.bar_chart, t('nav.stats')),
      (Icons.person_outline, Icons.person, t('nav.profile')),
    ];
    return Scaffold(
      body: SafeArea(bottom: false, child: shell),
      bottomNavigationBar: NavigationBar(
        height: 72,
        backgroundColor: c.surface,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          for (final (icon, selectedIcon, label) in tabs)
            NavigationDestination(
              icon: Icon(icon, color: c.muted),
              selectedIcon: Icon(selectedIcon, color: c.brandFg),
              label: label,
            ),
        ],
      ),
    );
  }
}
