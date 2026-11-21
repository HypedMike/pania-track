import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useParams } from "react-router";
import { currentLocale, plural, useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES } from "../../../shared/router/routes";
import { exportGpx, shareGpx } from "../../../shared/gps/track_files";
import {
  computeStats,
  formatDate,
  formatDistance,
  formatDuration,
  formatElevation,
} from "../../../shared/gps/trail_stats";
import PageHeader from "../../../shared/ui/layout/page_header";
import ActivityPicker from "../components/activity_picker";
import type { TrailActivity } from "../interfaces/trail";
import ElevationProfile from "../components/elevation_profile";
import TrailMap from "../components/trail_map";
import { useTrailStore } from "../stores/trail_store";

const FIELD =
  "rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none";
const ICON_BUTTON =
  "flex size-11 items-center justify-center rounded-full border border-line-strong bg-surface";

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-xs text-muted">{label}</span>
      <span className="font-display text-[17px] font-semibold">{value}</span>
    </div>
  );
}

function TrailDetailView() {
  const t = useT();
  const { id = "" } = useParams();
  const { goTo, goBack } = useNavigation();
  const trail = useTrailStore((state) => state.trails.find((t) => t.id === id));
  const loading = useTrailStore((state) => state.loading);
  const load = useTrailStore((state) => state.load);
  const updateTrail = useTrailStore((state) => state.updateTrail);
  const deleteTrail = useTrailStore((state) => state.deleteTrail);
  const stats = useMemo(
    () => computeStats(trail?.coordinates ?? []),
    [trail?.coordinates],
  );

  const [editing, setEditing] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [activity, setActivity] = useState<TrailActivity>("foot");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The store may be empty when opening this view directly.
  useEffect(() => {
    if (!trail) load();
  }, [trail, load]);

  if (!trail) {
    return (
      <main className="mx-auto max-w-2xl">
        <PageHeader onBack={goBack} backLabel={t("detail.trails")} />
        <p className="px-5 pt-4 text-muted">
          {loading ? t("common.loading") : t("detail.notFound")}
        </p>
      </main>
    );
  }

  const imported = trail.source === "imported";
  const pointCount = trail.coordinates.length;

  function startEditing() {
    if (!trail) return;
    setName(trail.name);
    setDescription(trail.description ?? "");
    setActivity(trail.activity);
    setError(null);
    setEditing(true);
  }

  async function handleSave(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await updateTrail(id, { name, description, activity });
      setEditing(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (
      !trail ||
      !window.confirm(t("detail.confirmDelete", { name: trail.name }))
    )
      return;
    try {
      await deleteTrail(id);
      goTo(ROUTES.home, { replace: true });
    } catch (e) {
      setMenuOpen(false);
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col">
      <PageHeader
        onBack={goBack}
        backLabel={t("detail.trails")}
        action={
          <>
            <div className="flex gap-2">
              <button
                type="button"
                aria-label={t("detail.share")}
                onClick={() => void shareGpx(trail)}
                className={ICON_BUTTON}
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M12 3v12M7 8l5-5 5 5" />
                  <path d="M5 13v6a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-6" />
                </svg>
              </button>
              <button
                type="button"
                aria-label={t("detail.more")}
                aria-expanded={menuOpen}
                onClick={() => setMenuOpen((o) => !o)}
                className={ICON_BUTTON}
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <circle cx="5" cy="12" r="2" />
                  <circle cx="12" cy="12" r="2" />
                  <circle cx="19" cy="12" r="2" />
                </svg>
              </button>
            </div>
            {menuOpen && (
              <div className="absolute top-12 right-0 z-[1000] min-w-44 rounded-xl border border-line bg-surface p-1 shadow-lg">
                <button
                  type="button"
                  onClick={() => void handleDelete()}
                  className="h-11 w-full rounded-lg px-3 text-left text-[15px] font-semibold text-red-700 active:bg-canvas"
                >
                  {t("detail.delete")}
                </button>
              </div>
            )}
          </>
        }
      />

      <div className="flex flex-1 flex-col gap-3.5 px-5 pt-4 pb-6">
        {editing ? (
          <form onSubmit={handleSave} className="flex flex-col gap-3.5">
            <label className="flex flex-col gap-1.5">
              <span className="text-sm font-semibold">{t("common.name")}</span>
              <input
                required
                autoFocus
                value={name}
                onChange={(e) => setName(e.target.value)}
                className={`${FIELD} h-12`}
              />
            </label>
            <ActivityPicker value={activity} onChange={setActivity} />
            <label className="flex flex-col gap-1.5">
              <span className="text-sm font-semibold">
                {t("common.description")}
              </span>
              <textarea
                rows={3}
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                className={`${FIELD} resize-none py-3 text-[15px]`}
              />
            </label>
            {error && <p className="text-sm text-danger">{error}</p>}
            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setEditing(false)}
                className="h-[54px] rounded-2xl border border-line-strong bg-surface text-base font-semibold"
              >
                {t("common.cancel")}
              </button>
              <button
                type="submit"
                disabled={saving || name.trim() === ""}
                className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
              >
                {saving ? t("common.saving") : t("detail.save")}
              </button>
            </div>
          </form>
        ) : (
          <header className="flex flex-col gap-2">
            <h1 className="font-display text-[28px] leading-tight font-bold tracking-tight">
              {trail.name}
            </h1>
            <div className="flex flex-wrap items-center gap-2 text-[13px] text-muted">
              <span
                className={`rounded-md px-2 py-0.5 text-xs font-semibold ${
                  imported
                    ? "bg-route-tint text-route-ink"
                    : "bg-brand-tint text-brand-tint-ink"
                }`}
              >
                {imported
                  ? t("trail.sourceImported")
                  : t("trail.sourceRecorded")}
              </span>
              <span className="rounded-md bg-canvas px-2 py-0.5 text-xs font-semibold text-ink-soft">
                {t(`activity.${trail.activity}`)}
              </span>
              <span>
                {t("detail.pointsLine", {
                  date: formatDate(trail.createdAt),
                  points: t("common.pointsCount", {
                    n: pointCount.toLocaleString(currentLocale()),
                  }),
                })}
                {trail.waypoints.length > 0 &&
                  ` · ${plural("common.waypoint", trail.waypoints.length, t)}`}
              </span>
            </div>
          </header>
        )}

        {pointCount > 0 && (
          <div className="h-72 overflow-hidden rounded-2xl">
            <TrailMap
              coordinates={trail.coordinates}
              waypoints={trail.waypoints}
              color={trail.source}
            />
          </div>
        )}

        {pointCount > 1 && (
          <section className="grid grid-cols-4 gap-1.5 rounded-[14px] border border-line bg-surface p-3">
            <Stat
              label={t("common.distance")}
              value={formatDistance(stats.distanceM)}
            />
            <Stat
              label={t("detail.gain")}
              value={formatElevation(stats.elevationGainM, true)}
            />
            <Stat
              label={t("detail.highest")}
              value={formatElevation(stats.highestM)}
            />
            <Stat
              label={t("common.duration")}
              value={formatDuration(stats.durationMs)}
            />
          </section>
        )}

        <ElevationProfile coordinates={trail.coordinates} />

        {!editing && trail.description && (
          <p className="text-sm leading-relaxed text-ink-soft">
            {trail.description}
          </p>
        )}

        {!editing && error && <p className="text-sm text-danger">{error}</p>}

        {!editing && (
          <div className="mt-auto grid grid-cols-[1fr_2fr] gap-3 pt-2">
            <button
              type="button"
              onClick={startEditing}
              className="h-[54px] rounded-2xl border border-line-strong bg-surface text-base font-semibold"
            >
              {t("detail.edit")}
            </button>
            <button
              type="button"
              onClick={() => exportGpx(trail)}
              disabled={pointCount === 0}
              className="flex h-[54px] items-center justify-center gap-2 rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
            >
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <path d="M12 4v11M7 10l5 5 5-5" />
                <path d="M5 20h14" />
              </svg>
              {t("detail.exportGpx")}
            </button>
          </div>
        )}
      </div>
    </main>
  );
}

export default TrailDetailView;
