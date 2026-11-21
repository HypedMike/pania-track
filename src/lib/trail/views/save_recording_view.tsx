import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { computeStats, formatClock, formatDistance, formatElevation } from "../../../shared/gps/trail_stats";
import StatTile from "../components/stat_tile";
import TrailMap from "../components/trail_map";
import { useRecordingStore } from "../stores/recording_store";
import { useTrailStore } from "../stores/trail_store";

const FIELD =
  "rounded-xl border border-line-strong bg-surface px-3.5 text-base text-ink focus:border-2 focus:border-brand-fg focus:outline-none";

function SaveRecordingView() {
  const { goTo } = useNavigation();
  const { status, points, waypoints, startedAt, elapsedMs, resume, discard } = useRecordingStore();
  const createTrail = useTrailStore((state) => state.createTrail);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const stats = useMemo(() => computeStats(points), [points]);

  // Nothing to save when opened without a recording (e.g. after a reload).
  useEffect(() => {
    if (status === "idle") goTo(ROUTES.home, { replace: true });
  }, [status, goTo]);

  if (status === "idle") return null;

  const fmt = (ms: number) => new Date(ms).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (points.length === 0) {
      setError("No GPS points were recorded yet. Resume recording, or discard it.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const trail = await createTrail({ name, description, source: "recorded", coordinates: points, waypoints });
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
    if (!window.confirm("Discard this recording? The track will be lost.")) return;
    goTo(ROUTES.home, { replace: true });
    void discard();
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col px-5 pt-7 pb-6">
      <form onSubmit={handleSubmit} className="flex flex-1 flex-col gap-4">
        <header className="flex flex-col gap-1">
          <h1 className="font-display text-[28px] font-bold">Save recording</h1>
          {startedAt && (
            <p className="text-sm text-muted">
              Today · {fmt(startedAt)} – {fmt(Date.now())}
            </p>
          )}
        </header>

        {points.length > 0 && (
          <div className="h-40 overflow-hidden rounded-2xl">
            <TrailMap coordinates={points} waypoints={waypoints} color="recorded" />
          </div>
        )}

        <div className="grid grid-cols-2 gap-2">
          <StatTile label="Distance" value={formatDistance(stats.distanceM)} />
          <StatTile label="Moving time" value={formatClock(elapsedMs()).replace(/^00:/, "")} />
          <StatTile label="Elevation gain" value={formatElevation(stats.elevationGainM, true)} />
          <StatTile label="Points" value={String(points.length)} />
        </div>

        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold">Name</span>
          <input
            required
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Morning loop on the walls"
            className={`${FIELD} h-12`}
          />
        </label>

        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold">Description</span>
          <textarea
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Notes about this trail (optional)"
            className={`${FIELD} resize-none py-3 text-[15px]`}
          />
        </label>

        {error && <p className="text-sm text-danger">{error}</p>}

        <div className="mt-auto flex flex-col gap-2">
          <div className="grid grid-cols-2 gap-3">
            <button type="button" onClick={() => void handleResume()} className="h-[54px] rounded-2xl border border-line-strong bg-surface text-base font-semibold">
              Resume
            </button>
            <button
              type="submit"
              disabled={saving || name.trim() === ""}
              className="h-[54px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
            >
              {saving ? "Saving…" : "Save trail"}
            </button>
          </div>
          <button type="button" onClick={() => void handleDiscard()} className="h-11 text-[15px] font-semibold text-red-700">
            Discard recording
          </button>
        </div>
      </form>
    </main>
  );
}

export default SaveRecordingView;
