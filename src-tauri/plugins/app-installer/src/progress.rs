//! Download progress: bytes so far, a smoothed speed and the time left.
//!
//! Pure and clock-free (the caller passes `Instant`s), so it can be tested without waiting.

use serde::Serialize;
use std::time::{Duration, Instant};

/// What the UI shows. Sent to the webview as the download advances.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub downloaded: u64,
    /// `None` when the server did not say how big the file is.
    pub total: Option<u64>,
    /// Current speed in bytes per second, smoothed so the number does not jump around.
    pub speed_bps: f64,
    /// Seconds left at the current speed; `None` without a known size or while the speed is ~0.
    pub eta_seconds: Option<u64>,
    pub done: bool,
}

/// Speed is measured over windows of at least this long, then smoothed.
const SAMPLE_WINDOW: Duration = Duration::from_millis(250);
/// Weight of the newest window in the smoothed speed (1.0 would be "no smoothing").
const SMOOTHING: f64 = 0.3;
/// Progress is reported at most this often, so a fast download does not flood the webview.
const REPORT_EVERY: Duration = Duration::from_millis(150);

pub struct Tracker {
    total: Option<u64>,
    window_start: Instant,
    window_bytes: u64,
    speed: Option<f64>,
    last_report: Option<Instant>,
}

impl Tracker {
    pub fn new(total: Option<u64>, now: Instant) -> Self {
        Self { total, window_start: now, window_bytes: 0, speed: None, last_report: None }
    }

    fn snapshot(&self, downloaded: u64, done: bool) -> Progress {
        let speed_bps = self.speed.unwrap_or(0.0);
        let eta_seconds = match self.total {
            Some(total) if speed_bps > 1.0 && total > downloaded => Some(((total - downloaded) as f64 / speed_bps).ceil() as u64),
            Some(_) if done => Some(0),
            _ => None,
        };
        Progress { downloaded, total: self.total, speed_bps, eta_seconds, done }
    }

    /// Records that `downloaded` bytes have arrived in total. Returns a report when it is time
    /// for one (the first call, then at most every [`REPORT_EVERY`]).
    pub fn update(&mut self, now: Instant, downloaded: u64) -> Option<Progress> {
        let elapsed = now.saturating_duration_since(self.window_start);
        if elapsed >= SAMPLE_WINDOW {
            let rate = downloaded.saturating_sub(self.window_bytes) as f64 / elapsed.as_secs_f64();
            self.speed = Some(match self.speed {
                Some(previous) => previous + SMOOTHING * (rate - previous),
                None => rate,
            });
            self.window_start = now;
            self.window_bytes = downloaded;
        }
        let due = self.last_report.is_none_or(|last| now.saturating_duration_since(last) >= REPORT_EVERY);
        if !due {
            return None;
        }
        self.last_report = Some(now);
        Some(self.snapshot(downloaded, false))
    }

    /// The final report, always produced.
    pub fn finish(&mut self, downloaded: u64) -> Progress {
        self.snapshot(downloaded, true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(t0: Instant, ms: u64) -> Instant {
        t0 + Duration::from_millis(ms)
    }

    #[test]
    fn measures_a_steady_speed_and_the_time_left() {
        let t0 = Instant::now();
        let mut t = Tracker::new(Some(10_000_000), t0);
        let mut last = None;
        // 1 MB/s for 2 s, in 100 ms steps.
        for step in 1..=20u64 {
            if let Some(p) = t.update(at(t0, step * 100), step * 100_000) {
                last = Some(p);
            }
        }
        let p = last.unwrap();
        assert!((p.speed_bps - 1_000_000.0).abs() < 50_000.0, "speed {}", p.speed_bps);
        // 8 MB left at ~1 MB/s.
        assert!((7..=9).contains(&p.eta_seconds.unwrap()), "eta {:?}", p.eta_seconds);
        assert!(!p.done && p.total == Some(10_000_000));
    }

    #[test]
    fn smooths_a_burst_instead_of_jumping() {
        let t0 = Instant::now();
        let mut t = Tracker::new(None, t0);
        let mut bytes = 0;
        let mut speeds = vec![];
        for step in 1..=12u64 {
            bytes += if step == 8 { 5_000_000 } else { 100_000 }; // one burst of 50x
            if let Some(p) = t.update(at(t0, step * 250), bytes) {
                speeds.push(p.speed_bps);
            }
        }
        let burst_instant = 5_000_000.0 / 0.25;
        assert!(speeds.iter().all(|&s| s < burst_instant * 0.5), "burst must be smoothed: {speeds:?}");
    }

    #[test]
    fn reports_are_throttled_and_the_first_one_is_immediate() {
        let t0 = Instant::now();
        let mut t = Tracker::new(Some(100), t0);
        assert!(t.update(t0, 0).is_some(), "first report at once");
        assert!(t.update(at(t0, 10), 5).is_none());
        assert!(t.update(at(t0, 149), 9).is_none());
        assert!(t.update(at(t0, 150), 10).is_some());
    }

    #[test]
    fn without_a_known_size_there_is_no_eta_and_the_end_is_marked_done() {
        let t0 = Instant::now();
        let mut t = Tracker::new(None, t0);
        let p = t.update(at(t0, 300), 300_000).unwrap();
        assert!(p.speed_bps > 0.0 && p.eta_seconds.is_none() && p.total.is_none());
        let done = t.finish(900_000);
        assert!(done.done && done.downloaded == 900_000 && done.eta_seconds.is_none());
    }

    #[test]
    fn a_stalled_download_has_no_eta_and_a_clock_that_goes_back_does_not_panic() {
        let t0 = Instant::now();
        let mut t = Tracker::new(Some(1_000), t0);
        let stalled = t.update(at(t0, 500), 0).unwrap();
        assert_eq!(stalled.eta_seconds, None);
        let _ = t.update(t0, 10); // earlier than the window start
        assert_eq!(t.finish(1_000).eta_seconds, Some(0));
    }
}
