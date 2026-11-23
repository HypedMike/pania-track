/**
 * Recording a trail and following one (a tour) both use the same native GPS service and its
 * single point buffer, so only one of them can run at a time.
 */
export type CaptureOwner = "recording" | "tour";

let owner: CaptureOwner | null = null;

export const captureLock = {
  /** Takes the lock. Returns false when the other feature holds it. */
  claim(who: CaptureOwner): boolean {
    if (owner !== null && owner !== who) return false;
    owner = who;
    return true;
  },
  release(who: CaptureOwner) {
    if (owner === who) owner = null;
  },
  heldBy(): CaptureOwner | null {
    return owner;
  },
};
