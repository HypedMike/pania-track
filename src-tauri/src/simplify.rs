//! GPS track simplification.
//!
//! Reduces a track to the points that define its shape (Ramer–Douglas–Peucker): jitter while
//! standing still and points along straight stretches go; corners, bends and meaningful
//! elevation changes stay. The first and last points are always kept, so the distance and
//! duration of the track barely change. Every dropped point ends up within
//! `tolerance_m + min_step_m` of the simplified line (a standing-still point is up to
//! `min_step_m` from a point that is itself within `tolerance_m`). The result is a list of indices into the input, so
//! the caller keeps its original points (timestamps included) untouched.

use serde::Deserialize;

const EARTH_RADIUS_M: f64 = 6_371_000.0;

/// A track point. Other fields the frontend sends (timestamps) are ignored.
#[derive(Debug, Clone, Deserialize)]
pub struct Point {
    pub latitude: f64,
    pub longitude: f64,
    pub altitude: Option<f64>,
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Options {
    /// Largest sideways distance, in meters, the simplified line may be from a dropped point.
    pub tolerance_m: f64,
    /// Largest elevation error, in meters, at a dropped point.
    pub altitude_tolerance_m: f64,
    /// Points closer than this to the previously kept point count as standing still.
    pub min_step_m: f64,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            tolerance_m: 4.0,
            altitude_tolerance_m: 4.0,
            min_step_m: 2.0,
        }
    }
}

impl Options {
    /// Non-positive or non-finite values would divide by zero or keep everything; use defaults.
    fn sanitized(self) -> Self {
        let d = Self::default();
        let ok = |v: f64, fallback: f64| if v.is_finite() && v > 0.0 { v } else { fallback };
        Self {
            tolerance_m: ok(self.tolerance_m, d.tolerance_m),
            altitude_tolerance_m: ok(self.altitude_tolerance_m, d.altitude_tolerance_m),
            min_step_m: if self.min_step_m.is_finite() && self.min_step_m >= 0.0 {
                self.min_step_m
            } else {
                d.min_step_m
            },
        }
    }
}

/// Point in a local flat projection: meters east/north of the track's first point.
#[derive(Clone, Copy)]
struct Flat {
    x: f64,
    y: f64,
    /// Altitude, or NaN when the point has none.
    z: f64,
}

fn project(points: &[&Point]) -> Vec<Flat> {
    let first = points[0];
    let m_per_deg = EARTH_RADIUS_M.to_radians();
    let cos = first.latitude.to_radians().cos();
    points
        .iter()
        .map(|p| Flat {
            x: (p.longitude - first.longitude) * m_per_deg * cos,
            y: (p.latitude - first.latitude) * m_per_deg,
            z: p.altitude.filter(|a| a.is_finite()).unwrap_or(f64::NAN),
        })
        .collect()
}

/// How far `p` is from segment `a`–`b`: the larger of its sideways distance and its elevation
/// error against the altitude interpolated along the segment, each scaled by its tolerance.
/// A result above 1 means the point is needed.
fn deviation(p: Flat, a: Flat, b: Flat, tol_m: f64, tol_alt_m: f64) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let len2 = dx * dx + dy * dy;
    let t = if len2 == 0.0 {
        0.0
    } else {
        (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0)
    };
    let side = (p.x - (a.x + t * dx)).hypot(p.y - (a.y + t * dy)) / tol_m;
    if p.z.is_nan() || a.z.is_nan() || b.z.is_nan() {
        return side;
    }
    let vertical = (p.z - (a.z + t * (b.z - a.z))).abs() / tol_alt_m;
    side.max(vertical)
}

/// Indices (into `points`, ascending) of the points to keep.
///
/// Points with a non-finite latitude or longitude are never kept. The first and last valid
/// points are always kept.
pub fn simplify(points: &[Point], options: Options) -> Vec<usize> {
    let opts = options.sanitized();
    let valid: Vec<usize> = (0..points.len())
        .filter(|&i| points[i].latitude.is_finite() && points[i].longitude.is_finite())
        .collect();
    if valid.len() <= 2 {
        return valid;
    }

    // Drop jitter while standing still. Always keep the first and last point.
    let refs: Vec<&Point> = valid.iter().map(|&i| &points[i]).collect();
    let flat = project(&refs);
    let mut kept = vec![0usize];
    let mut last = flat[0];
    for i in 1..flat.len() - 1 {
        if (flat[i].x - last.x).hypot(flat[i].y - last.y) >= opts.min_step_m {
            kept.push(i);
            last = flat[i];
        }
    }
    kept.push(flat.len() - 1);
    if kept.len() <= 2 {
        return kept.into_iter().map(|i| valid[i]).collect();
    }
    let pts: Vec<Flat> = kept.iter().map(|&i| flat[i]).collect();

    // Iterative on purpose: tracks can have hundreds of thousands of points.
    let n = pts.len();
    let mut keep = vec![false; n];
    keep[0] = true;
    keep[n - 1] = true;
    let mut stack = vec![(0usize, n - 1)];
    while let Some((first, last)) = stack.pop() {
        let (mut worst, mut worst_at) = (0.0, None);
        for i in first + 1..last {
            let d = deviation(pts[i], pts[first], pts[last], opts.tolerance_m, opts.altitude_tolerance_m);
            if d > worst {
                worst = d;
                worst_at = Some(i);
            }
        }
        if let Some(at) = worst_at.filter(|_| worst > 1.0) {
            keep[at] = true;
            stack.push((first, at));
            stack.push((at, last));
        }
    }

    (0..n).filter(|&i| keep[i]).map(|i| valid[kept[i]]).collect()
}

/// Tauri command: indices of the points to keep, see [`simplify`].
#[tauri::command]
pub async fn simplify_track(points: Vec<Point>, options: Option<Options>) -> Vec<usize> {
    simplify(&points, options.unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pt(lat: f64, lon: f64, alt: Option<f64>) -> Point {
        Point { latitude: lat, longitude: lon, altitude: alt }
    }

    /// Deterministic noise in [-0.5, 0.5).
    fn noise(seed: &mut u64) -> f64 {
        *seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        ((*seed >> 33) as f64) / ((1u64 << 31) as f64) - 0.5
    }

    fn winding_climb() -> Vec<Point> {
        let mut seed = 7;
        (0..6000)
            .map(|i| {
                // A 2-minute stop in the middle: the position stops advancing.
                let k = if i > 3000 && i < 3080 { 3000 } else { i } as f64;
                pt(
                    43.7 + k * 4e-6 + 0.002 * (k / 400.0).sin() + noise(&mut seed) * 6e-6,
                    10.4 + k * 3e-6 + 0.003 * (k / 700.0).cos() + noise(&mut seed) * 6e-6,
                    Some(100.0 + 600.0 * (k / 6000.0 * std::f64::consts::PI).sin() + noise(&mut seed) * 3.0),
                )
            })
            .collect()
    }

    fn gain(points: &[Point], idx: &[usize]) -> f64 {
        let (mut g, mut r) = (0.0, points[idx[0]].altitude.unwrap());
        for &i in idx {
            let a = points[i].altitude.unwrap();
            if a - r >= 3.0 { g += a - r; r = a } else if r - a >= 3.0 { r = a }
        }
        g
    }

    #[test]
    fn keeps_shape_and_elevation_with_far_fewer_points() {
        let pts = winding_climb();
        let all: Vec<usize> = (0..pts.len()).collect();
        let out = simplify(&pts, Options::default());
        assert!(out.len() < pts.len() / 20, "kept {}", out.len());
        assert_eq!((out[0], *out.last().unwrap()), (0, pts.len() - 1));
        assert!(out.windows(2).all(|w| w[0] < w[1]), "indices must ascend");
        let (g0, g1) = (gain(&pts, &all), gain(&pts, &out));
        assert!((g0 - g1).abs() / g0 < 0.05, "gain {g0} -> {g1}");
    }

    #[test]
    fn every_dropped_point_is_within_tolerance_plus_min_step() {
        let pts = winding_climb();
        let out = simplify(&pts, Options::default());
        let refs: Vec<&Point> = pts.iter().collect();
        let flat = project(&refs);
        let mut worst: f64 = 0.0;
        for w in out.windows(2) {
            for i in w[0] + 1..w[1] {
                // Tolerance 1 m and no altitude check: the result is the sideways distance in meters.
                worst = worst.max(deviation(flat[i], flat[w[0]], flat[w[1]], 1.0, 1e12));
            }
        }
        assert!(worst <= 4.0 + 2.0, "worst sideways error {worst} m");
    }

    #[test]
    fn straight_line_collapses_to_endpoints() {
        let pts: Vec<Point> = (0..500).map(|i| pt(43.0 + i as f64 * 1e-5, 10.0, None)).collect();
        assert_eq!(simplify(&pts, Options::default()), vec![0, 499]);
    }

    #[test]
    fn a_corner_is_kept() {
        // ~5.5 m steps (above the standing-still filter), north then east.
        let mut pts: Vec<Point> = (0..100).map(|i| pt(43.0 + i as f64 * 5e-5, 10.0, None)).collect();
        pts.extend((1..100).map(|i| pt(43.0 + 99.0 * 5e-5, 10.0 + i as f64 * 5e-5, None)));
        assert_eq!(simplify(&pts, Options::default()), vec![0, 99, 198]);
    }

    #[test]
    fn a_steep_climb_on_a_straight_line_keeps_its_peak() {
        // Flat on the map, but up and down 30 m: elevation tolerance must keep the top.
        let pts: Vec<Point> = (0..101)
            .map(|i| pt(43.0 + i as f64 * 1e-5, 10.0, Some(30.0 - (i as f64 - 50.0).abs() * 0.6)))
            .collect();
        assert!(simplify(&pts, Options::default()).contains(&50));
    }

    #[test]
    fn degenerate_input() {
        assert!(simplify(&[], Options::default()).is_empty());
        assert_eq!(simplify(&[pt(1.0, 1.0, None)], Options::default()), vec![0]);
        let same = vec![pt(1.0, 1.0, None); 3];
        assert_eq!(simplify(&same, Options::default()), vec![0, 2]);
        let bad = vec![pt(1.0, 1.0, None), pt(f64::NAN, 1.0, None), pt(1.1, 1.1, None)];
        assert_eq!(simplify(&bad, Options::default()), vec![0, 2]);
    }

    #[test]
    fn bad_options_fall_back_to_defaults() {
        let pts = winding_climb();
        let bad = Options { tolerance_m: 0.0, altitude_tolerance_m: f64::NAN, min_step_m: -1.0 };
        assert_eq!(simplify(&pts, bad), simplify(&pts, Options::default()));
    }
}
