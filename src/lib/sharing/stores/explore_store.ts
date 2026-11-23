import { create } from "zustand";
import type { TrailActivity } from "../../trail/interfaces/trail";
import { errorText, sharingApi, type Difficulty, type SharedTrail } from "../sharing_api";

export type LengthFilter = "any" | "short" | "medium" | "long";

export const RADII_KM = [5, 10, 25, 50] as const;
/** Length buckets in km: [min, max]; undefined means open-ended. */
export const LENGTH_RANGES: Record<LengthFilter, [number | undefined, number | undefined]> = {
  any: [undefined, undefined],
  short: [undefined, 5],
  medium: [5, 15],
  long: [15, undefined],
};

export interface ExploreFilters {
  radiusKm: number;
  length: LengthFilter;
  activity: "all" | TrailActivity;
  difficulty: Difficulty[];
}

export interface SearchCenter {
  lat: number;
  lon: number;
}

interface ExploreState {
  filters: ExploreFilters;
  /** Where the last search was centered; null until the user has a position or moves the map. */
  center: SearchCenter | null;
  results: SharedTrail[];
  loading: boolean;
  error: string | null;
  /** False until the first search finishes, so "nothing found" is not shown before searching. */
  searched: boolean;
  selectedId: string | null;

  setFilters: (changes: Partial<ExploreFilters>) => void;
  /** Searches around `center` (or the previous center) with the current filters. */
  search: (center?: SearchCenter) => Promise<void>;
  select: (eventId: string | null) => void;
  get: (eventId: string) => SharedTrail | undefined;
}

// Answers can arrive out of order when filters change quickly; only the latest one is kept.
let latestRequest = 0;

export const useExploreStore = create<ExploreState>((set, get) => ({
  filters: { radiusKm: 10, length: "any", activity: "all", difficulty: [] },
  center: null,
  results: [],
  loading: false,
  error: null,
  searched: false,
  selectedId: null,

  setFilters(changes) {
    set((s) => ({ filters: { ...s.filters, ...changes } }));
    if (get().center) void get().search();
  },

  async search(center) {
    const where = center ?? get().center;
    if (!where) return;
    const request = ++latestRequest;
    set({ center: where, loading: true, error: null });
    const { filters } = get();
    const [minLengthKm, maxLengthKm] = LENGTH_RANGES[filters.length];
    try {
      const results = await sharingApi.explore({
        lat: where.lat,
        lon: where.lon,
        radiusKm: filters.radiusKm,
        minLengthKm,
        maxLengthKm,
        activity: filters.activity === "all" ? undefined : filters.activity,
        difficulty: filters.difficulty,
      });
      if (request !== latestRequest) return;
      set({ results, loading: false, searched: true, selectedId: null });
    } catch (e) {
      if (request !== latestRequest) return;
      set({ loading: false, searched: true, error: errorText(e), results: [] });
    }
  },

  select: (selectedId) => set({ selectedId }),
  get: (eventId) => get().results.find((t) => t.eventId === eventId),
}));
