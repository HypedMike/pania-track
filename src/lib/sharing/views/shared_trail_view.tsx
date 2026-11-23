import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router";
import { toast } from "sonner";
import { computeStats, formatDistance, formatElevation } from "../../../shared/gps/trail_stats";
import { useT } from "../../../shared/i18n/i18n";
import { trailDetailPath } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import ElevationProfile from "../../trail/components/elevation_profile";
import TrailMap from "../../trail/components/trail_map";
import { useTrailStore } from "../../trail/stores/trail_store";
import { shortNpub } from "../../profile/nostr";
import DifficultyBadge from "../components/difficulty_badge";
import { errorText, type SharedTrail } from "../sharing_api";
import { useExploreStore } from "../stores/explore_store";

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-xs text-muted">{label}</span>
      <span className="font-display text-[17px] font-semibold">{value}</span>
    </div>
  );
}

function Fidelity({ trail }: { trail: SharedTrail }) {
  const t = useT();
  const f = trail.fidelity;
  const reported = f.points !== null && f.originalPoints !== null && f.removedPct !== null && f.maxErrorM !== null;
  return (
    <section className="flex flex-col gap-1 rounded-2xl border border-line bg-surface p-4">
      <h2 className="text-sm font-semibold">{t("shared.fidelityTitle")}</h2>
      <p className="text-[13px] leading-snug text-muted">
        {reported
          ? t("shared.fidelityText", {
              kept: f.points!,
              total: f.originalPoints!,
              removed: f.removedPct!,
              max: f.maxErrorM!,
              p95: f.p95ErrorM ?? f.maxErrorM!,
            })
          : t("shared.fidelityNone")}
      </p>
    </section>
  );
}

/** A trail shared by someone else, with the button that saves a copy to this device. */
function SharedTrailView() {
  const t = useT();
  const { eventId = "" } = useParams();
  const { goTo, goBack } = useNavigation();
  const trail = useExploreStore((s) => s.results.find((r) => r.eventId === eventId));
  const { trails, load, createTrail, updateTrail } = useTrailStore();
  const [saving, setSaving] = useState(false);
  const stats = useMemo(() => computeStats(trail?.coordinates ?? []), [trail?.coordinates]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!trail) {
    return (
      <main className="mx-auto max-w-2xl">
        <PageHeader onBack={goBack} backLabel={t("shared.back")} />
        <p className="px-5 pt-4 text-muted">{t("shared.notFound")}</p>
      </main>
    );
  }

  // The same original (author + trail id), possibly saved from an older version of it.
  const saved = trails.find((x) => x.author?.pubkey === trail.authorPubkey && x.author.dTag === trail.dTag);
  const upToDate = saved?.author?.eventId === trail.eventId;

  async function bookmark() {
    if (!trail) return;
    setSaving(true);
    try {
      const author = {
        pubkey: trail.authorPubkey,
        npub: trail.authorNpub,
        ...(trail.authorName && { name: trail.authorName }),
        dTag: trail.dTag,
        eventId: trail.eventId,
      };
      const fields = {
        name: trail.name,
        description: trail.description,
        activity: trail.activity,
        coordinates: trail.coordinates,
        waypoints: trail.waypoints,
        author,
      };
      if (saved) await updateTrail(saved.id, fields);
      else await createTrail({ ...fields, source: "bookmarked" });
      toast.success(t("shared.savedToast"));
    } catch (e) {
      toast.error(errorText(e));
    } finally {
      setSaving(false);
    }
  }

  async function copyNpub() {
    try {
      await navigator.clipboard.writeText(trail!.authorNpub);
      toast.success(t("profile.copied"));
    } catch {
      toast.error(t("profile.copyFailed"));
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader onBack={goBack} backLabel={t("shared.back")} />
      <div className="flex flex-1 flex-col gap-3.5 px-5 pt-4 pb-6">
        <header className="flex flex-col gap-2">
          <h1 className="font-display text-[28px] leading-tight font-bold tracking-tight">{trail.name}</h1>
          <div className="flex flex-wrap items-center gap-2">
            <DifficultyBadge difficulty={trail.difficulty} />
            <span className="rounded-md bg-canvas px-2 py-0.5 text-xs font-semibold text-ink-soft">{t(`activity.${trail.activity}`)}</span>
            <span className="text-[13px] text-muted">{t("explore.away", { n: trail.awayKm.toFixed(1) })}</span>
          </div>
        </header>

        <div className="flex items-center gap-3 rounded-2xl border border-line bg-surface p-3.5">
          <div className="flex min-w-0 flex-1 flex-col gap-0.5">
            <span className="text-xs text-muted">{t("shared.author")}</span>
            <span className="truncate text-[15px] font-semibold">{trail.authorName ?? t("explore.anonymous")}</span>
            <span className="font-mono text-[13px] text-muted">{shortNpub(trail.authorNpub)}</span>
          </div>
          <button
            type="button"
            aria-label={t("profile.copyKey")}
            onClick={() => void copyNpub()}
            className="flex size-11 shrink-0 items-center justify-center rounded-full border border-line-strong"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="9" y="9" width="11" height="11" rx="2" />
              <path d="M5 15V5a1 1 0 0 1 1-1h10" />
            </svg>
          </button>
        </div>

        <div className="h-72 overflow-hidden rounded-2xl">
          <TrailMap coordinates={trail.coordinates} waypoints={trail.waypoints} />
        </div>

        <section className="grid grid-cols-3 gap-1.5 rounded-[14px] border border-line bg-surface p-3">
          <Stat label={t("common.distance")} value={formatDistance(trail.distanceM)} />
          <Stat label={t("detail.gain")} value={formatElevation(trail.gainM, true)} />
          <Stat label={t("detail.highest")} value={formatElevation(stats.highestM)} />
        </section>

        <ElevationProfile coordinates={trail.coordinates} />

        {trail.description && <p className="text-sm leading-relaxed text-ink-soft">{trail.description}</p>}

        <Fidelity trail={trail} />

        <div className="mt-auto flex flex-col gap-2 pt-2">
          {saved && upToDate ? (
            <>
              <p className="text-center text-sm font-semibold text-brand-fg">{t("shared.saved")}</p>
              <button
                type="button"
                onClick={() => goTo(trailDetailPath(saved.id))}
                className="h-[54px] rounded-2xl border border-line-strong bg-surface text-base font-semibold"
              >
                {t("shared.openSaved")}
              </button>
            </>
          ) : (
            <button
              type="button"
              onClick={() => void bookmark()}
              disabled={saving}
              className="flex h-[54px] items-center justify-center gap-2 rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M6 4h12v17l-6-4-6 4z" />
              </svg>
              {saving ? t("common.saving") : saved ? t("shared.updateSaved") : t("shared.bookmark")}
            </button>
          )}
        </div>
      </div>
    </main>
  );
}

export default SharedTrailView;
