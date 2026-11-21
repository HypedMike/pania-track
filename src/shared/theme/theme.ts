import { useSettingsStore, type ThemeSetting } from "../settings/settings_store";

const QUERY = "(prefers-color-scheme: dark)";

function resolve(theme: ThemeSetting): "light" | "dark" {
  if (theme !== "system") return theme;
  return window.matchMedia(QUERY).matches ? "dark" : "light";
}

function apply() {
  const scheme = resolve(useSettingsStore.getState().theme);
  const root = document.documentElement;
  root.dataset.theme = scheme;
  root.style.colorScheme = scheme;
  // Android: match status/navigation bar icons to the page (bridge added in MainActivity.kt).
  (window as { PaniaSystemBars?: { setDark(dark: boolean): void } }).PaniaSystemBars?.setDark(scheme === "dark");
}

/** Keeps <html data-theme> in sync with the setting and the system scheme. Call once at startup. */
export function initTheme() {
  apply();
  useSettingsStore.subscribe(apply);
  window.matchMedia(QUERY).addEventListener("change", apply);
}
