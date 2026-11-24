import 'package:material_ui/material_ui.dart';

enum ToastLevel { info, success, warning, error }

/// Messages from code that has no [BuildContext] (a tour in progress, say). The app's
/// `MaterialApp` is given [messengerKey].
abstract final class AppToast {
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void show(
    String message, {
    String? description,
    ToastLevel level = ToastLevel.info,
    Duration duration = const Duration(seconds: 5),
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    final icon = switch (level) {
      ToastLevel.info => null,
      ToastLevel.success => Icons.check_circle_outline,
      ToastLevel.warning => Icons.warning_amber_rounded,
      ToastLevel.error => Icons.error_outline,
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          showCloseIcon: true,
          content: Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (description != null) Text(description),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  static void dismiss() => messengerKey.currentState?.hideCurrentSnackBar();
}
