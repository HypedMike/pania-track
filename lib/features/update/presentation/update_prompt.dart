import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/update_controller.dart';
import '../domain/format_progress.dart';

/// Shows the update offer over the app when a newer release exists. Mount once above the router.
class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// After the user grants the permission in system settings and comes back, carry on by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(updateProvider).phase == UpdatePhase.needsPermission) {
      ref.read(updateProvider.notifier).install();
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateProvider);
    final release = update.release;
    return Stack(
      children: [
        widget.child,
        if (release != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 384),
                    child: _Card(update: update),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.update});

  final UpdateState update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final controller = ref.read(updateProvider.notifier);
    final release = update.release!;
    final downloading = update.phase == UpdatePhase.downloading;
    final pct = update.progress == null ? null : percent(update.progress!);
    final message = switch (update.phase) {
      UpdatePhase.needsPermission => t('update.permissionText'),
      UpdatePhase.failed => t('update.failed', {'error': update.error}),
      UpdatePhase.downloading => t('update.downloading', {'version': release.version}),
      UpdatePhase.idle => t('update.message', {'version': release.version, 'current': update.currentVersion}),
    };
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(24),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('update.title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message, style: TextStyle(fontSize: 14, color: c.muted)),
            if (downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct == null ? null : pct / 100,
                  minHeight: 10,
                  backgroundColor: c.line,
                  color: c.brand,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                update.progress == null ? t('update.starting') : describeProgress(update.progress!, t),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
            const SizedBox(height: 16),
            if (update.phase == UpdatePhase.needsPermission)
              PrimaryButton(label: t('update.permissionAction'), onPressed: controller.openInstallSettings)
            else
              PrimaryButton(
                label: downloading
                    ? t('update.downloadingShort')
                    : (update.phase == UpdatePhase.failed ? t('update.retry') : t('update.action')),
                onPressed: downloading ? null : controller.install,
              ),
            if (update.phase == UpdatePhase.failed) ...[
              const SizedBox(height: 8),
              SecondaryButton(label: t('update.openBrowser'), onPressed: controller.openInBrowser),
            ],
            const SizedBox(height: 8),
            SecondaryButton(label: t('update.later'), onPressed: downloading ? null : controller.dismiss),
          ],
        ),
      ),
    );
  }
}
