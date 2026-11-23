import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams } from "react-router";
import { toast } from "sonner";
import {
  analysisApi,
  fromFixes,
  type CleanedTrack,
  type RouteGroup,
  type TrailAnalysis,
} from "../../../shared/analysis/analysis_api";
import { fetchTerrainElevations } from "../../../shared/gps/terrain";
import { formatDate, formatDistance, formatElevation, haversine } from "../../../shared/gps/trail_stats";
import { useT } from "../../../shared/i18n/i18n";
import { trailDetailPath } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import PageHeader from "../../../shared/ui/layout/page_header";
import TrailMap from "../../trail/components/trail_map";
import { useTrailStore } from "../../trail/stores/trail_store";
import BarChart from "../components/bar_chart";
import { BUTTON, BUTTON_PRIMARY, Card, Figure } from "../components/card";
import PaceCurve from "../components/pace_curve";
import ProfileChart from "../components/profile_chart";
import {
  formatClockTime,
  formatGrade,
  formatSeconds,
  formatSpeed,
  formatVerticalSpeed,
} from "../format";

/** Replay length: the whole trail plays in about this many seconds, however long it was. */
const REPLAY_SECONDS = 20;
const REPLAY_TICK_MS = 100;

function TrailAnalysisView() {
  const t = useT();
  const { id = "" } = useParams();
  const { goTo, goBack } = useNavigation();
  const trail = useTrailStore((s) => s.trails.find((x) => x.id === id));
  const trails = useTrailStore((s) => s.trails);
  const loading = useTrailStore((s) => s.loading);
  const load = useTrailStore((s) => s.load);
  const updateTrail = useTrailStore((s) => s.updateTrail);

  const [analysis, setAnalysis] = useState<TrailAnalysis | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [groups, setGroups] = useState<RouteGroup[]>([]);
  const [cleaned, setCleaned] = useState<CleanedTrack | null>(null);
  const [cleaning, setCleaning] = useState(false);
  const [cursor, setCursor] = useState(0);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!trail && !loading) void load();
  }, [trail, loading, load]);

  const coordinates = trail?.coordinates;
  const activity = trail?.activity;

  useEffect(() => {
    if (!coordinates || !activity) return;
    let alive = true;
    setAnalysis(null);
    setError(null);
    analysisApi
      .analyzeTrail(coordinates, activity)
      .then((a) => alive && setAnalysis(a))
      .catch((e) => alive && setError(e instanceof Error ? e.message : String(e)));
    return () => {
      alive = false;
    };
  }, [coordinates, activity]);

  // Other trails that follow the same route.
  useEffect(() => {
    if (!trail || trail.coordinates.length < 2) return;
    let alive = true;
    const candidates = trails
      .filter((x) => x.coordinates.length > 1)
      .map((x) => ({ id: x.id, activity: x.activity, coordinates: x.coordinates }));
    analysisApi
      .groupRoutes(candidates)
      .then((all) => alive && setGroups(all.filter((g) => g.members.some((m) => m.id === trail.id))))
      .catch(() => alive && setGroups([]));
    return () => {
      alive = false;
    };
  }, [trail, trails]);

  const distances = useMemo(() => {
    const out: number[] = [];
    let total = 0;
    (coordinates ?? []).forEach((c, i, all) => {
      if (i > 0) total += haversine(all[i - 1], c);
      out.push(total);
    });
    return out;
  }, [coordinates]);
  const altitudes = useMemo(() => (coordinates ?? []).map((c) => c.altitude), [coordinates]);
  const count = coordinates?.length ?? 0;

  // Replay: a timer moves the cursor along the trail.
  useEffect(() => {
    if (!playing || count < 2) return;
    const stepBy = Math.max(1, Math.round(count / ((REPLAY_SECONDS * 1000) / REPLAY_TICK_MS)));
    const timer = setInterval(() => {
      setCursor((c) => {
        if (c + stepBy >= count - 1) {
          setPlaying(false);
          return count - 1;
        }
        return c + stepBy;
      });
    }, REPLAY_TICK_MS);
    return () => clearInterval(timer);
  }, [playing, count]);

  const ownTrail = trail !== undefined && trail.source !== "bookmarked";

  const previewClean = useCallback(
    async (withTerrain: boolean) => {
      if (!trail) return;
      setCleaning(true);
      try {
        const terrain = withTerrain ? await fetchTerrainElevations(trail.coordinates) : undefined;
        setCleaned(await analysisApi.cleanTrack(trail.coordinates, trail.activity, terrain));
      } catch (e) {
        toast.error(withTerrain ? t("analysis.terrainFailed") : t("analysis.cleanFailed"), {
          description: e instanceof Error ? e.message : String(e),
        });
      } finally {
        setCleaning(false);
      }
    },
    [trail, t],
  );

  async function saveCleaned() {
    if (!trail || !cleaned) return;
    if (!window.confirm(t("analysis.confirmSaveCleaned"))) return;
    try {
      await updateTrail(trail.id, { coordinates: fromFixes(cleaned.fixes) });
      setCleaned(null);
      setCursor(0);
      toast.success(t("analysis.cleanSaved"));
    } catch (e) {
      toast.error(e instanceof Error ? e.message : String(e));
    }
  }

  function addStopAsWaypoint(i: number) {
    if (!trail || !analysis) return;
    const stop = analysis.motion.stops[i];
    const name = t("analysis.stopName", { d: formatSeconds(stop.durationS) });
    void updateTrail(trail.id, {
      waypoints: [...trail.waypoints, { latitude: stop.latitude, longitude: stop.longitude, name }],
    })
      .then(() => toast.success(t("analysis.waypointAdded")))
      .catch((e) => toast.error(e instanceof Error ? e.message : String(e)));
  }

  const back = <PageHeader onBack={goBack} backLabel={t("analysis.back")} />;
  if (!trail) {
    return (
      <main className="flex min-h-dvh flex-col bg-canvas">
        {back}
        <p className="p-6 text-center text-sm text-muted">{loading ? t("common.loading") : t("error.trailNotFound")}</p>
      </main>
    );
  }

  const motion = analysis?.motion;
  const at = Math.min(cursor, Math.max(0, count - 1));
  const here = trail.coordinates[at];
  const hereTime = here?.timestamp ? Date.parse(here.timestamp) : null;
  const startTime = trail.coordinates[0]?.timestamp ? Date.parse(trail.coordinates[0].timestamp) : null;

  return (
    <main className="flex min-h-dvh flex-col bg-canvas">
      {back}
      <div className="flex flex-col gap-3.5 px-5 pt-4 pb-8">
        <header className="flex flex-col gap-1">
          <h1 className="font-display text-[26px] leading-tight font-bold tracking-tight">{t("analysis.title")}</h1>
          <button type="button" onClick={() => goTo(trailDetailPath(trail.id))} className="text-left text-sm text-brand-fg">
            {trail.name}
          </button>
        </header>

        {error && <p className="text-sm text-danger">{error}</p>}
        {!analysis && !error && <p className="text-sm text-muted">{t("analysis.working")}</p>}

        {count > 1 && (
          <Card title={t("analysis.replay")} aside={formatDistance(distances[count - 1])}>
            <div className="h-56 overflow-hidden rounded-xl">
              <TrailMap
                coordinates={trail.coordinates}
                color={trail.source}
                completed={trail.coordinates.slice(0, at + 1)}
                current={here}
              />
            </div>
            <ProfileChart
              distances={distances}
              altitudes={altitudes}
              segments={analysis?.climbs?.segments}
              stops={motion?.stops}
              cursor={at}
              ariaLabel={t("analysis.profileAlt")}
            />
            <div className="flex items-center gap-3">
              <button
                type="button"
                className={BUTTON_PRIMARY}
                aria-label={playing ? t("analysis.pause") : t("analysis.play")}
                onClick={() => {
                  if (!playing && at >= count - 1) setCursor(0);
                  setPlaying((p) => !p);
                }}
              >
                {playing ? t("analysis.pause") : t("analysis.play")}
              </button>
              <input
                type="range"
                min={0}
                max={count - 1}
                value={at}
                aria-label={t("analysis.position")}
                onChange={(e) => {
                  setPlaying(false);
                  setCursor(Number(e.target.value));
                }}
                className="min-w-0 flex-1 accent-[var(--color-brand)]"
              />
            </div>
            <div className="grid grid-cols-3 gap-2">
              <Figure label={t("common.distance")} value={formatDistance(distances[at] ?? 0)} />
              <Figure label={t("analysis.altitude")} value={formatElevation(here?.altitude ?? null)} />
              <Figure
                label={t("analysis.elapsed")}
                value={hereTime !== null && startTime !== null ? formatSeconds((hereTime - startTime) / 1000) : "—"}
                hint={hereTime !== null ? formatClockTime(hereTime) : undefined}
              />
            </div>
          </Card>
        )}

        {motion &&
          (motion.hasTime ? (
            <Card title={t("analysis.time")}>
              <div className="grid grid-cols-3 gap-2">
                <Figure label={t("analysis.moving")} value={formatSeconds(motion.movingS)} />
                <Figure label={t("analysis.stopped")} value={formatSeconds(motion.stoppedS)} />
                <Figure label={t("analysis.paused")} value={formatSeconds(motion.pausedS)} hint={t("analysis.pausedHint")} />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <Figure label={t("analysis.movingSpeed")} value={formatSpeed(motion.avgMovingSpeedMs)} />
                <Figure label={t("analysis.adjustedSpeed")} value={formatSpeed(analysis?.adjustedSpeedMs)} hint={t("analysis.adjustedHint")} />
              </div>
              {motion.stops.length > 0 ? (
                <ul className="flex flex-col divide-y divide-line">
                  {motion.stops.map((s, i) => (
                    <li key={i} className="flex items-center justify-between gap-3 py-2">
                      <span className="flex flex-col">
                        <span className="text-sm font-semibold">
                          {formatSeconds(s.durationS)} · {formatDistance(s.alongM)}
                        </span>
                        <span className="text-xs text-muted">{s.startMs ? formatClockTime(s.startMs) : ""}</span>
                      </span>
                      {ownTrail && (
                        <button type="button" className={BUTTON} onClick={() => addStopAsWaypoint(i)}>
                          {t("analysis.addWaypoint")}
                        </button>
                      )}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-muted">{t("analysis.noStops")}</p>
              )}
            </Card>
          ) : (
            <Card title={t("analysis.time")}>
              <p className="text-sm text-muted">{t("analysis.noTimes")}</p>
            </Card>
          ))}

        {analysis && analysis.curve.legsUsed > 0 && (
          <Card title={t("analysis.pace")} aside={t("analysis.paceAxis")}>
            <PaceCurve model={analysis.curve} ariaLabel={t("analysis.paceAlt")} />
            <p className="text-xs text-muted">{t("analysis.paceLegend")}</p>
            <PaceNotes model={analysis.curve} />
          </Card>
        )}

        {analysis?.climbs && (
          <Card title={t("analysis.climbs")}>
            <div className="grid grid-cols-3 gap-2">
              <Figure label={t("detail.gain")} value={formatElevation(analysis.climbs.totalGainM, true)} />
              <Figure label={t("analysis.loss")} value={formatElevation(-analysis.climbs.totalLossM)} />
              <Figure label={t("analysis.vertSpeed")} value={formatVerticalSpeed(analysis.climbs.avgVerticalSpeedMh)} />
            </div>
            {(analysis.climbs.steepestClimbKm || analysis.climbs.steepestDescentKm) && (
              <div className="grid grid-cols-2 gap-2">
                {analysis.climbs.steepestClimbKm && (
                  <Figure
                    label={t("analysis.steepestUp")}
                    value={formatGrade(analysis.climbs.steepestClimbKm.gradePct)}
                    hint={t("analysis.atKm", { d: formatDistance(analysis.climbs.steepestClimbKm.startM) })}
                  />
                )}
                {analysis.climbs.steepestDescentKm && (
                  <Figure
                    label={t("analysis.steepestDown")}
                    value={formatGrade(analysis.climbs.steepestDescentKm.gradePct)}
                    hint={t("analysis.atKm", { d: formatDistance(analysis.climbs.steepestDescentKm.startM) })}
                  />
                )}
              </div>
            )}
            <ul className="flex flex-col divide-y divide-line">
              {analysis.climbs.segments.map((s, i) => (
                <li key={i} className="flex items-center justify-between gap-3 py-2 text-sm">
                  <span className="flex flex-col">
                    <span className="font-semibold">
                      {t(`analysis.kind.${s.kind}`)} · {formatDistance(s.distanceM)}
                    </span>
                    <span className="text-xs text-muted">
                      {formatDistance(s.startM)} → {formatDistance(s.endM)}
                      {s.durationS ? ` · ${formatSeconds(s.durationS)}` : ""}
                    </span>
                  </span>
                  <span className="text-right">
                    <span className="block font-semibold">{formatGrade(s.avgGradePct)}</span>
                    <span className="block text-xs text-muted">
                      {s.kind === "climb" && s.verticalSpeedMh ? formatVerticalSpeed(s.verticalSpeedMh) : formatElevation(s.riseM, true)}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </Card>
        )}

        {analysis?.fatigue && (
          <Card title={t("analysis.fatigue")}>
            <BarChart
              values={[analysis.fatigue.firstAdjustedMs * 3.6, analysis.fatigue.lastAdjustedMs * 3.6]}
              labels={[t("analysis.firstThird"), t("analysis.lastThird")]}
              tones={["brand", analysis.fatigue.changePct < -5 ? "bad" : "brand"]}
              height={80}
              ariaLabel={t("analysis.fatigueAlt")}
            />
            <div className="grid grid-cols-3 gap-2">
              <Figure label={t("analysis.firstThird")} value={formatSpeed(analysis.fatigue.firstSpeedMs)} />
              <Figure label={t("analysis.lastThird")} value={formatSpeed(analysis.fatigue.lastSpeedMs)} />
              <Figure label={t("analysis.change")} value={`${analysis.fatigue.changePct > 0 ? "+" : ""}${analysis.fatigue.changePct.toFixed(0)}%`} />
            </div>
            <p className="text-sm text-ink-soft">{fatigueSentence(analysis.fatigue.changePct, t)}</p>
            {!analysis.fatigue.gradeAdjusted && <p className="text-xs text-muted">{t("analysis.noAltitudeNote")}</p>}
          </Card>
        )}

        {analysis && (
          <Card title={t("analysis.quality")} aside={`${analysis.quality.score}/100`}>
            <div className="grid grid-cols-3 gap-2">
              <Figure label={t("analysis.spikes")} value={String(analysis.quality.spikes)} />
              <Figure label={t("analysis.altJumps")} value={String(analysis.quality.altitudeJumps)} />
              <Figure
                label={t("analysis.gaps")}
                value={String(analysis.quality.gaps)}
                hint={analysis.quality.gaps > 0 ? t("analysis.longest", { d: formatSeconds(analysis.quality.longestGapS) }) : undefined}
              />
            </div>
            {analysis.quality.accuracy ? (
              <div className="grid grid-cols-3 gap-2">
                <Figure label={t("analysis.accMedian")} value={`${analysis.quality.accuracy.medianM.toFixed(0)} m`} />
                <Figure label={t("analysis.accP95")} value={`${analysis.quality.accuracy.p95M.toFixed(0)} m`} />
                <Figure label={t("analysis.accPoor")} value={`${analysis.quality.accuracy.poorPct.toFixed(0)}%`} />
              </div>
            ) : (
              <p className="text-xs text-muted">{t("analysis.noAccuracy")}</p>
            )}
            <p className="text-sm text-ink-soft">
              {analysis.quality.suspicious ? t("analysis.qualityBad") : t("analysis.qualityGood")}
            </p>
            {ownTrail && !cleaned && (
              <div className="flex flex-wrap gap-2">
                <button type="button" disabled={cleaning} className={BUTTON} onClick={() => void previewClean(false)}>
                  {t("analysis.clean")}
                </button>
                {analysis.quality.withAltitudePct > 0 && (
                  <button type="button" disabled={cleaning} className={BUTTON} onClick={() => void previewClean(true)}>
                    {cleaning ? t("analysis.working") : t("analysis.terrain")}
                  </button>
                )}
              </div>
            )}
            {cleaned && (
              <div className="flex flex-col gap-2 rounded-xl border border-line bg-canvas p-3">
                <p className="text-sm">
                  {t("analysis.cleanResult", {
                    removed: cleaned.removedPoints,
                    before: formatElevation(cleaned.gainBeforeM, true),
                    after: formatElevation(cleaned.gainAfterM, true),
                  })}
                </p>
                <div className="flex gap-2">
                  <button type="button" className={BUTTON_PRIMARY} onClick={() => void saveCleaned()}>
                    {t("analysis.saveCleaned")}
                  </button>
                  <button type="button" className={BUTTON} onClick={() => setCleaned(null)}>
                    {t("common.cancel")}
                  </button>
                </div>
              </div>
            )}
          </Card>
        )}

        {groups.length > 0 && (
          <Card title={t("analysis.sameRoute")}>
            {groups.map((g, gi) => (
              <ul key={gi} className="flex flex-col divide-y divide-line">
                {[...g.members]
                  .sort((a, b) => (a.movingS ?? Infinity) - (b.movingS ?? Infinity))
                  .map((m) => {
                    const other = trails.find((x) => x.id === m.id);
                    return (
                      <li key={m.id}>
                        <button
                          type="button"
                          onClick={() => m.id !== trail.id && goTo(trailDetailPath(m.id))}
                          className={`flex min-h-11 w-full items-center justify-between gap-3 py-2 text-left ${
                            m.id === trail.id ? "font-semibold" : ""
                          }`}
                        >
                          <span className="flex min-w-0 flex-col">
                            <span className="truncate text-sm">
                              {other?.name ?? m.id}
                              {m.isBest ? ` · ${t("analysis.best")}` : ""}
                              {m.id === trail.id ? ` · ${t("analysis.thisOne")}` : ""}
                            </span>
                            <span className="text-xs text-muted">
                              {formatDate(m.startMs ?? other?.createdAt)}
                              {m.reversed ? ` · ${t("analysis.reversed")}` : ""}
                            </span>
                          </span>
                          <span className="text-right text-sm">
                            <span className="block font-semibold">{formatSeconds(m.movingS)}</span>
                            <span className="block text-xs text-muted">
                              {m.vsBestPct === null ? "" : m.isBest ? t("analysis.best") : `+${m.vsBestPct.toFixed(0)}%`}
                            </span>
                          </span>
                        </button>
                      </li>
                    );
                  })}
              </ul>
            ))}
          </Card>
        )}
      </div>
    </main>
  );
}

/** What the curve says in words: the speed on the slopes the person actually walked. */
function PaceNotes({ model }: { model: TrailAnalysis["curve"] }) {
  const t = useT();
  const at = (pct: number) => model.bins.find((b) => Math.abs(b.gradePct - pct) < 0.1);
  const rows = [
    { pct: 10, label: t("analysis.uphill") },
    { pct: 0, label: t("analysis.flat") },
    { pct: -10, label: t("analysis.downhill") },
  ].filter((r) => at(r.pct)?.measured);
  if (rows.length === 0) return null;
  return (
    <div className="grid grid-cols-3 gap-2">
      {rows.map((r) => (
        <Figure key={r.pct} label={r.label} value={formatSpeed(at(r.pct)!.speedMs)} />
      ))}
    </div>
  );
}

function fatigueSentence(changePct: number, t: ReturnType<typeof useT>): string {
  if (changePct <= -15) return t("analysis.fatigueBig", { pct: Math.abs(Math.round(changePct)) });
  if (changePct <= -5) return t("analysis.fatigueSome", { pct: Math.abs(Math.round(changePct)) });
  if (changePct >= 5) return t("analysis.fatigueFaster", { pct: Math.round(changePct) });
  return t("analysis.fatigueSteady");
}

export default TrailAnalysisView;
