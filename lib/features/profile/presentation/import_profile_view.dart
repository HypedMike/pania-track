import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/profile_controller.dart';

/// Sets the profile up from a Nostr secret key the user already owns.
class ImportProfileView extends ConsumerStatefulWidget {
  const ImportProfileView({super.key});

  @override
  ConsumerState<ImportProfileView> createState() => _ImportProfileViewState();
}

class _ImportProfileViewState extends ConsumerState<ImportProfileView> {
  final _secret = TextEditingController();
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _secret.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).importProfile(_secret.text, _name.text);
      if (mounted) context.goTo(Routes.profile, replace: true);
    } catch (e) {
      if (mounted) {
        showToast(context, '$e'.replaceFirst('Exception: ', ''));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    return PageScaffold(
      title: t('profile.importTitle'),
      onBack: context.goBack,
      backLabel: t('common.cancel'),
      body: PageColumn(
        gap: 20,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('profile.importKeyLabel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _secret,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(hintText: 'nsec1…'),
              ),
              const SizedBox(height: 4),
              Text(t('profile.importKeyHint'), style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('common.name'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                maxLength: 60,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 4),
              Text(t('profile.nameHint'), style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          PrimaryButton(
            label: _saving ? t('common.saving') : t('profile.importAction'),
            onPressed: _saving || _secret.text.trim().isEmpty || _name.text.trim().isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}
