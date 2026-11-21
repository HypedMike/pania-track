import { useEffect, useMemo, useState, type FormEvent } from "react";
import { currentLocale, useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { computeStats, formatClock, formatDistance, formatElevation } from "../../../shared/gps/trail_stats";
import ActivityPicker from "../components/activity_picker";
import type { TrailActivity } from "../interfaces/trail";
import StatTile from "../components/stat_tile";
import TrailMap from "../components/trail_map";
import { useRecordingStore } from "../stores/recording_store";
import { useTrailStore } from "../stores/trail_store";

const FIELD =
  "rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none";

function SaveRecordingView() {
  const t = useT();
  const { goTo } = useNavigation();
  const { status, points, waypoints, startedAt, elapsedMs, resume, discard } = useRecordingStore();
  const createTrail = useTrailStore((state) => state.createTrail);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [activity, setActivity] = useState<TrailActivity>("foot");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const stats = useMemo(() => computeStats(points), [points]);

  // Nothing to save when opened without a recording (e.g. after a reload).
  useEffect(() => {
    if (status === "idle") goTo(ROUTES.home, { replace: true });
  }, [status, goTo]);

  if (status === "idle") return null;

  const fmt = (ms: number) => new Date(ms).toLocaleTimeString(currentLocale(), { hour: "2-digit", minute: "2-digit" });

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (points.length === 0) {
      setError(t("save.noPoints"));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const trail = await createTrail({ name, description, source: "recorded", activity, coordinates: points, waypoints });
      // Leave first: clearing the session while still here would trigger the redirect home.
      goTo(trailDetailPath(trail.id), { replace: true });
      void discard();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setSaving(false);
    }
  }

  async function handleResume() {
    await resume();
    goTo(ROUTES.record, { replace: true });
  }

  async function handleDiscard() {
    if (!window.confirm(t("save.confirmDiscard"))) return;
    goTo(ROUTES.home, { replace: true });
    void discard();
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col px-5 pt-[calc(1.75rem+var(--safe-top))] pb-6">
      <form onSubmit={handleSubmit} className="flex flex-1 flex-col gap-4">
        <header className="flex flex-col gap-1">
          <h1 className="font-display text-[28px] font-bold">{t("save.title")}</h1>
          {startedAt && (
            <p className="text-sm text-muted">
              {t("save.today", { from: fmt(startedAt), to: fmt(Date.now()) })}
            </p>
          )}
        </header>

        {points.length > 0 && (
          <div className="h-40 overflow-hidden rounded-2xl">
            <TrailMap coordinates={points} waypoints={waypoints} color="recorded" />
          </div>
        )}

        <div className="grid grid-cols-2 gap-2">
          <StatTile label={t("common.distance")} value={formatDistance(stats.distanceM)} />
          <StatTile label={t("save.movingTime")} value={formatClock(elapsedMs()).replace(/^00:/, "")} />
          <StatTile label={t("common.elevationGain")} value={formatElevation(stats.elevationGainM, true)} />
          <StatTile label={t("save.points")} value={String(points.length)} />
        </div>

        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold">{t("common.name")}</span>
          <input
            required
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t("save.namePlaceholder")}
            className={`${FIELD} h-12`}
          />
        </label>

        <ActivityPicker value={activity} onChange={setActivity} />

        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold">{t("common.description")}</span>
          <textarea
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder={t("common.notesPlaceholder")}
            className={`${FIELD} resize-none py-3 text-[15px]`}
          />
        </label>

        {error && <p className="text-sm text-danger">{error}</p>}

        <div className="mt-auto flex flex-col gap-2">
          <div className="grid grid-cols-2 gap-3">
            <button type="button" onClick={() => void handleResume()} className="h-[54px] rounded-2xl border border-line-strong bg-surface text-base font-semibold">
              {t("common.resume")}
            </button>
            <button
              type="submit"
              disabled={saving || name.trim() === ""}
              className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
            >
              {saving ? t("common.saving") : t("common.saveTrail")}
            </button>
          </div>
          <button type="button" onClick={() => void handleDiscard()} className="h-11 text-[15px] font-semibold text-red-700">
            {t("save.discard")}
          </button>
        </div>
      </form>
    </main>
  );
}

export default SaveRecordingView;
