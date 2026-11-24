import 'package:flutter_test/flutter_test.dart';
import 'package:pania/core/gps/terrain.dart';
import 'package:pania/core/routing/brouter.dart';
import 'package:pania/core/weather/history.dart';

void main() {
  group('terrain sampling', () {
    test('samples evenly and keeps both ends', () {
      expect(sampleIndices(0, 5), isEmpty);
      expect(sampleIndices(3, 5), [0, 1, 2]);
      final s = sampleIndices(1000, 5);
      expect(s.first, 0);
      expect(s.last, 999);
      expect(s, hasLength(5));
    });

    test('interpolates between samples with straight lines', () {
      expect(interpolateByIndex([0, 10], [100, 200], 11), [for (var i = 0; i <= 10; i++) 100.0 + i * 10]);
      expect(interpolateByIndex([0], [50], 3), [50, 50, 50]);
    });
  });

  group('walk weather', () {
    final hourly = <String, List<Object?>>{
      'time': ['2026-05-01T07:00', '2026-05-01T08:00', '2026-05-01T09:00', '2026-05-01T10:00'],
      'temperature_2m': [10, 12, 14, null],
      'precipitation': [0, 0.5, 1.5, 9],
    };
    int utc(int h, [int min = 0]) => DateTime.utc(2026, 5, 1, h, min).millisecondsSinceEpoch;

    test('averages temperature and sums rain over the hours the walk touched', () {
      final w = summarizeWalkWeather(hourly, utc(8, 20), utc(9, 40))!;
      expect(w.tempC, 13);
      expect(w.precipMm, 2);
    });

    test('has nothing when no hour has data', () {
      expect(summarizeWalkWeather(hourly, utc(10), utc(10, 30)), isNull);
      expect(summarizeWalkWeather(hourly, utc(20), utc(21)), isNull);
    });
  });

  group('BRouter', () {
    test('reads the way segments from its messages table', () {
      final segments = parseSegments([
        [
          'Longitude',
          'Latitude',
          'Elevation',
          'Distance',
          'CostPerKm',
          'ElevCost',
          'TurnCost',
          'NodeCost',
          'InitialCost',
          'WayTags',
        ],
        ['10', '43', '100', '120', '0', '0', '0', '0', '0', 'highway=path sac_scale=hiking route_hiking_iwn=yes'],
        ['10', '43', '110', '80', '0', '0', '0', '0', '0', ''],
      ]);
      expect(segments, hasLength(2));
      expect(segments.first.distanceM, 120);
      expect(segments.first.tags['sac_scale'], 'hiking');
      expect(segments.first.tags['route_hiking_iwn'], 'yes');
      expect(segments.last.tags, isEmpty);
      expect(parseSegments(const []), isEmpty);
    });
  });
}
