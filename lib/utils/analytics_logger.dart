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
}

