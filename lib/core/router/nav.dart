import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'routes.dart';

extension AppNavigation on BuildContext {
  /// Opens a page on top of the current one.
  void goTo(String route, {bool replace = false}) {
    final router = GoRouter.of(this);
    replace ? router.pushReplacement(route) : router.push(route);
  }

  /// Switches to a top-level tab (no back stack).
  void goTab(String route) => GoRouter.of(this).go(route);

  /// Goes back, or home when there is nothing to go back to.
  void goBack() {
    final router = GoRouter.of(this);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(Routes.home);
    }
  }
}
