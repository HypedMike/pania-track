import { useEffect, useRef, useState } from "react";
import { formatDistance } from "../../../shared/gps/trail_stats";
import { gpsService } from "../../../shared/gps/gps_service";
import { useT } from "../../../shared/i18n/i18n";
import { ROUTES, exploreTrailPath } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import BottomNav from "../../../shared/ui/layout/bottom_nav";
import MainLayout from "../../../shared/ui/layout/main_layout";
import type { TrailActivity } from "../../trail/interfaces/trail";
import Chips from "../components/chips";
import DifficultyBadge from "../components/difficulty_badge";
import ExploreMap from "../components/explore_map";
import { DIFFICULTIES, type Difficulty } from "../sharing_api";
import { LENGTH_RANGES, RADII_KM, useExploreStore, type LengthFilter } from "../stores/explore_store";

const LENGTHS = Object.keys(LENGTH_RANGES) as LengthFilter[];
const LENGTH_LABEL = {
  any: "explore.lengthAny",
  short: "explore.lengthShort",
  medium: "explore.lengthMedium",
  long: "explore.lengthLong",
} as const;

function ExploreView() {
  const t = useT();
  const { goTo } = useNavigation();
  const { filters, results, loading, error, searched, selectedId, setFilters, search, select } = useExploreStore();
  const [me, setMe] = useState<[number, number] | null>(null);
  const [locationFailed, setLocationFailed] = useState(false);
  const mapCenter = useRef<{ lat: number; lon: number } | null>(null);

  async function useMyLocation() {
    setLocationFailed(false);
    try {
      await gpsService.ensurePermission();
      const p = await gpsService.getCurrentPosition();
      setMe([p.latitude, p.longitude]);
      void search({ lat: p.latitude, lon: p.longitude });
    } catch {
      setLocationFailed(true);
    }
  }

  // First visit: search around the user. Later visits keep the previous results.
  useEffect(() => {
    if (!useExploreStore.getState().center) void useMyLocation();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const toggleDifficulty = (d: Difficulty) =>
    setFilters({ difficulty: filters.difficulty.includes(d) ? filters.difficulty.filter((x) => x !== d) : [...filters.difficulty, d] });

  return (
    <div className="flex min-h-screen flex-col">
      <MainLayout
        header={
          <header className="flex flex-col gap-1">
            <h1 className="font-display text-[34px] leading-tight font-bold tracking-tight">{t("explore.title")}</h1>
            <p className="text-sm text-muted">{t("explore.subtitle")}</p>
          </header>
        }
        className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-4 px-5 pt-[calc(1.75rem+var(--safe-top))] pb-6"
      >
        <div role="region" aria-label={t("explore.mapLabel")} className="relative h-[40vh] min-h-64 overflow-hidden rounded-2xl border border-line">
          <ExploreMap
            results={results}
            selectedId={selectedId}
            me={me}
            onSelect={select}
            onCenter={(lat, lon) => (mapCenter.current = { lat, lon })}
          />
          <div className="absolute inset-x-3 bottom-3 z-[1000] flex justify-between gap-2">
            <button
              type="button"
              onClick={() => void useMyLocation()}
              className="h-11 rounded-full border border-line-strong bg-surface px-4 text-sm font-semibold shadow"
            >
              {t("explore.myLocation")}
            </button>
            <button
              type="button"
              onClick={() => mapCenter.current && void search(mapCenter.current)}
              className="h-11 rounded-full bg-brand px-4 text-sm font-semibold text-white shadow"
            >
              {t("explore.searchHere")}
            </button>
          </div>
        </div>

        {locationFailed && <p className="text-sm text-muted">{t("explore.locationDenied")}</p>}

        <section aria-label={t("explore.filters")} className="flex flex-col gap-3 rounded-2xl border border-line bg-surface p-4">
          <Chips
            label={t("explore.within")}
            options={RADII_KM.map((n) => ({ id: n, label: t("explore.km", { n }) }))}
            selected={[filters.radiusKm]}
            onToggle={(radiusKm) => setFilters({ radiusKm })}
          />
          <Chips
            label={t("explore.length")}
            options={LENGTHS.map((id) => ({ id, label: t(LENGTH_LABEL[id]) }))}
            selected={[filters.length]}
            onToggle={(length) => setFilters({ length })}
          />
          <Chips
            label={t("explore.activity")}
            options={[
              { id: "all", label: t("explore.activityAll") },
              { id: "foot" as TrailActivity, label: t("activity.foot") },
              { id: "bike" as TrailActivity, label: t("activity.bike") },
            ]}
            selected={[filters.activity]}
            onToggle={(activity) => setFilters({ activity })}
          />
          <Chips
            label={t("explore.difficulty")}
            options={DIFFICULTIES.map((id) => ({ id, label: t(`difficulty.${id}`) }))}
            selected={filters.difficulty}
            onToggle={toggleDifficulty}
          />
        </section>

        <section aria-live="polite" className="flex flex-col gap-2">
          {loading && <p className="text-sm text-muted">{t("explore.searching")}</p>}
          {!loading && error && (
            <div className="flex flex-col gap-2 rounded-xl bg-warn-tint p-3 text-sm text-warn-ink">
              <p>{t("explore.error", { error })}</p>
              <button type="button" onClick={() => goTo(ROUTES.nostrSettings)} className="h-11 self-start text-sm font-semibold underline">
                {t("explore.relaySettings")}
              </button>
            </div>
          )}
          {!loading && !error && searched && results.length === 0 && (
            <p className="rounded-2xl border border-line bg-surface p-4 text-sm text-muted">{t("explore.empty")}</p>
          )}
          {!loading && results.length > 0 && <h2 className="text-base font-semibold">{t("explore.results", { n: results.length })}</h2>}
          <ul className="flex flex-col gap-2">
            {results.map((r) => (
              <li key={r.eventId}>
                <button
                  type="button"
                  onClick={() => goTo(exploreTrailPath(r.eventId))}
                  onFocus={() => select(r.eventId)}
                  aria-current={r.eventId === selectedId}
                  className={`flex w-full flex-col gap-1.5 rounded-2xl border bg-surface p-3.5 text-left ${
                    r.eventId === selectedId ? "border-2 border-brand-fg" : "border-line"
                  }`}
                >
                  <span className="text-[15px] font-semibold">{r.name}</span>
                  <span className="text-[13px] text-muted">
                    {formatDistance(r.distanceM)} · {t("explore.away", { n: r.awayKm.toFixed(1) })} ·{" "}
                    {r.authorName ? t("explore.by", { name: r.authorName }) : t("explore.anonymous")}
                  </span>
                  <span className="flex gap-2">
                    <DifficultyBadge difficulty={r.difficulty} />
                    <span className="rounded-md bg-canvas px-2 py-0.5 text-xs font-semibold text-ink-soft">{t(`activity.${r.activity}`)}</span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </section>
      </MainLayout>
      <BottomNav current="explore" />
    </div>
  );
}

export default ExploreView;
