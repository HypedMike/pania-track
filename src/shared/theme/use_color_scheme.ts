import { useSyncExternalStore } from "react";
import { useSettingsStore } from "../settings/settings_store";

export type ColorScheme = "light" | "dark";

const QUERY = "(prefers-color-scheme: dark)";

function subscribe(callback: () => void) {
  const media = window.matchMedia(QUERY);
  media.addEventListener("change", callback);
  return () => media.removeEventListener("change", callback);
}

function useSystemScheme(): ColorScheme {
  return useSyncExternalStore(
    subscribe,
    () => (window.matchMedia(QUERY).matches ? "dark" : "light"),
    () => "light",
  );
}

/** The scheme in effect: the user's choice, or the system's when set to "system". */
export function useColorScheme(): ColorScheme {
  const theme = useSettingsStore((s) => s.theme);
  const system = useSystemScheme();
  return theme === "system" ? system : theme;
}
