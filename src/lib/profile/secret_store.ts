import { invoke } from "@tauri-apps/api/core";

/**
 * Where the Nostr secret key lives. On Android it is encrypted with a key held in the Android
 * Keystore (the native `secret-store` plugin). Desktop builds exist only for development and
 * have no keystore plugin, so they fall back to plain `localStorage`: never ship that.
 */
const NATIVE = /android/i.test(navigator.userAgent);
const DEV_KEY = "pania.dev-secrets";

function readDev(): Record<string, string> {
  try {
    return JSON.parse(localStorage.getItem(DEV_KEY) ?? "{}") as Record<string, string>;
  } catch {
    return {};
  }
}

export const secretStore = {
  /** True when secrets are protected by the platform keystore. */
  secure: NATIVE,

  async get(key: string): Promise<string | null> {
    if (NATIVE) {
      const result = await invoke<{ value: string | null }>("plugin:secret-store|get_secret", { key });
      return result.value ?? null;
    }
    return readDev()[key] ?? null;
  },

  async set(key: string, value: string): Promise<void> {
    if (NATIVE) {
      await invoke("plugin:secret-store|set_secret", { key, value });
      return;
    }
    localStorage.setItem(DEV_KEY, JSON.stringify({ ...readDev(), [key]: value }));
  },

  async delete(key: string): Promise<void> {
    if (NATIVE) {
      await invoke("plugin:secret-store|delete_secret", { key });
      return;
    }
    const { [key]: _removed, ...rest } = readDev();
    localStorage.setItem(DEV_KEY, JSON.stringify(rest));
  },
};
