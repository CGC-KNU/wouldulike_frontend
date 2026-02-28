import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsLogger {
  AnalyticsLogger._();

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

