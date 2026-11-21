import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

export type ThemeSetting = "system" | "light" | "dark";

/** Selectable GPS recording intervals, in seconds. */
export const RECORD_INTERVALS_S = [1, 2, 5, 10, 30, 60] as const;
export const DEFAULT_RECORD_INTERVAL_S = 5;

interface SettingsState {
  theme: ThemeSetting;
  /** Seconds between points added to a track while recording. */
  recordIntervalS: number;
  setTheme: (theme: ThemeSetting) => void;
  setRecordIntervalS: (seconds: number) => void;
}

/** Key is also read by the inline script in index.html to avoid a theme flash. */
export const SETTINGS_STORAGE_KEY = "pania.settings";

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      theme: "system",
      recordIntervalS: DEFAULT_RECORD_INTERVAL_S,
      setTheme: (theme) => set({ theme }),
      setRecordIntervalS: (recordIntervalS) => set({ recordIntervalS }),
    }),
    { name: SETTINGS_STORAGE_KEY, storage: createJSONStorage(() => localStorage) },
  ),
);

/** Current recording interval in ms. */
export function recordIntervalMs(): number {
  return useSettingsStore.getState().recordIntervalS * 1000;
}
