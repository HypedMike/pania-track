import { Channel, invoke } from "@tauri-apps/api/core";
import type { DownloadProgress } from "./format_progress";

/**
 * In-app updates (Android only). The Rust backend downloads the release APK, reporting progress,
 * and the native plugin opens the system installer on it. Android still asks the user to confirm.
 */
export const appInstaller = {
  /** Only Android has the native plugin; elsewhere the update link opens in the browser. */
  supported: /android/i.test(navigator.userAgent),

  /** Whether the user has allowed Pania to install apps ("install unknown apps"). */
  async canInstall(): Promise<boolean> {
    const { allowed } = await invoke<{ allowed: boolean }>("plugin:app-installer|can_install");
    return allowed;
  },

  /** Opens the system screen where that permission is granted. */
  openInstallSettings: () => invoke<void>("plugin:app-installer|open_install_settings"),

  /**
   * Downloads the release APK at `url` and opens the installer. `onProgress` is called as bytes
   * arrive; the promise resolves once the installer is on screen.
   */
  downloadAndInstall(url: string, onProgress: (progress: DownloadProgress) => void): Promise<void> {
    const channel = new Channel<DownloadProgress>();
    channel.onmessage = onProgress;
    return invoke<void>("plugin:app-installer|download_and_install", { url, onProgress: channel });
  },
};
