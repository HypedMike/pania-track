import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import { errorText, sharingApi } from "../sharing_api";

/** Default relays the app ships with; shown with a badge so users can tell theirs apart. */
const DEFAULT_RELAYS = new Set([
  "wss://relay.damus.io",
  "wss://nos.lol",
  "wss://relay.primal.net",
  "wss://relay.nostr.band",
  "wss://offchain.pub",
  "wss://relay.snort.social",
]);

function NostrSettingsView() {
  const t = useT();
  const { goBack } = useNavigation();
  const [relays, setRelays] = useState<string[] | null>(null);
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    sharingApi.relays.list().then(setRelays).catch((e) => toast.error(errorText(e)));
  }, []);

  async function run(action: () => Promise<string[]>, onDone?: () => void) {
    setBusy(true);
    try {
      setRelays(await action());
      onDone?.();
    } catch (e) {
      toast.error(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader title={t("nostr.title")} onBack={goBack} backLabel={t("settings.title")} />
      <div className="flex flex-col gap-6 px-5 pt-5 pb-6">
        <section className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <div>
            <h2 className="text-sm font-semibold">{t("nostr.relaysTitle")}</h2>
            <p className="text-sm text-muted">{t("nostr.relaysHint")}</p>
          </div>

          {relays === null ? (
            <p className="text-sm text-muted">{t("common.loading")}</p>
          ) : (
            <ul className="flex flex-col rounded-xl border border-line">
              {relays.map((relay) => (
                <li key={relay} className="flex min-h-12 items-center gap-2 border-line pl-3.5 not-first:border-t">
                  <span className="min-w-0 flex-1 truncate font-mono text-[13px]">{relay}</span>
                  {DEFAULT_RELAYS.has(relay) && (
                    <span className="shrink-0 rounded-md bg-canvas px-2 py-0.5 text-xs font-semibold text-ink-soft">{t("nostr.defaultBadge")}</span>
                  )}
                  <button
                    type="button"
                    aria-label={t("nostr.remove", { relay })}
                    disabled={busy || relays.length <= 1}
                    onClick={() => void run(() => sharingApi.relays.remove(relay))}
                    className="flex size-11 shrink-0 items-center justify-center text-muted disabled:opacity-30"
                  >
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
                      <path d="M6 6l12 12M18 6L6 18" />
                    </svg>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {relays && <p className="text-xs text-muted">{t("nostr.relayCount", { n: relays.length })}</p>}
        </section>

        <form
          className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4"
          onSubmit={(e) => {
            e.preventDefault();
            void run(() => sharingApi.relays.add(url), () => setUrl(""));
          }}
        >
          <label htmlFor="relay-url" className="text-sm font-semibold">
            {t("nostr.relayInput")}
          </label>
          <input
            id="relay-url"
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder="wss://relay.example.com"
            inputMode="url"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            className="h-12 rounded-xl border border-line-strong bg-surface px-3.5 font-mono text-[15px] text-ink focus:border-2 focus:border-brand-fg focus:outline-none"
          />
          <button type="submit" disabled={busy || url.trim() === ""} className="h-12 rounded-xl bg-brand text-[15px] font-semibold text-white disabled:opacity-50">
            {t("nostr.add")}
          </button>
        </form>

        <button
          type="button"
          disabled={busy}
          onClick={() => void run(sharingApi.relays.reset)}
          className="h-12 rounded-xl border border-line-strong text-[15px] font-semibold disabled:opacity-50"
        >
          {t("nostr.reset")}
        </button>
      </div>
    </main>
  );
}

export default NostrSettingsView;
