//! Geohashes, used to find shared trails near a place.
//!
//! Relays match tags by exact value, so a trail publishes its start point's geohash at every
//! precision from 1 to [`MAX_PRECISION`] (a "ladder"), and a search asks for the cells around a
//! point at one precision. This relies on relays filtering on the single-letter `g` tag.

const BASE32: &[u8; 32] = b"0123456789bcdefghjkmnpqrstuvwxyz";
const EARTH_RADIUS_M: f64 = 6_371_000.0;

/// Finest precision published: a cell about 1.2 km × 0.6 km, enough to find a trail "nearby".
pub const MAX_PRECISION: usize = 6;

pub fn encode(lat: f64, lon: f64, precision: usize) -> String {
    let (mut lat_range, mut lon_range) = ((-90.0, 90.0), (-180.0, 180.0));
    let (mut hash, mut bit, mut ch, mut even) = (String::new(), 0, 0usize, true);
    while hash.len() < precision {
        let (range, value) = if even { (&mut lon_range, lon) } else { (&mut lat_range, lat) };
        let mid = (range.0 + range.1) / 2.0;
        ch <<= 1;
        if value >= mid {
            ch |= 1;
            range.0 = mid;
        } else {
            range.1 = mid;
        }
        even = !even;
        bit += 1;
        if bit == 5 {
            hash.push(BASE32[ch] as char);
            bit = 0;
            ch = 0;
        }
    }
    hash
}

/// The geohashes to put on a trail starting at this point: precision 1 up to [`MAX_PRECISION`].
pub fn ladder(lat: f64, lon: f64) -> Vec<String> {
    (1..=MAX_PRECISION).map(|p| encode(lat, lon, p)).collect()
}

/// Cell size in degrees (height, width) at a precision.
fn cell_degrees(precision: usize) -> (f64, f64) {
    let bits = precision * 5;
    let lon_bits = bits.div_ceil(2);
    let lat_bits = bits / 2;
    (180.0 / (1u64 << lat_bits) as f64, 360.0 / (1u64 << lon_bits) as f64)
}

/// The geohash cells (one precision, at most 9) that together cover a circle of `radius_km`
/// around a point, so a search can ask relays for `#g` in this list. Callers must still filter
/// by real distance: the cells cover more than the circle.
pub fn cells_around(lat: f64, lon: f64, radius_km: f64) -> Vec<String> {
    let radius_m = radius_km.max(0.1) * 1000.0;
    let m_per_deg = EARTH_RADIUS_M.to_radians();
    let cos = lat.to_radians().cos().max(0.01);
    // Finest precision whose cell is still at least `radius` in both directions: the circle then
    // fits within the 3×3 block of cells around its center.
    let precision = (1..=MAX_PRECISION)
        .rev()
        .find(|&p| {
            let (h, w) = cell_degrees(p);
            (h * m_per_deg).min(w * m_per_deg * cos) >= radius_m
        })
        .unwrap_or(1);
    let (h, w) = cell_degrees(precision);
    let mut cells = Vec::new();
    for dy in -1..=1 {
        for dx in -1..=1 {
            let la = (lat + dy as f64 * h).clamp(-89.999_999, 89.999_999);
            let mut lo = lon + dx as f64 * w;
            if lo > 180.0 { lo -= 360.0 }
            if lo < -180.0 { lo += 360.0 }
            let cell = encode(la, lo.clamp(-179.999_999, 179.999_999), precision);
            if !cells.contains(&cell) {
                cells.push(cell);
            }
        }
    }
    cells
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tracks::simplify::{haversine_m, Point};

    fn at(lat: f64, lon: f64) -> Point {
        Point { latitude: lat, longitude: lon, altitude: None }
    }

    /// Well-known reference values for geohash.
    #[test]
    fn encodes_known_points() {
        assert_eq!(encode(57.64911, 10.40744, 11), "u4pruydqqvj");
        assert_eq!(encode(42.605, -5.603, 5), "ezs42");
    }

    #[test]
    fn a_ladder_is_a_chain_of_prefixes() {
        let l = ladder(43.7, 10.4);
        assert_eq!(l.len(), MAX_PRECISION);
        for w in l.windows(2) {
            assert!(w[1].starts_with(&w[0]));
        }
    }

    #[test]
    fn cells_around_cover_every_point_inside_the_radius() {
        // Brute force: a grid of points within the radius must each fall in one of the cells.
        for &(lat, lon, radius) in &[(43.7, 10.4, 5.0), (43.7, 10.4, 25.0), (0.0, 0.0, 10.0), (-33.9, 151.2, 50.0), (64.1, -21.9, 10.0), (0.1, 179.95, 10.0)] {
            let cells = cells_around(lat, lon, radius);
            assert!(cells.len() <= 9 && !cells.is_empty());
            let p = cells[0].len();
            let center = at(lat, lon);
            for i in -20..=20 {
                for j in -20..=20 {
                    let (dlat, dlon) = (i as f64 * radius / 20.0 / 111.0, j as f64 * radius / 20.0 / 111.0 / lat.to_radians().cos().max(0.01));
                    let mut lo = lon + dlon;
                    if lo > 180.0 { lo -= 360.0 }
                    let q = at(lat + dlat, lo);
                    if haversine_m(&center, &q) <= radius * 1000.0 && q.latitude.abs() < 90.0 {
                        assert!(cells.contains(&encode(q.latitude, q.longitude, p)), "({lat},{lon}) r={radius}: {i},{j} not covered");
                    }
                }
            }
        }
    }

    #[test]
    fn a_trail_published_with_a_ladder_is_found_by_a_search_next_to_it() {
        let start = (43.7005, 10.4003);
        let published = ladder(start.0, start.1);
        let cells = cells_around(43.72, 10.43, 10.0); // ~3.7 km away
        assert!(published.iter().any(|g| cells.contains(g)));
        let far = cells_around(45.0, 12.0, 10.0);
        assert!(!published.iter().any(|g| far.contains(g)));
    }
}
