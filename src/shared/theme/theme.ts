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

/** Android: apply the status-bar height reported by the native side (see MainActivity.kt). */
function applySafeInsets() {
  const bars = (window as { PaniaSystemBars?: { topInset?(): number } }).PaniaSystemBars;
  const top = bars?.topInset?.();
  if (top) document.documentElement.style.setProperty("--safe-top", `${top}px`);
}

/** Keeps <html data-theme> in sync with the setting and the system scheme. Call once at startup. */
export function initTheme() {
  apply();
  applySafeInsets();
  useSettingsStore.subscribe(apply);
  window.matchMedia(QUERY).addEventListener("change", apply);
}
