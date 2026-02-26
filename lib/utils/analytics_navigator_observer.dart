import 'package:flutter/material.dart';

import '../config/analytics_events.dart';
import 'analytics_logger.dart';

/// Navigator의 pop(뒤로가기) 이벤트를 Firebase에 기록
class AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final fromScreen = route.settings.name ??
        route.settings.arguments?.toString() ??
        route.runtimeType.toString();
    AnalyticsLogger.logEvent(
      AnalyticsEvents.backButtonClick,
      parameters: {
        AnalyticsEvents.paramFromScreen: fromScreen,
      },
    );
  }
}
