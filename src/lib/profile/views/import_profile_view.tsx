import { useState } from "react";
import { toast } from "sonner";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import { useProfileStore } from "../profile_store";

/** Sets the profile up from a Nostr secret key the user already owns. */
function ImportProfileView() {
  const t = useT();
  const { goBack, goTo } = useNavigation();
  const importProfile = useProfileStore((s) => s.importProfile);
  const [secret, setSecret] = useState("");
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      await importProfile(secret, { name });
      goTo(ROUTES.profile, { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
      setSaving(false);
    }
  }

  const field = "h-12 rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none";

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader
        title={t("profile.importTitle")}
        onBack={goBack}
        backLabel={t("common.cancel")}
        backIcon={false}
      />
      <form onSubmit={submit} className="flex flex-1 flex-col gap-5 px-5 pt-6 pb-6">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="import-secret" className="text-sm font-semibold">
            {t("profile.importKeyLabel")}
          </label>
          <input
            id="import-secret"
            type="password"
            value={secret}
            onChange={(e) => setSecret(e.target.value)}
            placeholder="nsec1…"
            autoComplete="off"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            className={`${field} font-mono`}
          />
          <span className="text-xs text-muted">{t("profile.importKeyHint")}</span>
        </div>

        <div className="flex flex-col gap-1.5">
          <label htmlFor="import-name" className="text-sm font-semibold">
            {t("common.name")}
          </label>
          <input
            id="import-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={60}
            autoComplete="nickname"
            className={field}
          />
          <span className="text-xs text-muted">{t("profile.nameHint")}</span>
        </div>

        <button
          type="submit"
          disabled={saving || secret.trim() === "" || name.trim() === ""}
          className="mt-auto h-[54px] rounded-2xl bg-brand text-base font-semibold text-white disabled:opacity-50"
        >
          {saving ? t("common.saving") : t("profile.importAction")}
        </button>
      </form>
    </main>
  );
}

export default ImportProfileView;
