import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/explore_controller.dart' show errorText;
import '../data/sharing_api.dart';

/// Default relays the app ships with; shown with a badge so users can tell theirs apart.
const Set<String> _defaultRelays = {
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://relay.nostr.band',
  'wss://offchain.pub',
  'wss://relay.snort.social',
};

/// The relays the app talks to: the defaults plus the user's own.
class NostrSettingsView extends ConsumerStatefulWidget {
  const NostrSettingsView({super.key});

  @override
  ConsumerState<NostrSettingsView> createState() => _NostrSettingsViewState();
}

class _NostrSettingsViewState extends ConsumerState<NostrSettingsView> {
  final _url = TextEditingController();
  List<String>? _relays;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharingApi.relaysList()
        .then((r) {
          if (mounted) setState(() => _relays = r);
        })
        .catchError((Object e) {
          if (mounted) showToast(context, errorText(e));
        });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<List<String>> Function() action, {VoidCallback? onDone}) async {
    setState(() => _busy = true);
    try {
      final list = await action();
      if (mounted) setState(() => _relays = list);
      onDone?.call();
    } catch (e) {
      if (mounted) showToast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.colors;
    final relays = _relays;
    return PageScaffold(
      title: t('nostr.title'),
      onBack: context.goBack,
      backLabel: t('settings.title'),
      body: PageColumn(
        gap: 24,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('nostr.relaysTitle'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(t('nostr.relaysHint'), style: TextStyle(fontSize: 14, color: c.muted)),
                const SizedBox(height: 12),
                if (relays == null)
                  Text(t('common.loading'), style: TextStyle(fontSize: 14, color: c.muted))
                else
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < relays.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: c.line),
                          Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    relays[i],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                                  ),
                                ),
                                if (_defaultRelays.contains(relays[i])) Pill(t('nostr.defaultBadge')),
                                IconButton(
                                  tooltip: t('nostr.remove', {'relay': relays[i]}),
                                  onPressed: _busy || relays.length <= 1
                                      ? null
                                      : () => _run(() => SharingApi.relaysRemove(relays[i])),
                                  icon: Icon(Icons.close, size: 18, color: c.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (relays != null) ...[
                  const SizedBox(height: 8),
                  Text(t('nostr.relayCount', {'n': relays.length}), style: TextStyle(fontSize: 12, color: c.muted)),
                ],
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('nostr.relayInput'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'wss://relay.example.com'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  height: 48,
                  label: t('nostr.add'),
                  onPressed: _busy || _url.text.trim().isEmpty
                      ? null
                      : () => _run(() => SharingApi.relaysAdd(_url.text), onDone: _url.clear),
                ),
              ],
            ),
          ),
          SecondaryButton(
            height: 48,
            label: t('nostr.reset'),
            onPressed: _busy ? null : () => _run(SharingApi.relaysReset),
          ),
        ],
      ),
    );
  }
}
