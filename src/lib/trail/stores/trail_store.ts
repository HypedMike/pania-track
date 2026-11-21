import { create } from "zustand";
import type { Trail } from "../interfaces/trail";
import { trailRepository } from "../repositories/trail_repository";

/** Fields the user provides; the store generates the rest. */
export type NewTrail = Pick<Trail, "name" | "description" | "coordinates" | "waypoints" | "source">;

interface TrailState {
  trails: Trail[];
  loading: boolean;
  error: string | null;

  /** Loads all trails from the database into the store. */
  load: () => Promise<void>;
  /** Validates, saves and adds a new trail. Rejects with an Error on invalid input or failure. */
  createTrail: (input: NewTrail) => Promise<Trail>;
  /** Applies changes to an existing trail and persists them. */
  updateTrail: (id: string, changes: Partial<NewTrail>) => Promise<Trail>;
  deleteTrail: (id: string) => Promise<void>;
  getTrail: (id: string) => Trail | undefined;
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function normalize(input: Partial<NewTrail>): Partial<NewTrail> {
  const result = { ...input };
  if (result.name !== undefined) {
    result.name = result.name.trim();
    if (result.name === "") throw new Error("A trail needs a name.");
  }
  if (result.description !== undefined) result.description = result.description.trim();
  return result;
}

export const useTrailStore = create<TrailState>((set, get) => ({
  trails: [],
  loading: false,
  error: null,

  load: async () => {
    set({ loading: true, error: null });
    try {
      set({ trails: await trailRepository.getAll(), loading: false });
    } catch (e) {
      set({ loading: false, error: errorMessage(e) });
    }
  },

  createTrail: async (input) => {
    const data = normalize(input) as NewTrail;
    const now = Date.now();
    const trail: Trail = { ...data, id: crypto.randomUUID(), createdAt: now, updatedAt: now };
    await trailRepository.save(trail);
    set((state) => ({ trails: [trail, ...state.trails] }));
    return trail;
  },

  updateTrail: async (id, changes) => {
    const existing = get().trails.find((t) => t.id === id);
    if (!existing) throw new Error("Trail not found.");
    const updated: Trail = { ...existing, ...normalize(changes) };
    await trailRepository.save(updated);
    set((state) => ({ trails: state.trails.map((t) => (t.id === id ? updated : t)) }));
    return updated;
  },

  deleteTrail: async (id) => {
    await trailRepository.remove(id);
    set((state) => ({ trails: state.trails.filter((t) => t.id !== id) }));
  },

  getTrail: (id) => get().trails.find((t) => t.id === id),
}));
