import { t } from "../i18n/i18n";
import type { LiveInfo } from "./background_recorder";

/** The captions shown by the native status notification and widget, in the app's language. */
export function liveLabels(): LiveInfo["labels"] {
  return {
    distance: t("common.distance"),
    time: t("common.duration"),
    climb: t("live.climb"),
    left: t("tour.remaining"),
    arrival: t("tour.eta"),
    done: t("live.done"),
  };
}
