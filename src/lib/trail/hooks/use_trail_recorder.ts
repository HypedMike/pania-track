import { useCallback, useEffect, useRef, useState } from "react";
import { gpsService } from "../../../shared/gps/gps_service";
import { useTrailStore } from "../stores/trail_store";

export const RECORD_INTERVAL_MS = 30_000;

/**
 * Records the device's GPS position into a trail: once immediately, then every 30 seconds
 * until stopped. Recording only runs while the component using this hook is mounted and the
 * app is in the foreground.
 */
export function useTrailRecorder(trailId: string) {
  const appendCoordinate = useTrailStore((state) => state.appendCoordinate);
  const [recording, setRecording] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);
  const capturing = useRef(false);

  const stop = useCallback(() => {
    if (timer.current) clearInterval(timer.current);
    timer.current = null;
    setRecording(false);
  }, []);

  const capture = useCallback(async () => {
    if (capturing.current) return; // previous fix still in flight
    capturing.current = true;
    try {
      await appendCoordinate(trailId, await gpsService.getCurrentPosition());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      capturing.current = false;
    }
  }, [appendCoordinate, trailId]);

  const start = useCallback(async () => {
    if (timer.current) return;
    setError(null);
    try {
      await gpsService.ensurePermission();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      return;
    }
    setRecording(true);
    void capture();
    timer.current = setInterval(() => void capture(), RECORD_INTERVAL_MS);
  }, [capture]);

  // Stop when leaving the view.
  useEffect(() => stop, [stop]);

  return { recording, error, start, stop };
}
