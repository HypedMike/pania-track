import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { gpsService } from "../../../shared/gps/gps_service";
import type { Place } from "../../../shared/geocoding/photon";
import {
  formatDistance,
  formatElevation,
  haversine,
} from "../../../shared/gps/trail_stats";
import { plural, useT } from "../../../shared/i18n/i18n";
import { ROUTES } from "../../../shared/router/routes";
import { useNavigation } from "../../../shared/router/use_navigation";
import type { GpsCoordinate } from "../../trail/interfaces/gps_coordinate";
import BottomSheet from "../../../shared/ui/bottom_sheet";
import PlaceSearch from "../components/place_search";
import PlanMap, {
  checkpointLabel,
  type MapFocus,
} from "../components/plan_map";
import { climbAndTime, DifficultyChip } from "../components/route_badges";
import SteepnessProfile, {
  SteepnessProfileSkeleton,
} from "../components/steepness_profile";
import {
  checkpointName,
  usePlanStore,
  type Checkpoint,
} from "../stores/plan_store";

const FLOATING =
  "flex h-11 items-center rounded-full bg-surface shadow-[0_2px_8px_rgb(22_32_27/0.12)]";
/** How long a locate/search notice replaces the hint. */
const NOTICE_MS = 4000;
/** A tap this close to a searched place adds a checkpoint named after it. */
const PLACE_SNAP_M = 80;

/** Checkpoint name that turns into a text field for renaming. */
function CheckpointName({
  checkpoint,
  index,
}: {
  checkpoint: Checkpoint;
  index: number;
}) {
  const t = useT();
  const renameCheckpoint = usePlanStore((s) => s.renameCheckpoint);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");
  const name = checkpointName(checkpoint, index, t);

  function start() {
    setDraft(checkpoint.name ?? "");
    setEditing(true);
  }
  function commit() {
    renameCheckpoint(checkpoint.id, draft);
    setEditing(false);
  }

  if (editing) {
    return (
      <input
        autoFocus
        value={draft}
        maxLength={60}
        placeholder={checkpointName(
          { ...checkpoint, name: undefined },
          index,
          t,
        )}
        aria-label={t("plan.renameField", { n: checkpointLabel(index) })}
        enterKeyHint="done"
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") commit();
          else if (e.key === "Escape") setEditing(false);
        }}
        className="h-9 min-w-0 flex-1 rounded-lg border-2 border-brand-fg bg-surface px-2 text-[15px] font-medium text-ink focus:outline-none"
      />
    );
  }
  return (
    <button
      type="button"
      onClick={start}
      aria-label={t("plan.rename", { name })}
      className="group flex h-11 min-w-0 flex-1 items-center gap-1.5 text-left"
    >
      <span
        className={`truncate text-[15px] font-medium ${checkpoint.name ? "" : "text-ink-soft"}`}
      >
        {name}
      </span>
      <svg
        className="shrink-0 text-muted"
        width="14"
        height="14"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
      >
        <path d="M4 20h4L19 9l-4-4L4 16z" />
        <path d="M13.5 6.5l4 4" />
      </svg>
    </button>
  );
}

/** Elevation of the route point closest to `p`, if the route has elevation data. */
function nearestAltitude(
  p: GpsCoordinate,
  route: GpsCoordinate[],
): number | undefined {
  let best: GpsCoordinate | undefined;
  let bestD = Infinity;
  for (const c of route) {
    const d = haversine(p, c);
    if (d < bestD) {
      bestD = d;
      best = c;
    }
  }
  return best?.altitude;
}

function PlanView() {
  const t = useT();
  const { goTo, goBack } = useNavigation();
  const {
    checkpoints,
    loop,
    avoidRoads,
    status,
    error,
    variants,
    cursor,
    setCursor,
    addCheckpoint,
    moveCheckpoint,
    removeCheckpoint,
    undo,
    setLoop,
    setAvoidRoads,
    reset,
  } = usePlanStore();
  const route = variants[0];

  const [position, setPosition] = useState<GpsCoordinate | null>(null);
  const [locating, setLocating] = useState(false);
  const [focus, setFocus] = useState<MapFocus | null>(null);
  const [place, setPlace] = useState<Place | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const center = useRef<GpsCoordinate | undefined>(undefined);
  const focusKey = useRef(0);

  const [collapsed, setCollapsed] = useState(false);

  const moveTo = useCallback((target: Omit<MapFocus, "key">) => {
    setFocus({ ...target, key: ++focusKey.current });
  }, []);

  const locate = useCallback(
    async (silent: boolean) => {
      setLocating(true);
      try {
        await gpsService.ensurePermission();
        const fix = await gpsService.getCurrentPosition();
        setPosition(fix);
        center.current = fix;
        moveTo({ center: fix });
      } catch (e) {
        if (!silent) setNotice(e instanceof Error ? e.message : String(e));
      } finally {
        setLocating(false);
      }
    },
    [moveTo],
  );

  // Start on the user's position for a new plan; stay quiet if it isn't available.
  useEffect(() => {
    if (usePlanStore.getState().checkpoints.length === 0) locate(true);
  }, [locate]);

  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(null), NOTICE_MS);
    return () => clearTimeout(timer);
  }, [notice]);

  function add(p: GpsCoordinate) {
    const named = place && haversine(p, place) <= PLACE_SNAP_M;
    addCheckpoint(
      named ? { latitude: place.latitude, longitude: place.longitude } : p,
      named ? place.name : undefined,
    );
  }

  function showPlace(p: Place) {
    setPlace(p);
    moveTo({
      center: p,
      bounds: p.kind === "peak" ? undefined : p.bounds,
      zoom: p.kind === "peak" ? 15 : undefined,
    });
  }

  const altitudes = useMemo(
    () =>
      checkpoints.map((c) =>
        route ? nearestAltitude(c, route.coordinates) : undefined,
      ),
    [checkpoints, route],
  );

  function cancel() {
    reset();
    goBack();
  }

  const hint =
    checkpoints.length === 0 ? t("plan.hintStart") : t("plan.hintNext");

  return (
    <main className="relative flex h-dvh flex-col overflow-hidden bg-map">
      <div className="relative min-h-60 flex-1">
        <PlanMap
          checkpoints={checkpoints}
          variants={variants}
          selectedId={route?.id}
          onlySelected
          cursor={cursor}
          position={position}
          place={place}
          focus={focus}
          onViewChange={(c) => (center.current = c)}
          onAdd={add}
          onMove={moveCheckpoint}
        />

        <div className="pointer-events-none absolute inset-x-4 top-10 z-1001 flex items-center gap-2 pt-[env(safe-area-inset-top)]">
          <button
            type="button"
            onClick={cancel}
            className={`${FLOATING} pointer-events-auto px-4 text-[15px] font-semibold`}
          >
            {t("common.cancel")}
          </button>
          <h1 className="sr-only">{t("plan.title")}</h1>
          <PlaceSearch
            className="pointer-events-auto min-w-0 flex-1"
            near={() => center.current}
            onSelect={showPlace}
            onClear={() => setPlace(null)}
          />
          <button
            type="button"
            onClick={undo}
            disabled={checkpoints.length === 0}
            aria-label={t("plan.undo")}
            className={`${FLOATING} pointer-events-auto w-11 justify-center disabled:opacity-50`}
          >
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <path d="M9 14L4 9l5-5" />
              <path d="M4 9h11a5 5 0 0 1 0 10h-3" />
            </svg>
          </button>
        </div>
        <p
          role={notice ? "status" : undefined}
          className={`pointer-events-none absolute top-24 left-1/2 z-1000 mt-[env(safe-area-inset-top)] max-w-[calc(100%-32px)] -translate-x-1/2 rounded-2xl px-3.5 py-2 text-center text-[13px] font-medium ${
            notice ? "bg-danger text-white" : "bg-ink text-on-ink"
          }`}
        >
          {notice ?? hint}
        </p>

        <button
          type="button"
          onClick={() => locate(false)}
          disabled={locating}
          aria-label={t("plan.locate")}
          className={`${FLOATING} absolute right-4 bottom-11 z-1000 w-11 justify-center ${position ? "text-route" : "text-ink"}`}
        >
          <svg
            className={locating ? "motion-safe:animate-pulse" : ""}
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            aria-hidden="true"
          >
            <circle
              cx="12"
              cy="12"
              r="4"
              fill={position ? "currentColor" : "none"}
            />
            <path d="M12 2v3M12 19v3M2 12h3M19 12h3" />
            <circle cx="12" cy="12" r="8" />
          </svg>
        </button>
      </div>

      <BottomSheet
        collapsed={collapsed}
        onCollapsedChange={setCollapsed}
        handleLabel={t(collapsed ? "plan.sheetShow" : "plan.sheetHide")}
        summary={
          <div
            className="flex min-h-14 items-center justify-between gap-3"
            aria-live="polite"
          >
            {status === "ready" && route ? (
              <>
                <div className="flex min-w-0 flex-col gap-0.5">
                  <span className="text-[13px] text-muted">
                    {t(
                      loop && checkpoints.length > 1
                        ? "plan.summaryLoop"
                        : "plan.summaryOneWay",
                      {
                        checkpoints: plural(
                          "plan.checkpoint",
                          checkpoints.length,
                          t,
                        ),
                        marked: Math.round(route.analysis.markedShare * 100),
                      },
                    )}
                  </span>
                  <span className="text-[15px] text-ink-soft">
                    <span className="font-display text-2xl font-semibold text-ink">
                      {formatDistance(route.analysis.distanceM)}
                    </span>
                    {` · ${climbAndTime(route.analysis)}`}
                  </span>
                </div>
                <DifficultyChip difficulty={route.analysis.difficulty} />
              </>
            ) : status === "loading" ? (
              <>
                <div
                  className="flex min-w-0 flex-1 flex-col gap-1.5"
                  aria-busy="true"
                  aria-label={t("plan.finding")}
                >
                  <span
                    className="h-3 w-48 max-w-full rounded bg-line motion-safe:animate-pulse"
                    aria-hidden="true"
                  />
                  <span
                    className="h-6 w-40 max-w-full rounded bg-line motion-safe:animate-pulse"
                    aria-hidden="true"
                  />
                </div>
                <span
                  className="h-6 w-20 shrink-0 rounded-md bg-line motion-safe:animate-pulse"
                  aria-hidden="true"
                />
              </>
            ) : status === "error" ? (
              <span className="text-[15px] text-danger">{error}</span>
            ) : (
              <span className="text-[15px] text-muted">{t("plan.empty")}</span>
            )}
          </div>
        }
      >
        {status === "loading" ? (
          <SteepnessProfileSkeleton />
        ) : (
          status === "ready" &&
          route && (
            <SteepnessProfile
              coordinates={route.coordinates}
              checkpoints={checkpoints}
              onCursor={setCursor}
            />
          )
        )}

        {checkpoints.length > 0 && (
          <ol className="flex flex-col rounded-[14px] border border-line">
            {checkpoints.map((c, i) => (
              <li
                key={c.id}
                className="flex h-11 shrink-0 items-center gap-3 border-line pr-1 pl-3 not-first:border-t"
              >
                <span className="flex size-6 shrink-0 items-center justify-center rounded-full border-2 border-ink text-xs font-bold">
                  {checkpointLabel(i)}
                </span>
                <CheckpointName checkpoint={c} index={i} />
                {altitudes[i] !== undefined && (
                  <span className="text-[13px] text-muted">
                    {formatElevation(altitudes[i]!)}
                  </span>
                )}
                <button
                  type="button"
                  onClick={() => removeCheckpoint(c.id)}
                  aria-label={t("plan.remove", {
                    name: checkpointName(c, i, t),
                  })}
                  className="flex size-11 items-center justify-center text-muted"
                >
                  <svg
                    width="16"
                    height="16"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    aria-hidden="true"
                  >
                    <path d="M6 6l12 12M18 6L6 18" />
                  </svg>
                </button>
              </li>
            ))}
          </ol>
        )}

        <div className="flex flex-wrap gap-2">
          <label className="flex h-10 items-center gap-2 rounded-full border border-line-strong px-3 text-sm font-medium">
            <input
              type="checkbox"
              checked={loop}
              onChange={(e) => setLoop(e.target.checked)}
              className="size-4.5 accent-brand"
            />
            {t("plan.loop")}
          </label>
          <label className="flex h-10 items-center gap-2 rounded-full border border-line-strong px-3 text-sm font-medium">
            <input
              type="checkbox"
              checked={avoidRoads}
              onChange={(e) => setAvoidRoads(e.target.checked)}
              className="size-4.5 accent-brand"
            />
            {t("plan.avoidRoads")}
          </label>
        </div>

        <button
          type="button"
          onClick={() => goTo(ROUTES.planRoutes)}
          disabled={status !== "ready"}
          className="mt-1 flex h-13.5 shrink-0 items-center justify-center gap-2 rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-50"
        >
          {variants.length > 1
            ? t("plan.compare", { n: variants.length })
            : t("plan.review")}
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
            <path d="M5 12h14M13 6l6 6-6 6" />
          </svg>
        </button>
      </BottomSheet>
    </main>
  );
}

export default PlanView;
