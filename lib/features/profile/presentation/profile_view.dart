import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../trail/application/trail_controller.dart';
import '../application/profile_controller.dart';
import '../domain/profile.dart';
import 'avatar.dart';
import 'backup_key_dialog.dart';

/// The Profile tab: create or import an identity, see it, back it up, remove it.
class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final profile = ref.watch(profileProvider);
    return PageColumn(
      gap: 16,
      children: [
        LargeTitle(
          t('profile.pageTitle'),
          trailing: profile == null
              ? null
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), shape: const StadiumBorder()),
                  onPressed: () => context.goTo(Routes.profileCreate),
                  child: Text(t('profile.edit'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
        ),
        if (profile == null) ..._empty(context, t) else ..._details(context, ref, t, profile),
      ],
    );
  }

  List<Widget> _empty(BuildContext context, TFunction t) {
    final c = context.colors;
    Widget benefit(IconData icon, String title, String text, {bool first = false}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.brandTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: c.brandTintInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: c.muted)),
              ],
            ),
          ),
        ],
      ),
    );
    return [
      Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.lineStrong, width: 2),
            ),
            child: Icon(Icons.person_outline, size: 34, color: c.muted),
          ),
          const SizedBox(height: 10),
          Text(t('profile.emptyTitle'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            t('profile.emptyIntro'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.muted),
          ),
        ],
      ),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            benefit(Icons.share_outlined, t('profile.benefitShareTitle'), t('profile.benefitShareText'), first: true),
            benefit(Icons.key_outlined, t('profile.benefitKeyTitle'), t('profile.benefitKeyText')),
          ],
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.lock_outline, size: 16, color: c.inkSoft),
          ),
          Expanded(
            child: Text(t('profile.privateByDefault'), style: TextStyle(fontSize: 13, height: 1.35, color: c.inkSoft)),
          ),
        ],
      ),
      PrimaryButton(label: t('profile.create'), onPressed: () => context.goTo(Routes.profileCreate)),
      TextButton(onPressed: () => context.goTo(Routes.profileImport), child: Text(t('profile.haveKey'))),
    ];
  }

  List<Widget> _details(BuildContext context, WidgetRef ref, TFunction t, Profile profile) {
    final c = context.colors;
    final trails = ref.watch(trailsProvider).value ?? const [];
    final keyMissing = ref.watch(_keyMissingProvider).value ?? false;
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: profile.npub));
      if (context.mounted) showToast(context, t('profile.copied'));
    }

    return [
      Panel(
        child: Row(
          children: [
            Avatar(name: profile.name, picture: profile.picture, size: 68),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shortNpub(profile.npub),
                    style: TextStyle(fontSize: 13, color: c.muted, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            RoundIconButton(icon: Icons.copy, tooltip: t('profile.copyKey'), onPressed: copy),
          ],
        ),
      ),
      if (keyMissing)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.warnTint, borderRadius: BorderRadius.circular(12)),
          child: Text(t('profile.keyMissing'), style: TextStyle(fontSize: 13, height: 1.35, color: c.warnInk)),
        ),
      Row(
        children: [
          Expanded(
            child: StatTile(label: t('profile.public'), value: '${trails.where((x) => x.sharedAt != null).length}'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(label: t('profile.private'), value: '${trails.length}'),
          ),
        ],
      ),
      Text(t('profile.publicTrails'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      if (trails.where((x) => x.sharedAt != null).isEmpty)
        Panel(
          child: Text(t('profile.noPublicTrails'), style: TextStyle(fontSize: 14, color: c.muted)),
        )
      else
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final trail in trails.where((x) => x.sharedAt != null))
                ListTile(title: Text(trail.name), onTap: () => context.goTo(Routes.trailDetail(trail.id))),
            ],
          ),
        ),
      Text(t('profile.account'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => showBackupKeyDialog(context),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(t('profile.backup'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    Pill(
                      profile.backedUp ? t('profile.backupDone') : t('profile.backupNotDone'),
                      background: profile.backedUp ? c.brandTint : c.warnTint,
                      foreground: profile.backedUp ? c.brandTintInk : c.warnInk,
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: c.line),
            InkWell(
              onTap: () async {
                final confirmed = await confirmDialog(
                  context,
                  message: t('profile.removeText'),
                  confirmLabel: t('profile.removeConfirm'),
                  cancelLabel: t('common.cancel'),
                  destructive: true,
                );
                if (!confirmed) return;
                try {
                  await ref.read(profileProvider.notifier).removeProfile();
                } catch (e) {
                  if (context.mounted) showToast(context, '$e');
                }
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  t('profile.remove'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// The profile record can outlive its key (app data restored on another phone): say so.
final _keyMissingProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (ref.watch(profileProvider) == null) return false;
  return !(await ref.read(profileProvider.notifier).hasSecretKey());
});
