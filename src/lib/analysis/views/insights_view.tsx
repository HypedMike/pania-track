import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { analysisApi, type Heatmap, type Patterns } from "../../../shared/analysis/analysis_api";
import { formatDistance } from "../../../shared/gps/trail_stats";
import { currentLocale, plural, useT } from "../../../shared/i18n/i18n";
import { useNavigation } from "../../../shared/router/use_navigation";
import { fetchWalkWeather, type WalkWeather } from "../../../shared/weather/history";
import PageHeader from "../../../shared/ui/layout/page_header";
import type { Trail } from "../../trail/interfaces/trail";
import { useTrailStore } from "../../trail/stores/trail_store";
import BarChart from "../components/bar_chart";
import { BUTTON, Card, Figure } from "../components/card";
import HeatmapMap from "../components/heatmap_map";
import { formatSpeed, monthNames, weekdayNames } from "../format";

/** The weather is looked up for this many of the most recent trails with times. */
const WEATHER_TRAILS = 60;

/** Trails the person walked themselves: recorded or imported, not planned or other people's. */
function walked(trails: Trail[]): Trail[] {
  return trails.filter((t) => (t.source === "recorded" || t.source === "imported") && t.coordinates.length > 1);
}

const hasTimes = (t: Trail) => t.coordinates.some((c) => c.timestamp);

function hourLabel(h: number): string {
  return new Date(2024, 0, 1, h).toLocaleTimeString(currentLocale(), { hour: "2-digit", minute: "2-digit" });
}

function InsightsView() {
  const t = useT();
  const { goBack } = useNavigation();
  const trails = useTrailStore((s) => s.trails);
  const loading = useTrailStore((s) => s.loading);
  const load = useTrailStore((s) => s.load);
  const mine = useMemo(() => walked(trails), [trails]);

  const [heatmap, setHeatmap] = useState<Heatmap | null>(null);
  const [patterns, setPatterns] = useState<Patterns | null>(null);
  const [weather, setWeather] = useState<Map<string, WalkWeather>>(new Map());
  const [lookup, setLookup] = useState<{ done: number; total: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const cancelled = useRef(false);

  useEffect(() => {
    if (trails.length === 0 && !loading) void load();
  }, [trails.length, loading, load]);
  useEffect(() => () => void (cancelled.current = true), []);

  useEffect(() => {
    if (mine.length === 0) return;
    let alive = true;
    const input = mine.map((x) => ({ id: x.id, activity: x.activity, coordinates: x.coordinates }));
    analysisApi
      .heatmap(input)
      .then((h) => alive && setHeatmap(h))
      .catch((e) => alive && setError(e instanceof Error ? e.message : String(e)));
    return () => {
      alive = false;
    };
  }, [mine]);

  useEffect(() => {
    const timed = mine.filter(hasTimes);
    if (timed.length === 0) return;
    let alive = true;
    analysisApi
      .patterns(timed.map((x) => ({ id: x.id, activity: x.activity, coordinates: x.coordinates, weather: weather.get(x.id) ?? null })))
      .then((p) => alive && setPatterns(p))
      .catch((e) => alive && setError(e instanceof Error ? e.message : String(e)));
    return () => {
      alive = false;
    };
  }, [mine, weather]);

  async function lookUpWeather() {
    const timed = mine.filter(hasTimes).sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0)).slice(0, WEATHER_TRAILS);
    setLookup({ done: 0, total: timed.length });
    const found = new Map(weather);
    let failures = 0;
    for (const [i, trail] of timed.entries()) {
      if (cancelled.current) return;
      try {
        const w = await fetchWalkWeather(trail.id, trail.coordinates);
        if (w) found.set(trail.id, w);
      } catch {
        failures++;
        if (failures >= 3) break; // offline, or the service is down: stop asking
      }
      setLookup({ done: i + 1, total: timed.length });
    }
    setWeather(found);
    setLookup(null);
    if (failures >= 3) toast.error(t("insights.weatherFailed"));
  }

  const months = monthNames();
  const weekdays = weekdayNames();
  const timedCount = mine.filter(hasTimes).length;

  return (
    <main className="flex min-h-dvh flex-col bg-canvas">
      <PageHeader onBack={goBack} backLabel={t("stats.title")} />
      <div className="flex flex-col gap-3.5 px-5 pt-4 pb-8">
        <h1 className="font-display text-[26px] leading-tight font-bold tracking-tight">{t("insights.title")}</h1>
        {error && <p className="text-sm text-danger">{error}</p>}
        {mine.length === 0 && !loading && <p className="text-sm text-muted">{t("insights.empty")}</p>}

        {heatmap && heatmap.cells.length > 0 && (
          <Card title={t("insights.heatmap")} aside={plural("common.trail", heatmap.trails, t)}>
            <div className="h-72 overflow-hidden rounded-xl">
              <HeatmapMap heatmap={heatmap} />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Figure label={t("insights.explored")} value={`${heatmap.exploredKm2.toFixed(1)} km²`} hint={t("insights.cellHint", { m: heatmap.cellM })} />
              <Figure label={t("insights.mostVisited")} value={t("insights.times", { n: heatmap.maxCount })} />
            </div>
            <p className="text-xs text-muted">{t("insights.heatmapHint")}</p>
          </Card>
        )}

        {patterns && patterns.trails > 0 && (
          <>
            <Card title={t("insights.hours")} aside={plural("common.trail", patterns.trails, t)}>
              <BarChart
                values={patterns.byHour.map((b) => b.trails)}
                labels={patterns.byHour.map((_, h) => String(h))}
                labelEvery={3}
                highlight={patterns.busiestHour}
                height={96}
                ariaLabel={t("insights.hoursAlt")}
              />
              <div className="grid grid-cols-2 gap-2">
                {patterns.busiestHour !== null && <Figure label={t("insights.busiestHour")} value={hourLabel(patterns.busiestHour)} />}
                {patterns.fastestHour !== null && (
                  <Figure
                    label={t("insights.fastestHour")}
                    value={hourLabel(patterns.fastestHour)}
                    hint={formatSpeed(patterns.byHour[patterns.fastestHour].adjustedSpeedMs)}
                  />
                )}
              </div>
            </Card>

            <Card title={t("insights.weekdays")}>
              <BarChart
                values={patterns.byWeekday.map((b) => b.trails)}
                labels={weekdays}
                height={90}
                ariaLabel={t("insights.weekdaysAlt")}
              />
            </Card>

            <Card title={t("insights.months")}>
              <BarChart
                values={patterns.byMonth.map((b) => b.distanceM / 1000)}
                labels={months}
                labelEvery={1}
                highlight={patterns.busiestMonth}
                height={96}
                ariaLabel={t("insights.monthsAlt")}
              />
              <div className="grid grid-cols-2 gap-2">
                {patterns.busiestMonth !== null && (
                  <Figure
                    label={t("insights.busiestMonth")}
                    value={months[patterns.busiestMonth]}
                    hint={formatDistance(patterns.byMonth[patterns.busiestMonth].distanceM)}
                  />
                )}
                {patterns.fastestMonth !== null && (
                  <Figure
                    label={t("insights.fastestMonth")}
                    value={months[patterns.fastestMonth]}
                    hint={formatSpeed(patterns.byMonth[patterns.fastestMonth].adjustedSpeedMs)}
                  />
                )}
              </div>
            </Card>

            <Card title={t("insights.weather")}>
              {patterns.weather ? (
                <>
                  <BarChart
                    values={patterns.weather.bands.map((b) => (b.adjustedSpeedMs ?? 0) * 3.6)}
                    labels={patterns.weather.bands.map((b) =>
                      b.fromC === null ? `<${b.toC}°` : b.toC === null ? `≥${b.fromC}°` : `${b.fromC}–${b.toC}°`,
                    )}
                    height={90}
                    ariaLabel={t("insights.weatherAlt")}
                  />
                  <p className="text-sm text-ink-soft">{weatherSentence(patterns, t)}</p>
                  <p className="text-xs text-muted">{t("insights.weatherBasis", { n: patterns.weather.trails })}</p>
                </>
              ) : (
                <p className="text-sm text-muted">{t("insights.weatherIntro")}</p>
              )}
              <button type="button" className={BUTTON} disabled={lookup !== null || timedCount === 0} onClick={() => void lookUpWeather()}>
                {lookup ? t("insights.lookingUp", { done: lookup.done, total: lookup.total }) : t("insights.lookUp")}
              </button>
              <p className="text-xs text-muted">{t("insights.weatherPrivacy")}</p>
            </Card>
          </>
        )}

        {mine.length > 0 && timedCount === 0 && <p className="text-sm text-muted">{t("insights.noTimes")}</p>}
      </div>
    </main>
  );
}

function weatherSentence(p: Patterns, t: ReturnType<typeof useT>): string {
  const w = p.weather;
  if (!w) return "";
  const parts: string[] = [];
  if (w.tempCorrelation !== null) {
    if (w.tempCorrelation <= -0.3) parts.push(t("insights.tempSlows"));
    else if (w.tempCorrelation >= 0.3) parts.push(t("insights.tempFaster"));
    else parts.push(t("insights.tempNeutral"));
  } else {
    parts.push(t("insights.tempNotEnough"));
  }
  if (w.wetVsDryPct !== null) {
    const pct = Math.abs(Math.round(w.wetVsDryPct));
    if (w.wetVsDryPct <= -3) parts.push(t("insights.rainSlower", { pct }));
    else if (w.wetVsDryPct >= 3) parts.push(t("insights.rainFaster", { pct }));
    else parts.push(t("insights.rainSame"));
  }
  return parts.join(" ");
}

export default InsightsView;
