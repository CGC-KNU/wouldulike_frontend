// lib/utils/location_helper.dart

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
}
