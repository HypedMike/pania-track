import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useT } from "../../../shared/i18n/i18n";
import { useProfileStore } from "../profile_store";

/** Shows the secret key once the user asks for it, so they can write it down. */
function BackupKeyDialog({ onClose }: { onClose: () => void }) {
  const t = useT();
  const revealSecretKey = useProfileStore((s) => s.revealSecretKey);
  const markBackedUp = useProfileStore((s) => s.markBackedUp);
  const [nsec, setNsec] = useState<string | null | undefined>(undefined);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    let cancelled = false;
    revealSecretKey()
      .then((key) => !cancelled && setNsec(key))
      .catch(() => !cancelled && setNsec(null));
    return () => {
      cancelled = true;
    };
  }, [revealSecretKey]);

  async function copy() {
    if (!nsec) return;
    try {
      await navigator.clipboard.writeText(nsec);
      toast.success(t("profile.copied"));
    } catch {
      toast.error(t("profile.copyFailed"));
    }
  }

  return (
    <div className="fixed inset-0 z-[3000] flex items-end bg-black/50" onClick={onClose}>
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="backup-title"
        onClick={(e) => e.stopPropagation()}
        className="mx-auto flex w-full max-w-2xl flex-col gap-4 rounded-t-[28px] bg-surface px-5 pt-6 pb-[calc(24px+env(safe-area-inset-bottom))]"
      >
        <div className="flex flex-col gap-1">
          <h2 id="backup-title" className="font-display text-xl font-semibold">
            {t("profile.backupTitle")}
          </h2>
          <p className="text-sm text-muted">{t("profile.backupText")}</p>
        </div>

        {nsec === null && <p className="rounded-xl bg-warn-tint p-3 text-sm text-warn-ink">{t("profile.keyMissing")}</p>}

        {nsec && (
          <>
            <code
              className={`rounded-xl border border-line bg-canvas p-3 font-mono text-[13px] leading-relaxed break-all ${
                shown ? "" : "blur-sm select-none"
              }`}
              aria-hidden={!shown}
            >
              {nsec}
            </code>
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setShown((v) => !v)}
                className="h-12 rounded-xl border border-line-strong text-[15px] font-semibold"
              >
                {shown ? t("profile.hide") : t("profile.reveal")}
              </button>
              <button
                type="button"
                onClick={copy}
                disabled={!shown}
                className="h-12 rounded-xl border border-line-strong text-[15px] font-semibold disabled:opacity-40"
              >
                {t("profile.copySecret")}
              </button>
            </div>
            <button
              type="button"
              onClick={() => {
                markBackedUp();
                onClose();
              }}
              className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white"
            >
              {t("profile.backupConfirm")}
            </button>
          </>
        )}

        <button type="button" onClick={onClose} className="h-11 text-[15px] font-semibold text-brand-fg">
          {t("profile.close")}
        </button>
      </section>
    </div>
  );
}

export default BackupKeyDialog;
