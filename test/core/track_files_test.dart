import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/gps/track_files.dart';
import 'package:pania/core/rust/analysis/geo.dart' show Activity;
import 'package:pania/features/trail/domain/gps_coordinate.dart';
import 'package:pania/features/trail/domain/trail.dart';

const gpx = '''<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Monte Serra</name></metadata>
  <wpt lat="43.75" lon="10.5"><name>Rifugio</name><ele>870</ele></wpt>
  <trk><name>Track name</name>
    <trkseg>
      <trkpt lat="43.7" lon="10.4"><ele>100</ele><time>2026-05-01T08:00:00Z</time></trkpt>
      <trkpt lat="43.71" lon="10.41"><ele>110.5</ele><time>2026-05-01T08:10:00Z</time></trkpt>
    </trkseg>
    <trkseg><trkpt lat="43.72" lon="10.42"/></trkseg>
  </trk>
</gpx>''';

const kml = '''<?xml version="1.0"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <Placemark><name>Summit</name><Point><coordinates>10.5,43.75,900</coordinates></Point></Placemark>
    <Placemark><name>Loop</name>
      <LineString><coordinates>10.4,43.7,100 10.41,43.71,110</coordinates></LineString>
    </Placemark>
    <Placemark><name>Timed</name>
      <gx:Track>
        <when>2026-05-01T08:00:00Z</when><gx:coord>10.4 43.7 100</gx:coord>
        <when>2026-05-01T08:01:00Z</when><gx:coord>10.41 43.71 105</gx:coord>
      </gx:Track>
    </Placemark>
  </Document>
</kml>''';

void main() {
  test('reads a GPX file: segments, times, altitudes, waypoints and the name', () {
    final t = parseTrackFile(gpx, 'a.gpx');
    expect(t.format, TrackFormat.gpx);
    expect(t.name, 'Monte Serra');
    expect(t.segments, hasLength(2));
    expect(t.segments.first.first.altitude, 100);
    expect(t.segments.first.first.timestamp, DateTime.utc(2026, 5, 1, 8));
    expect(t.segments.last.single.altitude, isNull);
    expect(t.waypoints.single.name, 'Rifugio');
    expect(t.waypoints.single.altitude, 870);
  });

  test('reads a KML file, including Google Earth timed tracks', () {
    final t = parseTrackFile(kml, 'a.kml');
    expect(t.format, TrackFormat.kml);
    expect(t.name, 'Loop');
    expect(t.segments, hasLength(2));
    expect(t.segments.first.first.latitude, 43.7);
    expect(t.segments.first.first.longitude, 10.4);
    expect(t.segments.last.last.timestamp, DateTime.utc(2026, 5, 1, 8, 1));
    expect(t.waypoints.single.name, 'Summit');
  });

  test('says what is wrong with a bad file', () {
    expect(() => parseTrackFile('not xml <', 'a.gpx'), throwsA(predicate((e) => '$e'.contains('XML'))));
    expect(() => parseTrackFile('<html/>', 'a.txt'), throwsA(predicate((e) => '$e'.contains('a.txt'))));
    expect(() => parseTrackFile('<gpx/>', 'a.gpx'), throwsA(predicate((e) => '$e'.contains('track points'))));
  });

  test('writes GPX that reads back the same', () {
    final trail = Trail(
      id: '1',
      name: 'A & B <c>',
      description: 'desc',
      source: TrailSource.recorded,
      activity: Activity.foot,
      coordinates: [
        GpsCoordinate(latitude: 43.7, longitude: 10.4, altitude: 100, timestamp: DateTime.utc(2026, 5, 1, 8)),
        const GpsCoordinate(latitude: 43.71, longitude: 10.41, altitude: 110.5),
      ],
      waypoints: const [Waypoint(latitude: 43.75, longitude: 10.5, name: 'Rifugio "Alto"')],
    );
    final back = parseTrackFile(buildGpx(trail), 'x.gpx');
    expect(back.name, 'A & B <c>');
    expect(back.segments.single, hasLength(2));
    expect(back.segments.single.first.timestamp, DateTime.utc(2026, 5, 1, 8));
    expect(back.segments.single.last.altitude, 110.5);
    expect(back.waypoints.single.name, 'Rifugio "Alto"');
  });

  test('file names are safe', () {
    final trail = const Trail(
      id: '1',
      name: 'Giro / del Monte: 5 km',
      source: TrailSource.recorded,
      activity: Activity.foot,
      coordinates: [],
      waypoints: [],
    );
    expect(gpxFileName(trail), 'Giro-del-Monte-5-km.gpx');
    expect(gpxFileName(trail.copyWith(name: '///')), 'trail.gpx');
  });
}
