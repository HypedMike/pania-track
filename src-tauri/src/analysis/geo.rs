//! Shared input types and geometry for the track analysis modules.

use serde::{Deserialize, Serialize};

pub const EARTH_RADIUS_M: f64 = 6_371_000.0;
/// Meters per degree of latitude (a sphere, like [`haversine_m`]).
pub const METERS_PER_DEGREE: f64 = 111_195.0;

/// How the trail is covered. Changes how steepness affects speed and what counts as a GPS glitch.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Activity {
    #[default]
    Foot,
    Bike,
}

impl Activity {
    /// Faster than this between two fixes is not the person moving (m/s).
    pub fn max_speed_ms(self) -> f64 {
        match self {
            Activity::Foot => 8.0,
            Activity::Bike => 25.0,
        }
    }

    /// Typical speed on flat ground, used before there is any data of the person's own (m/s).
    pub fn default_flat_speed_ms(self) -> f64 {
        match self {
            Activity::Foot => 4_000.0 / 3600.0,
            Activity::Bike => 14_000.0 / 3600.0,
        }
    }
}

/// One GPS fix. Times are milliseconds since the epoch; the frontend converts its ISO strings.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Fix {
    pub latitude: f64,
    pub longitude: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub altitude: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub time_ms: Option<i64>,
    /// Horizontal accuracy reported by the GPS, in meters, when it was kept.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub accuracy: Option<f64>,
}

impl Fix {
    pub fn at(latitude: f64, longitude: f64) -> Self {
        Self {
            latitude,
            longitude,
            altitude: None,
            time_ms: None,
            accuracy: None,
        }
    }

    fn usable(&self) -> bool {
        self.latitude.is_finite()
            && self.longitude.is_finite()
            && self.latitude.abs() <= 90.0
            && self.longitude.abs() <= 180.0
    }
}

/// Drops fixes with impossible coordinates, which would poison every calculation.
pub fn sanitize(fixes: &[Fix]) -> Vec<Fix> {
    fixes.iter().filter(|f| f.usable()).cloned().collect()
}

pub fn haversine_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let (p1, p2) = (lat1.to_radians(), lat2.to_radians());
    let dlat = p2 - p1;
    let dlon = (lon2 - lon1).to_radians();
    let h = (dlat / 2.0).sin().powi(2) + p1.cos() * p2.cos() * (dlon / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * h.sqrt().min(1.0).asin()
}

pub fn distance_m(a: &Fix, b: &Fix) -> f64 {
    haversine_m(a.latitude, a.longitude, b.latitude, b.longitude)
}

/// Distance in meters from the start to each fix, so `result[0]` is 0.
pub fn cumulative_m(fixes: &[Fix]) -> Vec<f64> {
    let mut out = Vec::with_capacity(fixes.len());
    let mut total = 0.0;
    for (i, f) in fixes.iter().enumerate() {
        if i > 0 {
            total += distance_m(&fixes[i - 1], f);
        }
        out.push(total);
    }
    out
}

/// Altitude of every fix, smoothed over `window_m` of track and with gaps filled in by
/// interpolation. `None` when no fix has an altitude. GPS altitude is noisy (several meters),
/// so gradients and climbs are always computed from this and never from the raw values.
pub fn smoothed_altitudes(fixes: &[Fix], cum: &[f64], window_m: f64) -> Option<Vec<f64>> {
    let known: Vec<(f64, f64)> = fixes
        .iter()
        .zip(cum)
        .filter_map(|(f, &d)| f.altitude.filter(|a| a.is_finite()).map(|a| (d, a)))
        .collect();
    if known.is_empty() {
        return None;
    }
    // Moving average over the known fixes within ±window/2 (two pointers).
    let half = window_m / 2.0;
    let mut smoothed = Vec::with_capacity(known.len());
    let (mut lo, mut hi) = (0usize, 0usize);
    let mut sum = 0.0;
    for &(d, _) in &known {
        while hi < known.len() && known[hi].0 <= d + half {
            sum += known[hi].1;
            hi += 1;
        }
        while known[lo].0 < d - half {
            sum -= known[lo].1;
            lo += 1;
        }
        smoothed.push(sum / (hi - lo) as f64);
    }
    // Interpolate onto every fix by distance.
    let mut out = Vec::with_capacity(fixes.len());
    let mut k = 0usize;
    for &d in cum {
        while k + 1 < known.len() && known[k + 1].0 <= d {
            k += 1;
        }
        let value = if d <= known[0].0 {
            smoothed[0]
        } else if k + 1 >= known.len() {
            smoothed[known.len() - 1]
        } else {
            let (d0, d1) = (known[k].0, known[k + 1].0);
            let f = if d1 > d0 { (d - d0) / (d1 - d0) } else { 0.0 };
            smoothed[k] + (smoothed[k + 1] - smoothed[k]) * f
        };
        out.push(value);
    }
    Some(out)
}

/// A flat projection around a reference latitude: fine over the few km a trail covers.
#[derive(Debug, Clone, Copy)]
pub struct Local {
    kx: f64,
    ky: f64,
}

impl Local {
    pub fn around(latitude: f64) -> Self {
        Self {
            kx: METERS_PER_DEGREE * latitude.to_radians().cos().max(0.01),
            ky: METERS_PER_DEGREE,
        }
    }

    /// (east, north) in meters from the origin (0°, 0°); only differences matter.
    pub fn xy(&self, latitude: f64, longitude: f64) -> (f64, f64) {
        (longitude * self.kx, latitude * self.ky)
    }
}

/// Points every `spacing_m` along the track (always including the first and last), as (lat, lon)
/// plus the distance from the start. Used where tracks are compared by shape, not by fixes.
pub fn resample(fixes: &[Fix], spacing_m: f64) -> Vec<(f64, f64, f64)> {
    if fixes.is_empty() {
        return Vec::new();
    }
    let mut out = vec![(fixes[0].latitude, fixes[0].longitude, 0.0)];
    let mut along = 0.0;
    let mut next = spacing_m;
    for w in fixes.windows(2) {
        let seg = distance_m(&w[0], &w[1]);
        while seg > 0.0 && next <= along + seg {
            let f = (next - along) / seg;
            out.push((
                w[0].latitude + (w[1].latitude - w[0].latitude) * f,
                w[0].longitude + (w[1].longitude - w[0].longitude) * f,
                next,
            ));
            next += spacing_m;
        }
        along += seg;
    }
    let last = fixes[fixes.len() - 1].clone();
    if fixes.len() > 1 && out.last().map(|p| along - p.2 > 1.0).unwrap_or(true) {
        out.push((last.latitude, last.longitude, along));
    }
    out
}

#[cfg(test)]
pub mod test_support {
    use super::*;

    /// A walk north from (46, 11) at `speed_ms`, one fix every `interval_s`, for `duration_s`.
    pub fn walk(speed_ms: f64, interval_s: i64, duration_s: i64, start_ms: i64) -> Vec<Fix> {
        let mut out = Vec::new();
        let mut t = 0;
        while t <= duration_s {
            out.push(Fix {
                latitude: 46.0 + speed_ms * t as f64 / METERS_PER_DEGREE,
                longitude: 11.0,
                altitude: None,
                time_ms: Some(start_ms + t * 1000),
                accuracy: None,
            });
            t += interval_s;
        }
        out
    }

    /// Meters north of (46, 11) as a latitude.
    pub fn north(m: f64) -> f64 {
        46.0 + m / METERS_PER_DEGREE
    }
}

#[cfg(test)]
mod tests {
    use super::test_support::*;
    use super::*;

    #[test]
    fn haversine_matches_the_degree_length() {
        assert!((haversine_m(46.0, 11.0, 47.0, 11.0) - METERS_PER_DEGREE).abs() < 100.0);
        assert_eq!(haversine_m(46.0, 11.0, 46.0, 11.0), 0.0);
    }

    #[test]
    fn cumulative_starts_at_zero_and_grows() {
        let fixes = walk(1.0, 10, 100, 0);
        let cum = cumulative_m(&fixes);
        assert_eq!(cum[0], 0.0);
        assert!((cum[cum.len() - 1] - 100.0).abs() < 0.5);
        assert!(cum.windows(2).all(|w| w[1] >= w[0]));
    }

    #[test]
    fn sanitize_drops_impossible_coordinates() {
        let fixes = vec![
            Fix::at(46.0, 11.0),
            Fix::at(f64::NAN, 11.0),
            Fix::at(91.0, 0.0),
            Fix::at(46.1, 11.1),
        ];
        assert_eq!(sanitize(&fixes).len(), 2);
    }

    #[test]
    fn altitude_smoothing_flattens_noise_and_keeps_trends() {
        let mut fixes = walk(1.0, 5, 1000, 0);
        for (i, f) in fixes.iter_mut().enumerate() {
            let noise = if i % 2 == 0 { 3.0 } else { -3.0 };
            f.altitude = Some(100.0 + i as f64 * 0.5 + noise);
        }
        let cum = cumulative_m(&fixes);
        let smooth = smoothed_altitudes(&fixes, &cum, 60.0).unwrap();
        // The zigzag of ±3 m is gone, the slope (0.1 m per m) is still there.
        let mid = fixes.len() / 2;
        assert!((smooth[mid + 1] - smooth[mid]).abs() < 1.0);
        assert!(smooth[fixes.len() - 5] - smooth[5] > 80.0);
    }

    #[test]
    fn altitude_gaps_are_interpolated_and_missing_altitude_gives_none() {
        let mut fixes = walk(1.0, 10, 100, 0);
        assert!(smoothed_altitudes(&fixes, &cumulative_m(&fixes), 20.0).is_none());
        fixes[0].altitude = Some(100.0);
        fixes[10].altitude = Some(110.0);
        let cum = cumulative_m(&fixes);
        let smooth = smoothed_altitudes(&fixes, &cum, 1.0).unwrap();
        assert!((smooth[5] - 105.0).abs() < 0.5);
    }

    #[test]
    fn resample_spaces_points_evenly_and_keeps_the_end() {
        let fixes = walk(1.0, 10, 100, 0);
        let points = resample(&fixes, 20.0);
        assert_eq!(points.len(), 6);
        assert!((points[1].2 - 20.0).abs() < 1e-9);
        assert!((points.last().unwrap().2 - 100.0).abs() < 1.0);
    }

    #[test]
    fn local_projection_measures_meters() {
        let l = Local::around(46.0);
        let (x1, y1) = l.xy(46.0, 11.0);
        let (x2, y2) = l.xy(46.001, 11.0);
        assert!(((y2 - y1) - 111.195).abs() < 0.01);
        assert!((x2 - x1).abs() < 1e-9);
    }
}
