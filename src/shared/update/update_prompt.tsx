import { openUrl } from "@tauri-apps/plugin-opener";
import { useCallback, useEffect, useState } from "react";
import { useT } from "../i18n/i18n";
import { useSettingsStore } from "../settings/settings_store";
import { appInstaller } from "./app_installer";
import { describeProgress, percent, type DownloadProgress } from "./format_progress";
import {
  fetchLatestRelease,
  isNewerVersion,
  LATEST_RELEASE_URL,
  type LatestRelease,
} from "./latest_release";

type Phase = "idle" | "needsPermission" | "downloading" | "failed";

/** Checks GitHub once per launch (if enabled in settings) and offers the update. */
function UpdatePrompt() {
  const t = useT();
  const [release, setRelease] = useState<LatestRelease | null>(null);
  const [phase, setPhase] = useState<Phase>("idle");
  const [error, setError] = useState("");
  const [progress, setProgress] = useState<DownloadProgress | null>(null);

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

  const openInBrowser = useCallback(() => {
    if (!release) return;
    openUrl(release.downloadUrl).catch(() => window.open(release.downloadUrl, "_blank"));
  }, [release]);

  /** Downloads the APK and opens Android's installer; asks for the install permission first if needed. */
  const install = useCallback(async () => {
    if (!release) return;
    if (!appInstaller.supported) {
      openInBrowser();
      setRelease(null);
      return;
    }
    try {
      if (!(await appInstaller.canInstall())) {
        setPhase("needsPermission");
        return;
      }
      setProgress(null);
      setPhase("downloading");
      await appInstaller.downloadAndInstall(release.downloadUrl, setProgress);
      // The system installer is on screen now; it takes it from here.
      setRelease(null);
      setPhase("idle");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPhase("failed");
    }
  }, [release, openInBrowser]);

  // After the user grants the permission in system settings and comes back, carry on by itself.
  useEffect(() => {
    if (phase !== "needsPermission") return;
    const onVisible = () => {
      if (document.visibilityState === "visible") void install();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [phase, install]);

  if (!release) return null;

  const dismiss = () => {
    setRelease(null);
    setPhase("idle");
  };
  const downloading = phase === "downloading";
  const pct = progress ? percent(progress) : null;

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
            {phase === "needsPermission"
              ? t("update.permissionText")
              : phase === "failed"
                ? t("update.failed", { error })
                : downloading
                  ? t("update.downloading", { version: release.version })
                  : t("update.message", { version: release.version, current: __APP_VERSION__ })}
          </p>
        </div>
        {downloading && (
          <div className="flex flex-col gap-2">
            <div
              role="progressbar"
              aria-label={t("update.downloadingShort")}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={pct ?? undefined}
              className="h-2.5 overflow-hidden rounded-full bg-line"
            >
              <div
                style={{ width: `${pct ?? 100}%` }}
                className={`h-full rounded-full bg-brand transition-[width] duration-150 motion-reduce:transition-none ${
                  pct === null ? "motion-safe:animate-pulse" : ""
                }`}
              />
            </div>
            <p aria-live="off" className="text-xs text-muted tabular-nums">
              {progress ? describeProgress(progress, t) : t("update.starting")}
            </p>
          </div>
        )}
        <div className="flex flex-col gap-2">
          {phase === "needsPermission" ? (
            <button
              type="button"
              onClick={() => void appInstaller.openInstallSettings().catch(() => setPhase("failed"))}
              className="h-[50px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark"
            >
              {t("update.permissionAction")}
            </button>
          ) : (
            <button
              type="button"
              onClick={() => void install()}
              disabled={downloading}
              className="h-[50px] rounded-2xl bg-brand text-base font-semibold text-white active:bg-brand-dark disabled:opacity-60"
            >
              {downloading ? t("update.downloadingShort") : phase === "failed" ? t("update.retry") : t("update.action")}
            </button>
          )}
          {phase === "failed" && (
            <button
              type="button"
              onClick={() => {
                openInBrowser();
                dismiss();
              }}
              className="h-[50px] rounded-2xl border border-line-strong text-base font-medium"
            >
              {t("update.openBrowser")}
            </button>
          )}
          <button
            type="button"
            onClick={dismiss}
            disabled={downloading}
            className="h-[50px] rounded-2xl border border-line-strong text-base font-medium disabled:opacity-60"
          >
            {t("update.later")}
          </button>
        </div>
      </div>
    </div>
  );
}

export default UpdatePrompt;
