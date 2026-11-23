import { invoke } from "@tauri-apps/api/core";

/**
 * In-app updates (Android only): the native `app-installer` plugin downloads a release APK and
 * opens the system installer on it. Android still asks the user to confirm the install.
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

  /** Downloads the release APK at `url` and opens the installer. Resolves once the installer is up. */
  downloadAndInstall: (url: string) => invoke<void>("plugin:app-installer|download_and_install", { url }),
};
