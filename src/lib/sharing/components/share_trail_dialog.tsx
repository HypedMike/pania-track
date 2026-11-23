import { useState } from "react";
import { toast } from "sonner";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import { useProfileStore } from "../../profile/profile_store";
import type { Trail } from "../../trail/interfaces/trail";
import { useTrailStore } from "../../trail/stores/trail_store";
import { errorText, sharingApi, type ShareResult } from "../sharing_api";

type Step = "confirm" | "sharing" | "done" | "failed" | "stopping";

/** Asks before publishing a trail, then publishes it (or updates / stops a shared one). */
function ShareTrailDialog({ trail, onClose }: { trail: Trail; onClose: () => void }) {
  const t = useT();
  const { goTo } = useNavigation();
  const profile = useProfileStore((s) => s.profile);
  const updateTrail = useTrailStore((s) => s.updateTrail);
  const [step, setStep] = useState<Step>("confirm");
  const [result, setResult] = useState<ShareResult | null>(null);
  const [error, setError] = useState("");
  const alreadyShared = trail.sharedAt !== undefined;
  const busy = step === "sharing" || step === "stopping";

  async function share() {
    setStep("sharing");
    try {
      const shared = await sharingApi.shareTrail(trail, profile?.name);
      await updateTrail(trail.id, { sharedAt: Date.now(), sharedEventId: shared.eventId });
      setResult(shared);
      setStep("done");
    } catch (e) {
      setError(errorText(e));
      setStep("failed");
    }
  }

  async function stop() {
    setStep("stopping");
    try {
      await sharingApi.unshareTrail(trail.id);
      await updateTrail(trail.id, { sharedAt: undefined, sharedEventId: undefined });
      toast.success(t("share.stopped"));
      onClose();
    } catch (e) {
      setError(errorText(e));
      setStep("failed");
    }
  }

  const point = (text: string) => (
    <li className="flex gap-2.5 text-sm leading-snug text-ink-soft">
      <span aria-hidden="true" className="mt-1.5 size-1.5 shrink-0 rounded-full bg-brand-fg" />
      {text}
    </li>
  );

  return (
    <div className="fixed inset-0 z-[3000] flex items-end bg-black/50" onClick={busy ? undefined : onClose}>
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="share-title"
        onClick={(e) => e.stopPropagation()}
        className="mx-auto flex max-h-[90dvh] w-full max-w-2xl flex-col gap-4 overflow-y-auto rounded-t-[28px] bg-surface px-5 pt-6 pb-[calc(24px+env(safe-area-inset-bottom))]"
      >
        {!profile ? (
          <>
            <h2 id="share-title" className="font-display text-xl font-semibold">
              {t("share.needProfile")}
            </h2>
            <p className="text-sm text-muted">{t("share.needProfileHint")}</p>
            <button type="button" onClick={() => goTo(ROUTES.profileCreate)} className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white">
              {t("share.createProfile")}
            </button>
            <button type="button" onClick={onClose} className="h-11 text-[15px] font-semibold text-brand-fg">
              {t("common.cancel")}
            </button>
          </>
        ) : step === "done" && result ? (
          <>
            <h2 id="share-title" className="font-display text-xl font-semibold">
              {t("share.done")}
            </h2>
            <ul className="flex flex-col gap-2">
              {point(t("share.doneRelays", { ok: result.relaysOk.length, total: result.relaysOk.length + result.relaysFailed.length }))}
              {point(
                t("share.doneCompression", {
                  kept: result.report.keptPoints,
                  total: result.report.originalPoints,
                  removed: result.report.removedPct,
                  err: result.report.maxErrorM,
                }),
              )}
            </ul>
            <button type="button" onClick={onClose} className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white">
              {t("share.close")}
            </button>
          </>
        ) : step === "failed" ? (
          <>
            <h2 id="share-title" className="font-display text-xl font-semibold">
              {t("share.failed")}
            </h2>
            <p className="rounded-xl bg-warn-tint p-3 text-sm text-warn-ink">{error}</p>
            <button type="button" onClick={() => setStep("confirm")} className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white">
              {t("share.retry")}
            </button>
            <button type="button" onClick={onClose} className="h-11 text-[15px] font-semibold text-brand-fg">
              {t("common.cancel")}
            </button>
          </>
        ) : (
          <>
            <h2 id="share-title" className="font-display text-xl font-semibold">
              {alreadyShared ? t("share.confirmUpdateTitle") : t("share.confirmTitle")}
            </h2>
            <ul className="flex flex-col gap-2.5">
              {point(t("share.pointAnyone"))}
              {point(t("share.pointStart"))}
              {point(t("share.pointIdentity", { name: profile.name }))}
              {point(t("share.pointRelays"))}
              {point(t("share.pointSimplified"))}
            </ul>
            <div className="grid grid-cols-2 gap-3">
              <button type="button" onClick={onClose} disabled={busy} className="h-[54px] rounded-2xl border border-line-strong bg-surface text-base font-semibold disabled:opacity-50">
                {t("common.cancel")}
              </button>
              <button type="button" onClick={() => void share()} disabled={busy} className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white disabled:opacity-50">
                {step === "sharing" ? t("share.sharing") : alreadyShared ? t("share.confirmUpdate") : t("share.confirm")}
              </button>
            </div>
            {alreadyShared && (
              <div className="flex flex-col gap-1 border-t border-line pt-3">
                <button type="button" onClick={() => void stop()} disabled={busy} className="h-11 self-start text-[15px] font-semibold text-danger disabled:opacity-50">
                  {step === "stopping" ? t("share.sharing") : t("share.stop")}
                </button>
                <p className="text-xs text-muted">{t("share.stopHint")}</p>
              </div>
            )}
          </>
        )}
      </section>
    </div>
  );
}

export default ShareTrailDialog;
