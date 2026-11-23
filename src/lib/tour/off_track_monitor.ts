export type OffTrackVerdict = "alert" | "remind" | "back" | null;

/** While still off the trail, remind every two minutes. */
const REPEAT_MS = 120_000;
/** Once alerted, the person must come back within this share of the threshold to be cleared. */
const CLEAR_SHARE = 0.7;

/**
 * Decides when a stray from the trail is worth an alert. The same rules run natively in
 * `OffTrackGuard.kt` while the screen is off, so keep the two in step:
 * a single stray fix does not count (two in a row do), a fix less accurate than the threshold
 * says nothing, and coming back is only noticed once well within the threshold.
 */
export class OffTrackMonitor {
  private consecutiveOff = 0;
  private alerted = false;
  private lastAlertAt = 0;

  /** Whether an alert is currently raised. */
  get offTrack(): boolean {
    return this.alerted;
  }

  reset() {
    this.consecutiveOff = 0;
    this.alerted = false;
    this.lastAlertAt = 0;
  }

  onFix(offTrackM: number, accuracyM: number | undefined, thresholdM: number, nowMs: number): OffTrackVerdict {
    if (accuracyM !== undefined && accuracyM > thresholdM) return null;

    if (offTrackM > thresholdM) {
      this.consecutiveOff++;
      if (this.consecutiveOff < 2) return null;
      if (!this.alerted) {
        this.alerted = true;
        this.lastAlertAt = nowMs;
        return "alert";
      }
      if (nowMs - this.lastAlertAt >= REPEAT_MS) {
        this.lastAlertAt = nowMs;
        return "remind";
      }
    } else if (offTrackM < thresholdM * CLEAR_SHARE) {
      this.consecutiveOff = 0;
      if (this.alerted) {
        this.alerted = false;
        return "back";
      }
    }
    return null;
  }
}
