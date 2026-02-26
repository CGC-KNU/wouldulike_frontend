import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsLogger {
  AnalyticsLogger._();

  static Future<void> logEvent(
    String name, {
    Map<String, Object?>? parameters,
  }) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
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

