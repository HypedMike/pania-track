import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useState } from "react";
import { useT } from "../i18n/i18n";
import { useSettingsStore } from "../settings/settings_store";
import {
  fetchLatestRelease,
  isNewerVersion,
  LATEST_RELEASE_URL,
  type LatestRelease,
} from "./latest_release";

/** Checks GitHub once per launch (if enabled in settings) and offers the update. */
function UpdatePrompt() {
  const t = useT();
  const [release, setRelease] = useState<LatestRelease | null>(null);

  useEffect(() => {
    if (!LATEST_RELEASE_URL || !useSettingsStore.getState().checkForUpdates) return;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    fetchLatestRelease(LATEST_RELEASE_URL, controller.signal)
      .then((latest) => {
        if (isNewerVersion(latest.version, __APP_VERSION__)) setRelease(latest);
      })
      .catch(() => {
        /* offline or rate limited: try again next launch */
      })
      .finally(() => clearTimeout(timeout));
    return () => {
      clearTimeout(timeout);
      controller.abort();
    };
  }, []);

  if (!release) return null;

  const dismiss = () => setRelease(null);
  const update = () => {
    openUrl(release.downloadUrl).catch(() => window.open(release.downloadUrl, "_blank"));
    dismiss();
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="update-title"
      className="fixed inset-0 z-[2000] flex items-end justify-center bg-black/50 p-4 sm:items-center"
    >
      <div className="flex w-full max-w-sm flex-col gap-4 rounded-3xl bg-surface p-5 text-ink shadow-xl">
        <div className="flex flex-col gap-1.5">
          <h2 id="update-title" className="font-display text-xl font-bold">
            {t("update.title")}
          </h2>
          <p className="text-sm text-muted">
            {t("update.message", { version: release.version, current: __APP_VERSION__ })}
          </p>
        </div>
        <div className="flex flex-col gap-2">
          <button
            type="button"
            onClick={update}
            className="h-[50px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark"
          >
            {t("update.action")}
          </button>
          <button
            type="button"
            onClick={dismiss}
            className="h-[50px] rounded-2xl border border-line-strong text-base font-medium"
          >
            {t("update.later")}
          </button>
        </div>
      </div>
    </div>
  );
}

export default UpdatePrompt;
