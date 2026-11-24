import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/profile_controller.dart';

/// Shows the secret key once the user asks for it, so they can write it down.
Future<void> showBackupKeyDialog(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _BackupSheet());

class _BackupSheet extends ConsumerStatefulWidget {
  const _BackupSheet();

  @override
  ConsumerState<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<_BackupSheet> {
  String? _nsec;
  bool _loaded = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(profileProvider.notifier)
        .revealSecretKey()
        .then((key) {
          if (!mounted) return;
          setState(() {
            _nsec = key;
            _loaded = true;
          });
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() {
            _nsec = null;
            _loaded = true;
          });
        });
  }

  Future<void> _copy() async {
    final t = ref.read(tProvider);
    await Clipboard.setData(ClipboardData(text: _nsec!));
    if (mounted) showToast(context, t('profile.copied'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('profile.backupTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(t('profile.backupText'), style: TextStyle(fontSize: 14, color: c.muted)),
        const SizedBox(height: 16),
        if (_loaded && _nsec == null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnTint, borderRadius: BorderRadius.circular(12)),
            child: Text(t('profile.keyMissing'), style: TextStyle(fontSize: 14, color: c.warnInk)),
          ),
        if (_nsec != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: ImageFiltered(
              enabled: !_shown,
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: SelectableText(_nsec!, style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  height: 48,
                  label: _shown ? t('profile.hide') : t('profile.reveal'),
                  onPressed: () => setState(() => _shown = !_shown),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SecondaryButton(height: 48, label: t('profile.copySecret'), onPressed: _shown ? _copy : null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: t('profile.backupConfirm'),
            onPressed: () {
              ref.read(profileProvider.notifier).markBackedUp();
              Navigator.pop(context);
            },
          ),
        ],
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('profile.close'))),
      ],
    );
  }
}
