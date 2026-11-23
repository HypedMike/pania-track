import { useRef, useState } from "react";
import { toast } from "sonner";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import Avatar from "../components/avatar";
import { fileToAvatar } from "../image";
import { useProfileStore } from "../profile_store";

/** Creates the profile (and its Nostr key), or edits the existing one's name and picture. */
function CreateProfileView() {
  const t = useT();
  const { goBack, goTo } = useNavigation();
  const existing = useProfileStore((s) => s.profile);
  const createProfile = useProfileStore((s) => s.createProfile);
  const updateProfile = useProfileStore((s) => s.updateProfile);
  // Fixed on first render: creating the profile must not flip this screen into edit mode.
  const [editing] = useState(existing !== null);
  const [name, setName] = useState(existing?.name ?? "");
  const [picture, setPicture] = useState<string | undefined>(existing?.picture);
  const [saving, setSaving] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);

  async function pickPicture(file: File | undefined) {
    if (!file) return;
    try {
      setPicture(await fileToAvatar(file));
    } catch {
      toast.error(t("profile.pictureError"));
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      if (editing) updateProfile({ name, picture });
      else await createProfile({ name, picture });
      goTo(ROUTES.profile, { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
      setSaving(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader
        title={editing ? t("profile.editTitle") : t("profile.createTitle")}
        onBack={goBack}
        backLabel={t("common.cancel")}
        backIcon={false}
      />
      <form onSubmit={submit} className="flex flex-1 flex-col gap-5 px-5 pt-6 pb-6">
        <div className="flex flex-col items-center gap-2.5">
          <div className="relative size-28">
            {picture || name.trim() ? (
              <Avatar name={name || "?"} picture={picture} size={112} />
            ) : (
              <div className="flex size-28 items-center justify-center rounded-full bg-map text-muted">
                <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" aria-hidden="true">
                  <circle cx="12" cy="8" r="4" />
                  <path d="M4 21c1-4.5 4.5-6.5 8-6.5s7 2 8 6.5" />
                </svg>
              </div>
            )}
            <button
              type="button"
              aria-label={t("profile.addPicture")}
              onClick={() => fileInput.current?.click()}
              className="absolute -right-0.5 -bottom-0.5 flex size-11 items-center justify-center rounded-full border-[3px] border-canvas bg-brand text-white"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M4 8h3l2-3h6l2 3h3v11H4z" />
                <circle cx="12" cy="13" r="3.5" />
              </svg>
            </button>
            <input
              ref={fileInput}
              type="file"
              accept="image/*"
              hidden
              onChange={(e) => {
                pickPicture(e.target.files?.[0]);
                e.target.value = "";
              }}
            />
          </div>
          {picture ? (
            <button type="button" onClick={() => setPicture(undefined)} className="h-8 text-[13px] font-semibold text-brand-fg">
              {t("profile.removePicture")}
            </button>
          ) : (
            <span className="text-[13px] text-muted">{t("profile.pictureOptional")}</span>
          )}
        </div>

        <div className="flex flex-col gap-1.5">
          <label htmlFor="profile-name" className="text-sm font-semibold">
            {t("common.name")}
          </label>
          <input
            id="profile-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={60}
            autoComplete="nickname"
            className="h-12 rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none"
          />
          <span className="text-xs text-muted">{t("profile.nameHint")}</span>
        </div>

        {!editing && (
          <>
            <div className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
              <div className="flex gap-3">
                <span className="flex size-9 shrink-0 items-center justify-center rounded-[10px] bg-brand-tint text-brand-tint-ink">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <circle cx="8" cy="15" r="4" />
                    <path d="M11 12l9-9M17 6l3 3M15 8l2 2" />
                  </svg>
                </span>
                <div className="flex flex-col gap-1">
                  <span className="text-[15px] font-semibold">{t("profile.keyCreatedTitle")}</span>
                  <span className="text-[13px] leading-snug text-muted">{t("profile.keyCreatedText")}</span>
                </div>
              </div>
              <p className="rounded-[10px] bg-warn-tint px-3 py-2.5 text-[13px] leading-snug text-warn-ink">{t("profile.backupWarning")}</p>
            </div>
            <p className="text-[13px] leading-snug text-muted">{t("profile.publicNote")}</p>
          </>
        )}

        <button
          type="submit"
          disabled={saving || name.trim() === ""}
          className="mt-auto h-[54px] rounded-2xl bg-brand text-base font-semibold text-white disabled:opacity-50"
        >
          {saving ? t("common.saving") : editing ? t("profile.save") : t("profile.create")}
        </button>
      </form>
    </main>
  );
}

export default CreateProfileView;
