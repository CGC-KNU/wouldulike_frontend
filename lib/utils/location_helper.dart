// lib/utils/location_helper.dart

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationHelper {
  // 위도 가져오기
  static Future<double?> getLatitude() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('user_lat');
  }

  // 경도 가져오기
  static Future<double?> getLongitude() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('user_lon');
  }

  // 위도+경도 Map으로 가져오기
  static Future<Map<String, double>?> getLatLon() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('user_lat');
    final lon = prefs.getDouble('user_lon');
    if (lat != null && lon != null) {
      return {'lat': lat, 'lon': lon};
    }
    return null;
  }

  // 현재 위치를 받아 SharedPreferences에 저장 (비동기로 호출)
  static Future<void> refreshCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled; skipping refresh.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_lat', position.latitude);
      await prefs.setDouble('user_lon', position.longitude);
    } catch (e) {
      debugPrint('Failed to refresh current location: $e');
    }
  }
}
