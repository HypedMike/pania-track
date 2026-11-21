import { useEffect, useMemo, useState } from "react";
import { useNavigation } from "../../../shared/router/use_navigation";
import { ROUTES, trailDetailPath } from "../../../shared/router/routes";
import { computeStats } from "../../../shared/gps/trail_stats";
import { useRecordingStore } from "../../trail/stores/recording_store";
import { useTrailStore } from "../../trail/stores/trail_store";
import type { TrailSource } from "../../trail/interfaces/trail";
import { useT } from "../../../shared/i18n/i18n";
import BottomNav from "../../../shared/ui/layout/bottom_nav";
import MainLayout from "../../../shared/ui/layout/main_layout";
import HomeHeader from "../components/home_header";
import RecordingBanner from "../components/recording_banner";
import HomeActions from "../components/home_actions";
import FilterTabs from "../components/filter_tabs";
import TrailListItem from "../components/trail_list_item";

type Filter = "all" | TrailSource;

function HomeView() {
  const t = useT();
  const { goTo } = useNavigation();
  const { trails, loading, error, load } = useTrailStore();
  const recordingStatus = useRecordingStore((state) => state.status);
  const [filter, setFilter] = useState<Filter>("all");

  useEffect(() => {
    load();
  }, [load]);

  const rows = useMemo(
    () =>
      trails.map((trail) => ({
        trail,
        stats: computeStats(trail.coordinates),
      })),
    [trails],
  );
  const totalM = rows.reduce((sum, r) => sum + r.stats.distanceM, 0);
  const visible =
    filter === "all" ? rows : rows.filter((r) => r.trail.source === filter);
  const count = (source: TrailSource) =>
    trails.filter((t) => t.source === source).length;
  const tabs: { id: Filter; label: string; n: number }[] = [
    { id: "all", label: t("home.filterAll"), n: trails.length },
    { id: "recorded", label: t("home.filterRecorded"), n: count("recorded") },
    { id: "imported", label: t("home.filterImported"), n: count("imported") },
  ];

  return (
    <div className="flex min-h-screen flex-col">
    <MainLayout
      header={
        <HomeHeader
          trailCount={trails.length}
          totalDistanceM={totalM}
          onOpenSettings={() => goTo(ROUTES.settings)}
        />
      }
      className="mx-auto flex w-full max-w-2xl flex-1 flex-col gap-5 px-5 pt-7 pb-6"
    >
      {recordingStatus !== "idle" && (
        <RecordingBanner
          paused={recordingStatus === "paused"}
          onOpen={() => goTo(ROUTES.record)}
        />
      )}

      <HomeActions
        recordDisabled={recordingStatus !== "idle"}
        onRecord={() => goTo(ROUTES.record)}
        onImport={() => goTo(ROUTES.importTrail)}
      />

      {trails.length > 0 && (
        <FilterTabs tabs={tabs} selected={filter} onSelect={setFilter} />
      )}

      {loading && <p className="text-muted">{t("common.loading")}</p>}
      {error && <p className="text-danger">{t("home.loadError", { error })}</p>}
      {!loading && !error && trails.length === 0 && (
        <p className="rounded-2xl border border-line bg-surface p-5 text-center text-sm text-muted">
          {t("home.empty")}
        </p>
      )}

      <ul className="flex flex-col gap-3">
        {visible.map(({ trail, stats }) => (
          <TrailListItem
            key={trail.id}
            trail={trail}
            stats={stats}
            onSelect={() => goTo(trailDetailPath(trail.id))}
          />
        ))}
      </ul>
    </MainLayout>
    <BottomNav current="trails" />
    </div>
  );
}

export default HomeView;
