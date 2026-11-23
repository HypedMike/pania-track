//! When the person goes out and how the weather affects their pace: time of day, weekday and
//! month, and the link between temperature or rain and slope-adjusted speed.

use serde::{Deserialize, Serialize};

use super::geo::{Activity, Fix, sanitize};
use super::motion::analyze;
use super::pace::track_adjusted_speed;

/// Rain heavier than this over the walk counts as wet (mm).
pub const WET_MM: f64 = 0.5;
/// Temperature bands in °C: below the first edge, between edges, and above the last.
const TEMP_EDGES: [f64; 3] = [5.0, 15.0, 25.0];

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Weather {
    pub temp_c: f64,
    pub precip_mm: f64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TrailInput {
    #[serde(default)]
    pub activity: Activity,
    pub fixes: Vec<Fix>,
    /// Conditions around the start of the walk, when they were looked up.
    #[serde(default)]
    pub weather: Option<Weather>,
}

#[derive(Debug, Clone, Default, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Bucket {
    pub trails: usize,
    pub distance_m: f64,
    pub moving_s: f64,
    /// Slope-adjusted speed, weighted by moving time.
    pub adjusted_speed_ms: Option<f64>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TempBand {
    /// `None` is open-ended.
    pub from_c: Option<f64>,
    pub to_c: Option<f64>,
    pub trails: usize,
    pub adjusted_speed_ms: Option<f64>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct WeatherEffect {
    pub trails: usize,
    /// Pearson correlation of temperature with slope-adjusted speed (-1…1), from five trails up.
    pub temp_correlation: Option<f64>,
    /// How much slower (negative) or faster the person is on wet days than dry ones, in percent.
    pub wet_vs_dry_pct: Option<f64>,
    pub wet_trails: usize,
    pub bands: Vec<TempBand>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Patterns {
    /// Trails with times, which the rest is based on.
    pub trails: usize,
    /// 24 buckets, hour of the day at the start.
    pub by_hour: Vec<Bucket>,
    /// 7 buckets, Monday first.
    pub by_weekday: Vec<Bucket>,
    /// 12 buckets, January first.
    pub by_month: Vec<Bucket>,
    pub busiest_hour: Option<usize>,
    pub busiest_month: Option<usize>,
    /// Hour and month with the best slope-adjusted speed (from two trails up).
    pub fastest_hour: Option<usize>,
    pub fastest_month: Option<usize>,
    pub weather: Option<WeatherEffect>,
}

/// Local hour (0–23), weekday (Monday = 0) and month (January = 0) of a time, for a fixed UTC offset.
pub fn local_parts(time_ms: i64, tz_offset_min: i32) -> (usize, usize, usize) {
    let local = time_ms.div_euclid(1000) + tz_offset_min as i64 * 60;
    let days = local.div_euclid(86_400);
    let secs = local.rem_euclid(86_400);
    let hour = (secs / 3600) as usize;
    // 1970-01-01 was a Thursday (Monday = 0 → 3).
    let weekday = (days + 3).rem_euclid(7) as usize;
    // Civil date from day count (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let month = if mp < 10 { mp + 3 } else { mp - 9 }; // 1–12
    let _ = era;
    (hour, weekday, (month - 1) as usize)
}

struct Row {
    hour: usize,
    weekday: usize,
    month: usize,
    distance_m: f64,
    moving_s: f64,
    speed: Option<f64>,
    weather: Option<Weather>,
}

fn weighted(rows: &[&Row]) -> Option<f64> {
    let (sum, w) = rows
        .iter()
        .filter_map(|r| r.speed.map(|s| (s * r.moving_s, r.moving_s)))
        .fold((0.0, 0.0), |(a, b), (x, y)| (a + x, b + y));
    (w > 0.0).then(|| sum / w)
}

fn bucket(rows: &[&Row]) -> Bucket {
    Bucket {
        trails: rows.len(),
        distance_m: rows.iter().map(|r| r.distance_m).sum(),
        moving_s: rows.iter().map(|r| r.moving_s).sum(),
        adjusted_speed_ms: weighted(rows),
    }
}

fn pearson(xs: &[f64], ys: &[f64]) -> Option<f64> {
    let n = xs.len() as f64;
    if xs.len() < 5 {
        return None;
    }
    let (mx, my) = (xs.iter().sum::<f64>() / n, ys.iter().sum::<f64>() / n);
    let (mut sxy, mut sxx, mut syy) = (0.0, 0.0, 0.0);
    for (x, y) in xs.iter().zip(ys) {
        sxy += (x - mx) * (y - my);
        sxx += (x - mx).powi(2);
        syy += (y - my).powi(2);
    }
    if sxx <= 0.0 || syy <= 0.0 {
        return None;
    }
    Some(sxy / (sxx * syy).sqrt())
}

fn weather_effect(rows: &[&Row]) -> Option<WeatherEffect> {
    let with: Vec<&&Row> = rows
        .iter()
        .filter(|r| r.weather.is_some() && r.speed.is_some())
        .collect();
    if with.is_empty() {
        return None;
    }
    let temps: Vec<f64> = with.iter().map(|r| r.weather.unwrap().temp_c).collect();
    let speeds: Vec<f64> = with.iter().map(|r| r.speed.unwrap()).collect();
    let wet: Vec<&Row> = with
        .iter()
        .filter(|r| r.weather.unwrap().precip_mm >= WET_MM)
        .map(|r| **r)
        .collect();
    let dry: Vec<&Row> = with
        .iter()
        .filter(|r| r.weather.unwrap().precip_mm < WET_MM)
        .map(|r| **r)
        .collect();
    let wet_vs_dry_pct = match (weighted(&wet), weighted(&dry)) {
        (Some(w), Some(d)) if wet.len() >= 2 && dry.len() >= 2 && d > 0.0 => {
            Some((w / d - 1.0) * 100.0)
        }
        _ => None,
    };
    let bands = (0..=TEMP_EDGES.len())
        .map(|b| {
            let from = if b == 0 {
                None
            } else {
                Some(TEMP_EDGES[b - 1])
            };
            let to = TEMP_EDGES.get(b).copied();
            let inside: Vec<&Row> = with
                .iter()
                .filter(|r| {
                    let t = r.weather.unwrap().temp_c;
                    from.map_or(true, |f| t >= f) && to.map_or(true, |u| t < u)
                })
                .map(|r| **r)
                .collect();
            TempBand {
                from_c: from,
                to_c: to,
                trails: inside.len(),
                adjusted_speed_ms: weighted(&inside),
            }
        })
        .collect();
    Some(WeatherEffect {
        trails: with.len(),
        temp_correlation: pearson(&temps, &speeds),
        wet_vs_dry_pct,
        wet_trails: wet.len(),
        bands,
    })
}

fn best_of(
    buckets: &[Bucket],
    by: impl Fn(&Bucket) -> Option<f64>,
    min_trails: usize,
) -> Option<usize> {
    buckets
        .iter()
        .enumerate()
        .filter(|(_, b)| b.trails >= min_trails)
        .filter_map(|(i, b)| by(b).map(|v| (i, v)))
        .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap())
        .map(|(i, _)| i)
}

pub fn analyze_patterns(trails: &[TrailInput], tz_offset_min: i32) -> Patterns {
    let mut rows = Vec::new();
    for t in trails {
        let fixes = sanitize(&t.fixes);
        let m = analyze(&fixes);
        let Some(start) = fixes.first().and_then(|f| f.time_ms).filter(|_| m.has_time) else {
            continue;
        };
        let (hour, weekday, month) = local_parts(start, tz_offset_min);
        rows.push(Row {
            hour,
            weekday,
            month,
            distance_m: m.distance_m,
            moving_s: m.moving_s,
            speed: track_adjusted_speed(t.activity, &m),
            weather: t
                .weather
                .filter(|w| w.temp_c.is_finite() && w.precip_mm.is_finite()),
        });
    }
    let group = |n: usize, key: &dyn Fn(&Row) -> usize| -> Vec<Bucket> {
        (0..n)
            .map(|i| bucket(&rows.iter().filter(|r| key(r) == i).collect::<Vec<_>>()))
            .collect()
    };
    let by_hour = group(24, &|r| r.hour);
    let by_weekday = group(7, &|r| r.weekday);
    let by_month = group(12, &|r| r.month);
    let most = |b: &[Bucket]| best_of(b, |x| Some(x.trails as f64 * 1e9 + x.distance_m), 1);
    let all: Vec<&Row> = rows.iter().collect();
    Patterns {
        trails: rows.len(),
        busiest_hour: most(&by_hour),
        busiest_month: most(&by_month),
        fastest_hour: best_of(&by_hour, |b| b.adjusted_speed_ms, 2),
        fastest_month: best_of(&by_month, |b| b.adjusted_speed_ms, 2),
        weather: weather_effect(&all),
        by_hour,
        by_weekday,
        by_month,
    }
}

#[cfg(test)]
mod tests {
    use super::super::geo::test_support::*;
    use super::*;

    const DAY: i64 = 86_400_000;
    /// 2024-03-15 (a Friday) 00:00 UTC.
    const FRI_2024_03_15: i64 = 1_710_460_800_000;

    fn walk_at(start_ms: i64, speed: f64, weather: Option<Weather>) -> TrailInput {
        TrailInput {
            activity: Activity::Foot,
            fixes: walk(speed, 5, 1800, start_ms),
            weather,
        }
    }

    #[test]
    fn local_parts_gives_hour_weekday_and_month() {
        assert_eq!(local_parts(0, 0), (0, 3, 0)); // Thursday 1 Jan 1970
        assert_eq!(local_parts(FRI_2024_03_15 + 9 * 3_600_000, 0), (9, 4, 2));
        // +2 h offset moves the hour, and past midnight the weekday
        assert_eq!(local_parts(FRI_2024_03_15 + 23 * 3_600_000, 120), (1, 5, 2));
        // before the epoch still works (Wed 31 Dec 1969)
        assert_eq!(local_parts(-3_600_000, 0), (23, 2, 11));
        // leap day
        assert_eq!(local_parts(FRI_2024_03_15 - 15 * DAY, 0).2, 1);
    }

    #[test]
    fn buckets_count_when_the_person_goes_out() {
        let trails = vec![
            walk_at(FRI_2024_03_15 + 8 * 3_600_000, 1.2, None),
            walk_at(FRI_2024_03_15 + DAY + 8 * 3_600_000, 1.2, None),
            walk_at(FRI_2024_03_15 + 2 * DAY + 15 * 3_600_000, 1.2, None),
        ];
        let p = analyze_patterns(&trails, 0);
        assert_eq!(p.trails, 3);
        assert_eq!(p.by_hour[8].trails, 2);
        assert_eq!(p.by_hour[15].trails, 1);
        assert_eq!(p.busiest_hour, Some(8));
        assert_eq!(p.busiest_month, Some(2));
        assert_eq!(p.by_weekday[4].trails, 1); // Friday
        assert_eq!(p.by_weekday[5].trails, 1);
        assert_eq!(p.by_hour.len() + p.by_weekday.len() + p.by_month.len(), 43);
        assert!((p.by_hour[8].distance_m - 2.0 * 1.2 * 1800.0).abs() < 5.0);
    }

    #[test]
    fn the_fastest_hour_needs_two_trails() {
        let trails = vec![
            walk_at(FRI_2024_03_15 + 7 * 3_600_000, 1.5, None),
            walk_at(FRI_2024_03_15 + DAY + 7 * 3_600_000, 1.5, None),
            walk_at(FRI_2024_03_15 + 2 * DAY + 18 * 3_600_000, 0.8, None),
            walk_at(FRI_2024_03_15 + 3 * DAY + 18 * 3_600_000, 0.8, None),
            walk_at(FRI_2024_03_15 + 4 * DAY + 12 * 3_600_000, 3.0, None), // alone at noon
        ];
        let p = analyze_patterns(&trails, 0);
        assert_eq!(p.fastest_hour, Some(7));
    }

    #[test]
    fn trails_without_times_are_left_out() {
        let t = TrailInput {
            activity: Activity::Foot,
            fixes: (0..10)
                .map(|i| Fix::at(north(i as f64 * 10.0), 11.0))
                .collect(),
            weather: None,
        };
        let p = analyze_patterns(&[t], 0);
        assert_eq!(p.trails, 0);
        assert!(p.busiest_hour.is_none() && p.weather.is_none());
    }

    #[test]
    fn heat_slows_the_person_down_and_rain_too() {
        // Faster when it is cool: 8 °C → 1.5 m/s … 30 °C → 0.9 m/s, with two wet, slow days.
        let mk = |i: i64, speed: f64, temp: f64, rain: f64| {
            walk_at(
                FRI_2024_03_15 + i * DAY + 9 * 3_600_000,
                speed,
                Some(Weather {
                    temp_c: temp,
                    precip_mm: rain,
                }),
            )
        };
        let trails = vec![
            mk(0, 1.5, 8.0, 0.0),
            mk(1, 1.4, 12.0, 0.0),
            mk(2, 1.3, 18.0, 0.0),
            mk(3, 1.1, 27.0, 0.0),
            mk(4, 0.9, 30.0, 0.0),
            mk(5, 1.0, 10.0, 4.0),
            mk(6, 1.0, 11.0, 2.0),
        ];
        let w = analyze_patterns(&trails, 0).weather.unwrap();
        assert_eq!(w.trails, 7);
        assert_eq!(w.wet_trails, 2);
        assert!(
            w.temp_correlation.unwrap() < -0.3,
            "{:?}",
            w.temp_correlation
        );
        assert!(w.wet_vs_dry_pct.unwrap() < -10.0, "{:?}", w.wet_vs_dry_pct);
        assert_eq!(w.bands.len(), 4);
        assert_eq!(w.bands.iter().map(|b| b.trails).sum::<usize>(), 7);
        let hot = w.bands.last().unwrap();
        assert_eq!((hot.from_c, hot.to_c, hot.trails), (Some(25.0), None, 2));
        assert!(hot.adjusted_speed_ms.unwrap() < w.bands[1].adjusted_speed_ms.unwrap());
    }

    #[test]
    fn a_correlation_needs_five_trails_and_some_variation() {
        assert!(pearson(&[1.0, 2.0, 3.0], &[1.0, 2.0, 3.0]).is_none());
        assert!(pearson(&[1.0; 6], &[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]).is_none());
        let r = pearson(&[1.0, 2.0, 3.0, 4.0, 5.0], &[2.0, 4.0, 6.0, 8.0, 10.0]).unwrap();
        assert!((r - 1.0).abs() < 1e-9);
    }
}
