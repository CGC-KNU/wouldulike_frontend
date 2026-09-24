import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:new1/config/analytics_events.dart';

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

  /// 이벤트를 보낸다.
  ///
  /// [event] 가 [String] 이 아니라 [AnalyticsEvent] 인 것이 핵심이다.
  /// 문자열을 받게 두면 오타가 나도 컴파일이 통과하고 데이터만 조용히
  /// 사라지며, `analytics_events.dart` 가 「이 앱이 찍는 것의 목록」 구실을
  /// 못 하게 된다. 새 이벤트는 그 파일에 한 줄 선언해야 쓸 수 있다.
  static Future<void> logEvent(
    AnalyticsEvent event, {
    Map<String, Object?>? parameters,
  }) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: event.name,
        parameters: _sanitizeParameters(parameters),
      );
    } catch (e) {
      // Analytics failures shouldn't block user flows.
      // 다만 예약어 충돌처럼 조용히 전부 버려지는 실패는 개발 중에 보여야 한다.
      if (kDebugMode) debugPrint('[Analytics] ${event.name} 전송 실패: $e');
    }
  }

  /// 앱 이벤트를 서버 기록(마일리지 원장 등)과 사용자 단위로 잇는 키.
  /// 내부 회원 id만 넣는다(카카오 id·닉네임 금지). null이면 해제한다.
  static Future<void> setUserId(int? userId) async {
    try {
      await FirebaseAnalytics.instance.setUserId(
        id: userId != null && userId > 0 ? userId.toString() : null,
      );
    } catch (_) {}
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

