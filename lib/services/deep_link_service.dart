import 'dart:async';
import 'package:flutter/foundation.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final ValueNotifier<int?> pendingRestaurantId = ValueNotifier(null);
  int? _pendingTabIndex;
  final _tabController = StreamController<int>.broadcast();

  Stream<int> get tabStream => _tabController.stream;

  /// 하단 탭을 유지한 채 해당 탭으로 이동한다.
  /// 쿠폰 발급 팝업의 '내 지갑 바로가기'처럼 새 라우트를 쌓지 않을 때 쓴다.
  void openTab(int tabIndex) {
    _pendingTabIndex = tabIndex;
    _tabController.add(tabIndex);
  }

  /// MainAppScreen.initState에서 한 번 호출 — 앱 최초 실행 시의 딥링크 탭 인덱스를 소비
  int? consumePendingTabIndex() {
    final idx = _pendingTabIndex;
    _pendingTabIndex = null;
    return idx;
  }

  void handleUri(Uri uri) {
    if (uri.scheme != 'wouldulike') return;
    debugPrint('[DeepLink] Handling URI: $uri');

    int? tabIndex;
    switch (uri.host) {
      case 'main':
        tabIndex = 0;
      case 'restaurant':
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final id = int.tryParse(segments.first);
          if (id != null) {
            pendingRestaurantId.value = id;
            tabIndex = 1;
          }
        }
      case 'coupons':
        tabIndex = 2;
    }

    if (tabIndex != null) {
      _pendingTabIndex = tabIndex;
      _tabController.add(tabIndex);
    }
  }
}
