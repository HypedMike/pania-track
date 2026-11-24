import 'package:geolocator/geolocator.dart';

import '../../features/trail/domain/gps_coordinate.dart';
import '../i18n/i18n.dart';

/// Reads the device's position.
abstract final class GpsService {
  /// Asks for location permission if needed. Throws if it is denied.
  static Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(I18n.t('error.geoUnavailable'));
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception(I18n.t('error.permissionDenied'));
    }
  }

  /// Reads the current GPS position.
  static Future<GpsCoordinate> currentPosition() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 20)),
    );
    return fromPosition(p);
  }

  static GpsCoordinate fromPosition(Position p) => GpsCoordinate(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    altitude: p.altitude == 0 && p.altitudeAccuracy == 0 ? null : p.altitude,
    timestamp: p.timestamp,
  );
}
