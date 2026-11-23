//! Minimal GPX reading and writing for shared tracks.
//!
//! Writing never includes timestamps: a published trail should not reveal *when* someone was
//! out. Reading is defensive, since the input comes from strangers over the network.

use super::simplify::Point;
use quick_xml::{events::Event, Reader};
use serde::{Deserialize, Serialize};

/// Most points a parsed track may have; a longer one is rejected, not truncated.
pub const MAX_POINTS: usize = 100_000;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Waypoint {
    pub latitude: f64,
    pub longitude: f64,
    pub altitude: Option<f64>,
    #[serde(default)]
    pub name: String,
}

#[derive(Debug, Clone, Default)]
pub struct Parsed {
    pub name: Option<String>,
    pub description: Option<String>,
    pub points: Vec<Point>,
    pub waypoints: Vec<Waypoint>,
}

fn escape(text: &str) -> String {
    text.chars()
        .filter(|c| !c.is_control() || matches!(c, '\n' | '\t'))
        .map(|c| match c {
            '&' => "&amp;".to_string(),
            '<' => "&lt;".to_string(),
            '>' => "&gt;".to_string(),
            '"' => "&quot;".to_string(),
            c => c.to_string(),
        })
        .collect()
}

/// A GPX 1.1 document with one track segment and the given waypoints. No timestamps.
pub fn write_gpx(name: &str, description: &str, points: &[Point], waypoints: &[Waypoint]) -> String {
    let mut out = String::with_capacity(points.len() * 56 + 512);
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    out.push_str("<gpx version=\"1.1\" creator=\"pania\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n");
    for w in waypoints {
        out.push_str(&format!("<wpt lat=\"{:.6}\" lon=\"{:.6}\">", w.latitude, w.longitude));
        if let Some(ele) = w.altitude.filter(|a| a.is_finite()) {
            out.push_str(&format!("<ele>{ele:.1}</ele>"));
        }
        out.push_str(&format!("<name>{}</name></wpt>\n", escape(&w.name)));
    }
    out.push_str(&format!("<trk><name>{}</name>", escape(name)));
    if !description.is_empty() {
        out.push_str(&format!("<desc>{}</desc>", escape(description)));
    }
    out.push_str("<trkseg>\n");
    for p in points {
        out.push_str(&format!("<trkpt lat=\"{:.6}\" lon=\"{:.6}\">", p.latitude, p.longitude));
        if let Some(ele) = p.altitude.filter(|a| a.is_finite()) {
            out.push_str(&format!("<ele>{ele:.1}</ele>"));
        }
        out.push_str("</trkpt>\n");
    }
    out.push_str("</trkseg></trk>\n</gpx>\n");
    out
}

fn coordinate_attrs(e: &quick_xml::events::BytesStart<'_>) -> Result<(f64, f64), String> {
    let (mut lat, mut lon) = (None, None);
    for attr in e.attributes().flatten() {
        let value = attr.unescape_value().map_err(|e| e.to_string())?;
        match attr.key.local_name().as_ref() {
            b"lat" => lat = value.trim().parse::<f64>().ok(),
            b"lon" => lon = value.trim().parse::<f64>().ok(),
            _ => {}
        }
    }
    match (lat, lon) {
        (Some(lat), Some(lon)) if lat.is_finite() && lon.is_finite() && lat.abs() <= 90.0 && lon.abs() <= 180.0 => {
            Ok((lat, lon))
        }
        _ => Err("point without valid lat/lon".into()),
    }
}

/// Resolves the five predefined XML entities and numeric references; anything else (custom
/// entities, which could be used for tricks) resolves to nothing.
fn entity(name: &str) -> Option<char> {
    match name {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        n => {
            let digits = n.strip_prefix('#')?;
            let code = match digits.strip_prefix('x') {
                Some(hex) => u32::from_str_radix(hex, 16).ok()?,
                None => digits.parse::<u32>().ok()?,
            };
            char::from_u32(code)
        }
    }
}

/// Reads the track points (all segments, in order), waypoints, and the track's name/description.
pub fn parse_gpx(text: &str) -> Result<Parsed, String> {
    let mut reader = Reader::from_str(text);
    let mut parsed = Parsed::default();
    let mut stack: Vec<String> = Vec::new();
    let mut buf = String::new();
    let mut current: Option<Point> = None;
    let mut current_wpt: Option<Waypoint> = None;

    // Text of an element is only complete at its end tag, because entity references such as
    // `&amp;` arrive as separate events.
    let finish = |name: &str, parent: Option<&str>, text: &str, parsed: &mut Parsed,
                      current: &mut Option<Point>, current_wpt: &mut Option<Waypoint>|
     -> Result<(), String> {
        let text = text.trim();
        match (name, parent) {
            ("ele", Some("trkpt")) => {
                if let Some(p) = current.as_mut() {
                    p.altitude = text.parse::<f64>().ok().filter(|a| a.is_finite());
                }
            }
            ("ele", Some("wpt")) => {
                if let Some(w) = current_wpt.as_mut() {
                    w.altitude = text.parse::<f64>().ok().filter(|a| a.is_finite());
                }
            }
            ("name", Some("wpt")) => {
                if let Some(w) = current_wpt.as_mut() {
                    w.name = text.to_string();
                }
            }
            ("name", Some("trk")) if parsed.name.is_none() => parsed.name = Some(text.to_string()),
            ("desc", Some("trk")) if parsed.description.is_none() => parsed.description = Some(text.to_string()),
            ("trkpt", _) => {
                if let Some(p) = current.take() {
                    if parsed.points.len() >= MAX_POINTS {
                        return Err("track has too many points".into());
                    }
                    parsed.points.push(p);
                }
            }
            ("wpt", _) => {
                if let Some(w) = current_wpt.take() {
                    parsed.waypoints.push(w);
                }
            }
            _ => {}
        }
        Ok(())
    };

    loop {
        match reader.read_event().map_err(|e| format!("invalid GPX: {e}"))? {
            Event::Start(e) => {
                let name = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                match name.as_str() {
                    "trkpt" => {
                        let (latitude, longitude) = coordinate_attrs(&e)?;
                        current = Some(Point { latitude, longitude, altitude: None });
                    }
                    "wpt" => {
                        let (latitude, longitude) = coordinate_attrs(&e)?;
                        current_wpt = Some(Waypoint { latitude, longitude, altitude: None, name: String::new() });
                    }
                    _ => {}
                }
                buf.clear();
                stack.push(name);
            }
            Event::Empty(e) => {
                // A self-closing point: `<trkpt lat=".." lon=".."/>`.
                let name = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                match name.as_str() {
                    "trkpt" => {
                        let (latitude, longitude) = coordinate_attrs(&e)?;
                        current = Some(Point { latitude, longitude, altitude: None });
                        finish("trkpt", None, "", &mut parsed, &mut current, &mut current_wpt)?;
                    }
                    "wpt" => {
                        let (latitude, longitude) = coordinate_attrs(&e)?;
                        current_wpt = Some(Waypoint { latitude, longitude, altitude: None, name: String::new() });
                        finish("wpt", None, "", &mut parsed, &mut current, &mut current_wpt)?;
                    }
                    _ => {}
                }
            }
            Event::End(_) => {
                if let Some(name) = stack.pop() {
                    let parent = stack.last().map(String::as_str);
                    finish(&name, parent, &buf, &mut parsed, &mut current, &mut current_wpt)?;
                    buf.clear();
                }
            }
            Event::Text(t) => buf.push_str(&t.decode().map_err(|e| e.to_string())?),
            Event::GeneralRef(r) => {
                if let Some(c) = r.decode().ok().and_then(|n| entity(&n)) {
                    buf.push(c);
                }
            }
            Event::Eof => break,
            _ => {}
        }
        if buf.len() > 100_000 {
            return Err("text too long".into());
        }
    }
    if !stack.is_empty() {
        return Err("invalid GPX: unclosed element".into());
    }
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pt(lat: f64, lon: f64, alt: Option<f64>) -> Point {
        Point { latitude: lat, longitude: lon, altitude: alt }
    }

    #[test]
    fn round_trips_points_waypoints_and_text() {
        let points = vec![pt(43.7, 10.4, Some(100.0)), pt(43.71, 10.41, None), pt(43.72, 10.42, Some(150.5))];
        let wpts = vec![Waypoint { latitude: 43.71, longitude: 10.41, altitude: Some(120.0), name: "Rifugio <A&B>".into() }];
        let gpx = write_gpx("Monte \"Serra\" & co", "ridge <walk>", &points, &wpts);
        let back = parse_gpx(&gpx).unwrap();
        assert_eq!(back.name.as_deref(), Some("Monte \"Serra\" & co"));
        assert_eq!(back.description.as_deref(), Some("ridge <walk>"));
        assert_eq!(back.points.len(), 3);
        assert_eq!(back.points[1].altitude, None);
        assert_eq!(back.points[2].altitude, Some(150.5));
        assert!((back.points[0].latitude - 43.7).abs() < 1e-9);
        assert_eq!(back.waypoints, vec![Waypoint { name: "Rifugio <A&B>".into(), ..wpts[0].clone() }]);
    }

    #[test]
    fn written_gpx_has_no_timestamps() {
        let gpx = write_gpx("t", "", &[pt(1.0, 1.0, None), pt(1.1, 1.1, None)], &[]);
        assert!(!gpx.contains("<time"));
    }

    #[test]
    fn rejects_bad_coordinates_and_broken_xml() {
        assert!(parse_gpx("<gpx><trk><trkseg><trkpt lat=\"91\" lon=\"0\"/></trkseg></trk></gpx>").is_err());
        assert!(parse_gpx("<gpx><trk><trkseg><trkpt lat=\"x\" lon=\"0\"/></trkseg></trk></gpx>").is_err());
        assert!(parse_gpx("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"1\"></trkseg>").is_err());
    }

    #[test]
    fn entities_are_not_expanded_into_anything_dangerous() {
        let evil = "<?xml version=\"1.0\"?><!DOCTYPE x [<!ENTITY a SYSTEM \"file:///etc/passwd\">]><gpx><trk><name>&a;</name><trkseg><trkpt lat=\"1\" lon=\"1\"/><trkpt lat=\"2\" lon=\"2\"/></trkseg></trk></gpx>";
        // Either it errors or the entity stays unresolved; it must never contain file contents.
        if let Ok(p) = parse_gpx(evil) {
            assert!(!p.name.unwrap_or_default().contains("root:"));
        }
    }

    #[test]
    fn several_segments_are_joined_in_order_and_empty_input_is_empty() {
        let two = "<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"1\"/></trkseg><trkseg><trkpt lat=\"2\" lon=\"2\"/></trkseg></trk></gpx>";
        assert_eq!(parse_gpx(two).unwrap().points.len(), 2);
        assert!(parse_gpx("").unwrap().points.is_empty());
    }
}
