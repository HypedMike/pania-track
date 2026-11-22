import { openUrl } from "@tauri-apps/plugin-opener";

/** Source code of the app. */
export const REPO_URL = "https://github.com/HypedMike/pania-track";

/** Opens a link in the system browser; inside Tauri a plain link would load in the app's own webview. */
export function openExternal(url: string): void {
  openUrl(url).catch(() => window.open(url, "_blank", "noopener"));
}
