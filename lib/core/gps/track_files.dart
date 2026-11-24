import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

import '../../features/trail/domain/gps_coordinate.dart';
import '../../features/trail/domain/trail.dart';
import '../i18n/i18n.dart';

enum TrackFormat { gpx, kml }

class ParsedTrack {
  const ParsedTrack({required this.format, required this.segments, required this.waypoints, this.name});

  final TrackFormat format;

  /// Name found in the file's metadata, if any.
  final String? name;
  final List<List<GpsCoordinate>> segments;
  final List<Waypoint> waypoints;
}

/// Descendants by local name, ignoring XML namespaces.
Iterable<XmlElement> _all(XmlNode root, String name) => root.descendantElements.where((e) => e.name.local == name);

String? _childText(XmlElement el, String name) {
  for (final c in el.childElements) {
    if (c.name.local == name) {
      final text = c.innerText.trim();
      return text.isEmpty ? null : text;
    }
  }
  return null;
}

double? _num(String? value) {
  if (value == null || value.isEmpty) return null;
  final n = double.tryParse(value);
  return n != null && n.isFinite ? n : null;
}

DateTime? _time(String? value) => value == null ? null : DateTime.tryParse(value)?.toUtc();

GpsCoordinate? _gpxPoint(XmlElement el) {
  final lat = _num(el.getAttribute('lat'));
  final lon = _num(el.getAttribute('lon'));
  if (lat == null || lon == null) return null;
  return GpsCoordinate(
    latitude: lat,
    longitude: lon,
    altitude: _num(_childText(el, 'ele')),
    timestamp: _time(_childText(el, 'time')),
  );
}

ParsedTrack _parseGpx(XmlDocument doc) {
  final trks = _all(doc, 'trk').toList();
  final lines = trks.isNotEmpty ? trks.expand((t) => _all(t, 'trkseg')).toList() : _all(doc, 'rte').toList();
  final pointTag = trks.isNotEmpty ? 'trkpt' : 'rtept';
  final segments = [
    for (final line in lines) [for (final el in _all(line, pointTag)) ?_gpxPoint(el)],
  ].where((s) => s.isNotEmpty).toList();

  final waypoints = <Waypoint>[];
  var i = 0;
  for (final el in _all(doc, 'wpt')) {
    final pt = _gpxPoint(el);
    if (pt != null) waypoints.add(Waypoint.at(pt, _childText(el, 'name') ?? 'Waypoint ${i + 1}'));
    i++;
  }

  final metaName = _all(doc, 'metadata').map((m) => _childText(m, 'name')).whereType<String>().firstOrNull;
  final name = metaName ?? (trks.isNotEmpty ? _childText(trks.first, 'name') : null);
  return ParsedTrack(format: TrackFormat.gpx, name: name, segments: segments, waypoints: waypoints);
}

List<GpsCoordinate> _kmlCoordinates(String text) {
  final out = <GpsCoordinate>[];
  for (final triplet in text.trim().split(RegExp(r'\s+'))) {
    final parts = triplet.split(',').map(double.tryParse).toList();
    if (parts.length < 2 || parts[0] == null || parts[1] == null) continue;
    out.add(GpsCoordinate(latitude: parts[1]!, longitude: parts[0]!, altitude: parts.length > 2 ? parts[2] : null));
  }
  return out;
}

ParsedTrack _parseKml(XmlDocument doc) {
  final segments = <List<GpsCoordinate>>[];
  final waypoints = <Waypoint>[];
  final placemarks = _all(doc, 'Placemark').toList();

  for (var i = 0; i < placemarks.length; i++) {
    final pm = placemarks[i];
    for (final line in _all(pm, 'LineString')) {
      final coords = _kmlCoordinates(_childText(line, 'coordinates') ?? '');
      if (coords.isNotEmpty) segments.add(coords);
    }
    // Google Earth exports timed tracks as <gx:Track> with parallel <when>/<gx:coord> lists.
    for (final track in _all(pm, 'Track')) {
      final whens = _all(track, 'when').map((w) => _time(w.innerText.trim())).toList();
      final coords = <GpsCoordinate>[];
      var j = 0;
      for (final c in _all(track, 'coord')) {
        final parts = c.innerText.trim().split(RegExp(r'\s+')).map(double.tryParse).toList();
        if (parts.length >= 2 && parts[0] != null && parts[1] != null) {
          coords.add(
            GpsCoordinate(
              latitude: parts[1]!,
              longitude: parts[0]!,
              altitude: parts.length > 2 ? parts[2] : null,
              timestamp: j < whens.length ? whens[j] : null,
            ),
          );
        }
        j++;
      }
      if (coords.isNotEmpty) segments.add(coords);
    }
    for (final point in _all(pm, 'Point')) {
      final pts = _kmlCoordinates(_childText(point, 'coordinates') ?? '');
      if (pts.isNotEmpty) waypoints.add(Waypoint.at(pts.first, _childText(pm, 'name') ?? 'Waypoint ${i + 1}'));
    }
  }

  final trackPlacemark = placemarks
      .where((pm) => _all(pm, 'LineString').isNotEmpty || _all(pm, 'Track').isNotEmpty)
      .firstOrNull;
  return ParsedTrack(
    format: TrackFormat.kml,
    name: trackPlacemark == null ? null : _childText(trackPlacemark, 'name'),
    segments: segments,
    waypoints: waypoints,
  );
}

/// Parses the text of a .gpx or .kml file. Throws an [Exception] with a user-readable message.
ParsedTrack parseTrackFile(String text, String filename) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException {
    throw Exception(I18n.t('error.invalidXml'));
  }
  final root = doc.rootElement.name.local.toLowerCase();
  final ParsedTrack parsed;
  if (root == 'gpx') {
    parsed = _parseGpx(doc);
  } else if (root == 'kml') {
    parsed = _parseKml(doc);
  } else {
    throw Exception(I18n.t('error.notGpxKml', {'file': filename}));
  }
  if (parsed.segments.isEmpty) throw Exception(I18n.t('error.noTrackPoints'));
  return parsed;
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _gpxPoint2(String tag, GpsCoordinate pt, {String? name}) {
  final inner = [
    if (name != null) '<name>${_esc(name)}</name>',
    if (pt.altitude != null) '<ele>${pt.altitude}</ele>',
    if (pt.timestamp != null) '<time>${pt.timestamp!.toUtc().toIso8601String()}</time>',
  ].join();
  return '<$tag lat="${pt.latitude}" lon="${pt.longitude}">$inner</$tag>';
}

/// The trail as a GPX 1.1 document, with timestamps (this is the person's own copy).
String buildGpx(Trail trail) {
  final waypoints = trail.waypoints.map((w) => '  ${_gpxPoint2('wpt', w, name: w.name)}').join('\n');
  final points = trail.coordinates.map((c) => '      ${_gpxPoint2('trkpt', c)}').join('\n');
  final desc = trail.description.isEmpty ? '' : '<desc>${_esc(trail.description)}</desc>';
  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Pania" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${_esc(trail.name)}</name>$desc</metadata>
$waypoints
  <trk>
    <name>${_esc(trail.name)}</name>
    <trkseg>
$points
    </trkseg>
  </trk>
</gpx>
''';
}

String gpxFileName(Trail trail) {
  final safe = trail.name.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-').replaceAll(RegExp(r'^-|-$'), '');
  return '${safe.isEmpty ? 'trail' : safe}.gpx';
}

Future<File> _writeGpx(Trail trail) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, gpxFileName(trail)));
  return file.writeAsString(buildGpx(trail));
}

/// Opens the system share sheet with the .gpx file; the person can save it from there.
Future<void> shareGpx(Trail trail) async {
  final file = await _writeGpx(trail);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/gpx+xml')],
      title: trail.name,
    ),
  );
}
