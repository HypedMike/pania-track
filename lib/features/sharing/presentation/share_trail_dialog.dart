import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../../profile/application/profile_controller.dart';
import '../../trail/application/trail_controller.dart';
import '../../trail/domain/trail.dart';
import '../application/explore_controller.dart' show errorText;
import '../data/sharing_api.dart';

enum _Step { confirm, sharing, done, failed, stopping }

/// Asks before publishing a trail, then publishes it (or updates / stops a shared one).
Future<void> showShareTrailDialog(BuildContext context, Trail trail) =>
    showAppSheet<void>(context, dismissible: true, builder: (_) => _ShareTrailSheet(trail: trail));

class _ShareTrailSheet extends ConsumerStatefulWidget {
  const _ShareTrailSheet({required this.trail});

  final Trail trail;

  @override
  ConsumerState<_ShareTrailSheet> createState() => _ShareTrailSheetState();
}

class _ShareTrailSheetState extends ConsumerState<_ShareTrailSheet> {
  _Step _step = _Step.confirm;
  ShareResult? _result;
  String _error = '';

  bool get _busy => _step == _Step.sharing || _step == _Step.stopping;

  Future<void> _share() async {
    final profile = ref.read(profileProvider);
    setState(() => _step = _Step.sharing);
    try {
      final shared = await SharingApi.shareTrail(widget.trail, authorName: profile?.name);
      await ref
          .read(trailsProvider.notifier)
          .updateTrail(widget.trail.copyWith(sharedAt: DateTime.now(), sharedEventId: shared.eventId));
      if (!mounted) return;
      setState(() {
        _result = shared;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _step = _Step.failed;
      });
    }
  }

  Future<void> _stop() async {
    final t = ref.read(tProvider);
    setState(() => _step = _Step.stopping);
    try {
      await SharingApi.unshareTrail(widget.trail.id);
      await ref.read(trailsProvider.notifier).updateTrail(widget.trail.copyWith(clearShared: true));
      if (!mounted) return;
      showToast(context, t('share.stopped'));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _step = _Step.failed;
      });
    }
  }

  Widget _point(String text, AppColors c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7, right: 10),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.brandFg, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 14, height: 1.35, color: c.inkSoft)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final profile = ref.watch(profileProvider);
    final alreadyShared = widget.trail.sharedAt != null;
    const title = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);

    if (profile == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('share.needProfile'), style: title),
          const SizedBox(height: 8),
          Text(t('share.needProfileHint'), style: TextStyle(fontSize: 14, color: c.muted)),
          const SizedBox(height: 16),
          PrimaryButton(
            label: t('share.createProfile'),
            onPressed: () {
              Navigator.pop(context);
              context.goTo(Routes.profileCreate);
            },
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('common.cancel'))),
        ],
      );
    }

    if (_step == _Step.done && _result != null) {
      final r = _result!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('share.done'), style: title),
          const SizedBox(height: 12),
          _point(
            t('share.doneRelays', {'ok': r.relaysOk.length, 'total': r.relaysOk.length + r.relaysFailed.length}),
            c,
          ),
          _point(
            t('share.doneCompression', {
              'kept': r.report.keptPoints,
              'total': r.report.originalPoints,
              'removed': r.report.removedPct,
              'err': r.report.maxErrorM,
            }),
            c,
          ),
          const SizedBox(height: 8),
          PrimaryButton(label: t('share.close'), onPressed: () => Navigator.pop(context)),
        ],
      );
    }

    if (_step == _Step.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('share.failed'), style: title),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnTint, borderRadius: BorderRadius.circular(12)),
            child: Text(_error, style: TextStyle(fontSize: 14, color: c.warnInk)),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: t('share.retry'), onPressed: () => setState(() => _step = _Step.confirm)),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('common.cancel'))),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(alreadyShared ? t('share.confirmUpdateTitle') : t('share.confirmTitle'), style: title),
        const SizedBox(height: 14),
        _point(t('share.pointAnyone'), c),
        _point(t('share.pointStart'), c),
        _point(t('share.pointIdentity', {'name': profile.name}), c),
        _point(t('share.pointRelays'), c),
        _point(t('share.pointSimplified'), c),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(label: t('common.cancel'), onPressed: _busy ? null : () => Navigator.pop(context)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: _step == _Step.sharing
                    ? t('share.sharing')
                    : (alreadyShared ? t('share.confirmUpdate') : t('share.confirm')),
                onPressed: _busy ? null : _share,
              ),
            ),
          ],
        ),
        if (alreadyShared) ...[
          const Divider(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _stop,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              child: Text(_step == _Step.stopping ? t('share.sharing') : t('share.stop')),
            ),
          ),
          Text(t('share.stopHint'), style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ],
    );
  }
}
