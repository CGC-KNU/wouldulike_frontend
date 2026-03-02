// lib/utils/location_helper.dart
// 위치 기반 서비스 비활성화: SharedPreferences에 저장된 값만 사용 (기본값 대체)

import 'package:shared_preferences/shared_preferences.dart';

class LocationHelper {
  static const double _defaultLat = 35.8714;
  static const double _defaultLon = 128.6014;

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

  // 위도+경도 Map으로 가져오기 (저장된 값 없으면 null)
  static Future<Map<String, double>?> getLatLon() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('user_lat');
    final lon = prefs.getDouble('user_lon');
    if (lat != null && lon != null) {
      return {'lat': lat, 'lon': lon};
    }
    return null;
  }

  // 기본 좌표 반환 (대구 대학가 등 - 위치 권한 없을 때 사용)
  static Map<String, double> getDefaultLatLon() =>
      {'lat': _defaultLat, 'lon': _defaultLon};
}
