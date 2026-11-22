import { create } from "zustand";
import type { TFunction } from "../../../shared/i18n/i18n";
import type { GpsCoordinate } from "../../trail/interfaces/gps_coordinate";
import { toast } from "sonner";
import { planRoutes, type RouteVariant } from "../route_planner";

export interface Checkpoint {
  id: string;
  latitude: number;
  longitude: number;
  /** Set by the user (or from a searched place); otherwise a default name is shown. */
  name?: string;
}

/** The checkpoint's own name, or "Start" / "Checkpoint 3" by position. */
export function checkpointName(c: Checkpoint, index: number, t: TFunction): string {
  return c.name || (index === 0 ? t("plan.start") : t("plan.checkpointN", { n: index + 1 }));
}

const MAX_NAME_LENGTH = 60;

type Status = "idle" | "loading" | "ready" | "error";

interface PlanState {
  checkpoints: Checkpoint[];
  /** Return to the first checkpoint at the end. */
  loop: boolean;
  avoidRoads: boolean;
  status: Status;
  error: string | null;
  /** Variants for the current checkpoints; the first is the recommended one. */
  variants: RouteVariant[];
  selectedId: string | null;
  /** Point picked on the steepness profile, shown as a dot on the map. */
  cursor: GpsCoordinate | null;

  addCheckpoint: (point: GpsCoordinate, name?: string) => void;
  /** An empty name goes back to the default. */
  renameCheckpoint: (id: string, name: string) => void;
  moveCheckpoint: (id: string, point: GpsCoordinate) => void;
  removeCheckpoint: (id: string) => void;
  /** Removes the most recently added checkpoint. */
  undo: () => void;
  setLoop: (loop: boolean) => void;
  setAvoidRoads: (avoid: boolean) => void;
  select: (id: string) => void;
  setCursor: (p: GpsCoordinate | null) => void;
  reset: () => void;
}

/** Waits for the user to stop tapping/dragging before asking the router. */
const DEBOUNCE_MS = 500;
let timer: ReturnType<typeof setTimeout> | undefined;
let controller: AbortController | undefined;

const INITIAL = {
  checkpoints: [] as Checkpoint[],
  loop: true,
  avoidRoads: true,
  status: "idle" as Status,
  error: null,
  variants: [] as RouteVariant[],
  selectedId: null,
  cursor: null as GpsCoordinate | null,
};

export const usePlanStore = create<PlanState>((set, get) => {
  function cancel() {
    clearTimeout(timer);
    controller?.abort();
    controller = undefined;
  }

  /** Re-plans after any change to the checkpoints or options. */
  function replan() {
    cancel();
    const { checkpoints } = get();
    if (checkpoints.length < 2) {
      set({ status: "idle", error: null, variants: [], selectedId: null });
      return;
    }
    set({ status: "loading", error: null, cursor: null });
    timer = setTimeout(async () => {
      const own = new AbortController();
      controller = own;
      const { checkpoints, loop, avoidRoads } = get();
      try {
        const variants = await planRoutes(checkpoints, { loop, avoidRoads }, own.signal);
        if (own.signal.aborted) return;
        set({ status: "ready", variants, selectedId: variants[0]?.id ?? null });
      } catch (e) {
        if (own.signal.aborted) return;
        const message = e instanceof Error ? e.message : String(e);
        set({ status: "error", error: message, variants: [], selectedId: null });
        toast.error(message, { id: message });
      }
    }, DEBOUNCE_MS);
  }

  return {
    ...INITIAL,

    addCheckpoint: ({ latitude, longitude }, name) => {
      set((s) => ({ checkpoints: [...s.checkpoints, { id: crypto.randomUUID(), latitude, longitude, name }] }));
      replan();
    },
    // Names don't change the route, so no replanning.
    renameCheckpoint: (id, name) => {
      const trimmed = name.trim().slice(0, MAX_NAME_LENGTH) || undefined;
      set((s) => ({ checkpoints: s.checkpoints.map((c) => (c.id === id ? { ...c, name: trimmed } : c)) }));
    },
    moveCheckpoint: (id, { latitude, longitude }) => {
      set((s) => ({ checkpoints: s.checkpoints.map((c) => (c.id === id ? { ...c, latitude, longitude } : c)) }));
      replan();
    },
    removeCheckpoint: (id) => {
      set((s) => ({ checkpoints: s.checkpoints.filter((c) => c.id !== id) }));
      replan();
    },
    undo: () => {
      set((s) => ({ checkpoints: s.checkpoints.slice(0, -1) }));
      replan();
    },
    setLoop: (loop) => {
      set({ loop });
      replan();
    },
    setAvoidRoads: (avoidRoads) => {
      set({ avoidRoads });
      replan();
    },
    select: (selectedId) => set({ selectedId, cursor: null }),
    setCursor: (cursor) => set({ cursor }),
    reset: () => {
      cancel();
      set(INITIAL);
    },
  };
});
