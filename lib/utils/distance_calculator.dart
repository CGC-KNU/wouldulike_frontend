import 'dart:math';

class DistanceCalculator {
  static double haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // 지구 반지름 (단위: km)
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _degToRad(double deg) {
    return deg * pi / 180;
  }
}
