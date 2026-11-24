import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/profile_controller.dart';
import '../data/avatar_image.dart';
import 'avatar.dart';

/// Creates the profile (and its Nostr key), or edits the existing one's name and picture.
class CreateProfileView extends ConsumerStatefulWidget {
  const CreateProfileView({super.key});

  @override
  ConsumerState<CreateProfileView> createState() => _CreateProfileViewState();
}

class _CreateProfileViewState extends ConsumerState<CreateProfileView> {
  // Fixed on first build: creating the profile must not flip this screen into edit mode.
  late final bool _editing = ref.read(profileProvider) != null;
  late final TextEditingController _name = TextEditingController(text: ref.read(profileProvider)?.name ?? '');
  late Uint8List? _picture = ref.read(profileProvider)?.picture;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final t = ref.read(tProvider);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;
      final avatar = await imageToAvatar(bytes);
      if (mounted) setState(() => _picture = avatar);
    } catch (_) {
      if (mounted) showToast(context, t('profile.pictureError'));
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final controller = ref.read(profileProvider.notifier);
      if (_editing) {
        controller.updateProfile(_name.text, _picture);
      } else {
        await controller.createProfile(_name.text, _picture);
      }
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
      title: _editing ? t('profile.editTitle') : t('profile.createTitle'),
      onBack: context.goBack,
      backLabel: t('common.cancel'),
      body: PageColumn(
        gap: 20,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Column(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_picture != null || _name.text.trim().isNotEmpty)
                      Avatar(name: _name.text.isEmpty ? '?' : _name.text, picture: _picture, size: 112)
                    else
                      Container(
                        decoration: BoxDecoration(color: c.map, shape: BoxShape.circle),
                        child: Icon(Icons.person_outline, size: 44, color: c.muted),
                      ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Tooltip(
                        message: t('profile.addPicture'),
                        child: InkResponse(
                          onTap: _pickPicture,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: c.brand,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.canvas, width: 3),
                            ),
                            child: const Icon(Icons.photo_camera_outlined, size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_picture != null)
                TextButton(onPressed: () => setState(() => _picture = null), child: Text(t('profile.removePicture')))
              else
                Text(t('profile.pictureOptional'), style: TextStyle(fontSize: 13, color: c.muted)),
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
                autofillHints: const [AutofillHints.nickname],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 4),
              Text(t('profile.nameHint'), style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          if (!_editing) ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: c.brandTint, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.key_outlined, size: 18, color: c.brandTintInk),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('profile.keyCreatedTitle'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t('profile.keyCreatedText'),
                              style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: c.warnTint, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      t('profile.backupWarning'),
                      style: TextStyle(fontSize: 13, height: 1.35, color: c.warnInk),
                    ),
                  ),
                ],
              ),
            ),
            Text(t('profile.publicNote'), style: TextStyle(fontSize: 13, height: 1.35, color: c.muted)),
          ],
          PrimaryButton(
            label: _saving ? t('common.saving') : (_editing ? t('profile.save') : t('profile.create')),
            onPressed: _saving || _name.text.trim().isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}
