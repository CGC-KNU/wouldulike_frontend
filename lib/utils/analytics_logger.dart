import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsLogger {
  AnalyticsLogger._();

  static int? _lastRestaurantDetailId;
  static String? _lastRestaurantDetailSource;
  static DateTime? _lastRestaurantDetailClosedAt;

  /// 이전에 닫힌 매장 상세 정보를 (id, source)로 반환.
  /// 너무 오래된 값은 무시하여 잘못된 전환 연결을 줄인다.
  static ({int? restaurantId, String? source}) getRecentLastRestaurantDetail({
    Duration maxAge = const Duration(minutes: 10),
  }) {
    final closedAt = _lastRestaurantDetailClosedAt;
    if (closedAt == null) {
      return (restaurantId: null, source: null);
    }
    final age = DateTime.now().difference(closedAt);
    if (age.isNegative || age > maxAge) {
      return (restaurantId: null, source: null);
    }
    return (
      restaurantId: _lastRestaurantDetailId,
      source: _lastRestaurantDetailSource,
    );
  }

  /// 매장 상세 닫힘을 기록해, 다음 상세 오픈 시 prev_*로 연결할 수 있게 한다.
  static void markRestaurantDetailClosed({
    required int restaurantId,
    required String source,
  }) {
    _lastRestaurantDetailId = restaurantId;
    _lastRestaurantDetailSource = source;
    _lastRestaurantDetailClosedAt = DateTime.now();
  }

  /// Firebase Analytics는 String, int, double만 허용. bool 등은 변환 필요.
  static Map<String, Object>? _sanitizeParameters(Map<String, Object?>? params) {
    if (params == null || params.isEmpty) return null;
    final sanitized = <String, Object>{};
    for (final e in params.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is String || v is int || v is double) {
        sanitized[e.key] = v;
      } else if (v is bool) {
        sanitized[e.key] = v ? 'true' : 'false';
      } else {
        sanitized[e.key] = v.toString();
      }
    }
    return sanitized.isEmpty ? null : sanitized;
  }

  static Future<void> logEvent(
    String name, {
    Map<String, Object?>? parameters,
  }) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: _sanitizeParameters(parameters),
      );
    } catch (_) {
      // Analytics failures shouldn't block user flows.
    }
  }

  /// 프로필에서 단대/학과 정보를 Firebase User Property로 설정
  static Future<void> setUserPropertiesFromProfile(
    Map<String, dynamic>? profile,
  ) async {
    if (profile == null) return;
    try {
      final analytics = FirebaseAnalytics.instance;
      final college = profile['college_code']?.toString();
      final dept = profile['department_code']?.toString();
      await analytics.setUserProperty(name: 'college_code', value: college);
      await analytics.setUserProperty(name: 'department_code', value: dept);
    } catch (_) {}
  }
}

