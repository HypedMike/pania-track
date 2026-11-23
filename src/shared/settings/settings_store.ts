import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { detectLanguage, type Language } from "../i18n/translations";

export type ThemeSetting = "system" | "light" | "dark";

/** Selectable GPS recording intervals, in seconds. */
export const RECORD_INTERVALS_S = [1, 2, 5, 10, 30, 60] as const;
export const DEFAULT_RECORD_INTERVAL_S = 5;

/** Selectable distances from the trail, in meters, beyond which a tour raises an off-track alert. */
export const OFF_TRACK_DISTANCES_M = [25, 50, 100, 200] as const;
export const DEFAULT_OFF_TRACK_M = 50;

interface SettingsState {
  theme: ThemeSetting;
  language: Language;
  /** Seconds between points added to a track while recording. */
  recordIntervalS: number;
  /** How far from the trail, in meters, a tour lets you stray before alerting. */
  offTrackM: number;
  /** Look for a newer GitHub release when the app opens. */
  checkForUpdates: boolean;
  setTheme: (theme: ThemeSetting) => void;
  setLanguage: (language: Language) => void;
  setRecordIntervalS: (seconds: number) => void;
  setOffTrackM: (meters: number) => void;
  setCheckForUpdates: (enabled: boolean) => void;
}

/** Key is also read by the inline script in index.html to avoid a theme flash. */
export const SETTINGS_STORAGE_KEY = "pania.settings";

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      theme: "system",
      language: detectLanguage(),
      recordIntervalS: DEFAULT_RECORD_INTERVAL_S,
      offTrackM: DEFAULT_OFF_TRACK_M,
      checkForUpdates: true,
      setTheme: (theme) => set({ theme }),
      setLanguage: (language) => set({ language }),
      setRecordIntervalS: (recordIntervalS) => set({ recordIntervalS }),
      setOffTrackM: (offTrackM) => set({ offTrackM }),
      setCheckForUpdates: (checkForUpdates) => set({ checkForUpdates }),
    }),
    { name: SETTINGS_STORAGE_KEY, storage: createJSONStorage(() => localStorage) },
  ),
);

/** Current recording interval in ms. */
export function recordIntervalMs(): number {
  return useSettingsStore.getState().recordIntervalS * 1000;
}
