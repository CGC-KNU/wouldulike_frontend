import 'dart:async';
import 'package:flutter/foundation.dart';

import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';
import 'api_client.dart';
import 'mileage_service.dart';

/// 외부 딥링크가 앱에 들어온 통로. deep_link_open · qr_visit_credit 의 source 값.
/// 같은 링크가 link_stream 과 initial_link 로 연달아 찍히면 이중 처리된 것이다.
enum DeepLinkChannel {
  linkStream('link_stream'),
  initialLink('initial_link'),
  pushTap('push_tap');

  const DeepLinkChannel(this.value);
  final String value;
}

/// 링크에 붙은 출처 표기(`src=qr` 등). 없으면 'none'.
/// 매장 QR과 공유 링크가 같은 주소라, 인쇄물에 src 를 붙여야 둘을 가를 수 있다.
String resolveDeepLinkSource(Uri uri) {
  final src = (uri.queryParameters['src'] ?? '').trim().toLowerCase();
  return src.isEmpty ? 'none' : src;
}

/// QR 방문 적립 요청에 실을 source (서버 MileageEvent.SOURCE_CHOICES: qr · share · push).
/// src 없는 옛 QR 인쇄물이 섞여 있어 share 로 추정하지 않고 null(미전송)로 둔다.
/// push 는 링크 표기가 아니라 통로로 판단하며, 푸시 탭은 요청 전에 걸러진다.
String? qrVisitServerSource(String linkSource) {
  switch (linkSource) {
    case 'qr':
    case 'share':
      return linkSource;
    default:
      return null;
  }
}

/// 앱 안에서 딥링크로 열 수 있는 화면.
/// 외부 브라우저·OS 설정·카카오 채널 등 앱 밖 목적지는 넣지 않는다.
enum DeepLinkScreen {
  home,
  restaurants,
  restaurantDetail,
  wallet,
  my,
  featured,
  mission,
  invite,
  shop,
  raffleEntries,
  raffleWinners,
  raffleTerms,
  favorites,
  profile,
  login,
}

/// 브릿지·커스텀 스킴이 가리키는 화면.
class DeepLinkTarget {
  const DeepLinkTarget({
    required this.screen,
    this.restaurantId,
    this.walletTabIndex,
    this.campaignCode,
  });

  final DeepLinkScreen screen;
  final int? restaurantId;

  /// 내 지갑 내부 탭. 0 쿠폰 / 1 스탬프 / 2 마일리지.
  final int? walletTabIndex;

  /// 기획전 코드. 없으면 현재 진행 중 첫 기획전.
  final String? campaignCode;

  int get tabIndex {
    switch (screen) {
      case DeepLinkScreen.home:
      case DeepLinkScreen.featured:
      case DeepLinkScreen.mission:
      case DeepLinkScreen.invite:
        return 0;
      case DeepLinkScreen.restaurants:
      case DeepLinkScreen.restaurantDetail:
        return 1;
      case DeepLinkScreen.wallet:
      case DeepLinkScreen.shop:
      case DeepLinkScreen.raffleEntries:
      case DeepLinkScreen.raffleWinners:
      case DeepLinkScreen.raffleTerms:
        return 2;
      case DeepLinkScreen.my:
      case DeepLinkScreen.favorites:
      case DeepLinkScreen.profile:
      case DeepLinkScreen.login:
        return 3;
    }
  }

  bool get pushesRoute {
    switch (screen) {
      case DeepLinkScreen.featured:
      case DeepLinkScreen.mission:
      case DeepLinkScreen.invite:
      case DeepLinkScreen.shop:
      case DeepLinkScreen.raffleEntries:
      case DeepLinkScreen.raffleWinners:
      case DeepLinkScreen.raffleTerms:
      case DeepLinkScreen.favorites:
      case DeepLinkScreen.profile:
      case DeepLinkScreen.login:
        return true;
      case DeepLinkScreen.home:
      case DeepLinkScreen.restaurants:
      case DeepLinkScreen.restaurantDetail:
      case DeepLinkScreen.wallet:
      case DeepLinkScreen.my:
        return false;
    }
  }
}

/// QR 방문으로 새로 발급된 쿠폰. 어느 식당(restaurantId) 쿠폰인지 알아야
/// 화면단에서 그 식당의 보유 쿠폰 목록/카운트도 함께 새로고침할 수 있다.
class QrVisitCouponIssued {
  const QrVisitCouponIssued({required this.restaurantId, required this.codes});

  final int restaurantId;
  final List<String> codes;
}

const _bridgeHost = 'cgc-knu.github.io';
const _bridgePathPrefix = '/wouldulike_deeplink';

/// 배너 HTTPS / wouldulike:// 를 앱 화면으로 바꾼다.
/// 웹뷰가 `wouldulike:///restaurant` 처럼 host를 비우는 경우도 처리한다.
DeepLinkTarget? resolveWouldUlikeDeepLink(Uri uri) {
  if (uri.scheme == 'https' || uri.scheme == 'http') {
    if (uri.host.toLowerCase() != _bridgeHost) return null;
    final path = uri.path.toLowerCase();
    if (path != _bridgePathPrefix && !path.startsWith('$_bridgePathPrefix/')) {
      return null;
    }
    return resolveWouldUlikeDeepLink(
      _customSchemeFromBridgeQuery(uri.queryParameters),
    );
  }
  if (uri.scheme != 'wouldulike') return null;

  final host = uri.host.toLowerCase();
  final segments =
      uri.pathSegments.where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
  final dest = host.isNotEmpty ? host : (segments.isNotEmpty ? segments.first : '');
  final rest = host.isNotEmpty
      ? uri.pathSegments.where((s) => s.isNotEmpty).toList()
      : (uri.pathSegments.length > 1
          ? uri.pathSegments.sublist(1).where((s) => s.isNotEmpty).toList()
          : const <String>[]);

  return _resolveDestination(dest, rest);
}

DeepLinkTarget? _resolveDestination(String dest, List<String> rest) {
  switch (dest) {
    case 'main':
    case 'home':
      return const DeepLinkTarget(screen: DeepLinkScreen.home);
    case 'restaurant':
    case 'restaurants':
    case 'affiliate':
      int? id;
      if (rest.isNotEmpty) id = int.tryParse(rest.first);
      if (id != null) {
        return DeepLinkTarget(
          screen: DeepLinkScreen.restaurantDetail,
          restaurantId: id,
        );
      }
      return const DeepLinkTarget(screen: DeepLinkScreen.restaurants);
    case 'wallet':
      return _walletTarget(rest.isEmpty ? '' : rest.first);
    case 'coupons':
    case 'coupon':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.wallet,
        walletTabIndex: 0,
      );
    case 'stamps':
    case 'stamp':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.wallet,
        walletTabIndex: 1,
      );
    case 'mileage':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.wallet,
        walletTabIndex: 2,
      );
    case 'shop':
    case 'mileage-shop':
    case 'mileageshop':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.shop,
        walletTabIndex: 2,
      );
    case 'raffle':
    case 'raffles':
      return _raffleTarget(rest.isEmpty ? '' : rest.first);
    case 'entries':
      return const DeepLinkTarget(screen: DeepLinkScreen.raffleEntries);
    case 'winners':
      return const DeepLinkTarget(screen: DeepLinkScreen.raffleWinners);
    case 'terms':
      return const DeepLinkTarget(screen: DeepLinkScreen.raffleTerms);
    case 'my':
    case 'me':
    case 'mypage':
      return const DeepLinkTarget(screen: DeepLinkScreen.my);
    case 'featured':
    case 'campaign':
    case 'promotion':
      final code = rest.isNotEmpty ? rest.first.trim() : '';
      return DeepLinkTarget(
        screen: DeepLinkScreen.featured,
        campaignCode: code.isEmpty ? null : code,
      );
    case 'mission':
    case 'missions':
    case 'welcome':
      return const DeepLinkTarget(screen: DeepLinkScreen.mission);
    case 'invite':
    case 'invitation':
    case 'referral':
      return const DeepLinkTarget(screen: DeepLinkScreen.invite);
    case 'favorites':
    case 'favorite':
    case 'wishlist':
      return const DeepLinkTarget(screen: DeepLinkScreen.favorites);
    case 'profile':
    case 'profilesetup':
      return const DeepLinkTarget(screen: DeepLinkScreen.profile);
    case 'login':
      return const DeepLinkTarget(screen: DeepLinkScreen.login);
    case 'tab':
      if (rest.isEmpty) return null;
      final tab = int.tryParse(rest.first);
      if (tab == null || tab < 0 || tab > 3) return null;
      return DeepLinkTarget(screen: _screenForTab(tab));
    default:
      return null;
  }
}

DeepLinkScreen _screenForTab(int tab) {
  switch (tab) {
    case 1:
      return DeepLinkScreen.restaurants;
    case 2:
      return DeepLinkScreen.wallet;
    case 3:
      return DeepLinkScreen.my;
    default:
      return DeepLinkScreen.home;
  }
}

DeepLinkTarget? _walletTarget(String sub) {
  final key = sub.toLowerCase();
  if (key.isEmpty) {
    return const DeepLinkTarget(
      screen: DeepLinkScreen.wallet,
      walletTabIndex: 0,
    );
  }
  final index = int.tryParse(key);
  if (index != null) {
    if (index < 0 || index > 2) return null;
    return DeepLinkTarget(
      screen: DeepLinkScreen.wallet,
      walletTabIndex: index,
    );
  }
  switch (key) {
    case 'stamp':
    case 'stamps':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.wallet,
        walletTabIndex: 1,
      );
    case 'mileage':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.wallet,
        walletTabIndex: 2,
      );
    case 'shop':
    case 'store':
    case 'mileage-shop':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.shop,
        walletTabIndex: 2,
      );
    case 'coupon':
    case 'coupons':
      return const DeepLinkTarget(
        screen: DeepLinkScreen.wallet,
        walletTabIndex: 0,
      );
    default:
      return null;
  }
}

DeepLinkTarget _raffleTarget(String sub) {
  switch (sub.toLowerCase()) {
    case 'winners':
    case 'winner':
      return const DeepLinkTarget(screen: DeepLinkScreen.raffleWinners);
    case 'terms':
    case 'term':
      return const DeepLinkTarget(screen: DeepLinkScreen.raffleTerms);
    default:
      return const DeepLinkTarget(screen: DeepLinkScreen.raffleEntries);
  }
}

Uri _customSchemeFromBridgeQuery(Map<String, String> params) {
  final type = (params['type'] ?? '').toLowerCase();
  final id = (params['id'] ?? '').trim();
  switch (type) {
    case 'restaurant':
    case 'restaurants':
      return id.isEmpty
          ? Uri.parse('wouldulike://restaurant')
          : Uri.parse('wouldulike://restaurant/$id');
    case 'affiliate':
      return Uri.parse('wouldulike://restaurant');
    case 'tab':
      return id.isEmpty
          ? Uri.parse('wouldulike://')
          : Uri.parse('wouldulike://tab/$id');
    case 'wallet':
      return id.isEmpty
          ? Uri.parse('wouldulike://wallet')
          : Uri.parse('wouldulike://wallet/$id');
    case 'coupons':
    case 'coupon':
      return Uri.parse('wouldulike://coupons');
    case 'stamps':
    case 'stamp':
      return Uri.parse('wouldulike://stamps');
    case 'mileage':
      return Uri.parse('wouldulike://mileage');
    case 'shop':
    case 'mileage-shop':
    case 'mileageshop':
      return Uri.parse('wouldulike://shop');
    case 'raffle':
    case 'raffles':
    case 'entries':
      return id.isEmpty
          ? Uri.parse('wouldulike://raffle')
          : Uri.parse('wouldulike://raffle/$id');
    case 'winners':
      return Uri.parse('wouldulike://raffle/winners');
    case 'terms':
      return Uri.parse('wouldulike://raffle/terms');
    case 'my':
    case 'me':
    case 'mypage':
      return Uri.parse('wouldulike://my');
    case 'featured':
    case 'campaign':
    case 'promotion':
      return id.isEmpty
          ? Uri.parse('wouldulike://featured')
          : Uri.parse('wouldulike://featured/$id');
    case 'mission':
    case 'missions':
    case 'welcome':
      return Uri.parse('wouldulike://mission');
    case 'invite':
    case 'invitation':
    case 'referral':
      return Uri.parse('wouldulike://invite');
    case 'favorites':
    case 'favorite':
    case 'wishlist':
      return Uri.parse('wouldulike://favorites');
    case 'profile':
    case 'profilesetup':
      return Uri.parse('wouldulike://profile');
    case 'login':
      return Uri.parse('wouldulike://login');
    case 'main':
    case 'home':
      return Uri.parse('wouldulike://main');
    default:
      return Uri.parse('wouldulike://');
  }
}

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final ValueNotifier<int?> pendingRestaurantId = ValueNotifier(null);
  final ValueNotifier<int?> pendingWalletTab = ValueNotifier(null);

  /// QR 방문으로 방금 새로 발급된 쿠폰. 화면단에서 소비 후 null로 되돌린다.
  final ValueNotifier<QrVisitCouponIssued?> pendingQrVisitCoupon =
      ValueNotifier(null);
  int? _pendingTabIndex;
  DeepLinkTarget? _pendingTarget;
  final _tabController = StreamController<int>.broadcast();
  final _targetController = StreamController<DeepLinkTarget>.broadcast();

  Stream<int> get tabStream => _tabController.stream;
  Stream<DeepLinkTarget> get targetStream => _targetController.stream;

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

  /// 앱 최초 실행 시 푸시할 화면까지 포함한 목적지.
  DeepLinkTarget? consumePendingTarget() {
    final target = _pendingTarget;
    _pendingTarget = null;
    _pendingTabIndex = null;
    return target;
  }

  /// 브릿지 HTTPS면 브라우저를 열지 않고 앱 화면만 연다.
  /// 앱 내부 배너/목록 클릭 등 in-app 네비게이션에서 호출한다 —
  /// 실제 외부 QR 스캔이 아니므로 방문 마일리지는 적립하지 않는다.
  bool tryHandle(Uri uri) {
    final target = resolveWouldUlikeDeepLink(uri);
    if (target == null) return false;
    _apply(target);
    return true;
  }

  /// OS가 앱 밖에서 전달한 딥링크(QR 스캔, 카카오톡 링크 클릭 등) 전용 진입점.
  /// main.dart의 uriLinkStream / getInitialAppLink / 푸시 탭에서만 호출해야 한다.
  void handleUri(
    Uri uri, {
    DeepLinkChannel channel = DeepLinkChannel.linkStream,
  }) {
    debugPrint('[DeepLink] Handling URI: $uri');
    final target = resolveWouldUlikeDeepLink(uri);
    // 해석 못 한 링크(카카오 로그인 리다이렉트 등)는 화면 이동이 아니므로 남기지 않는다.
    if (target == null) return;
    final linkSource = resolveDeepLinkSource(uri);
    AnalyticsLogger.logEvent(
      AnalyticsEvents.deepLinkOpen,
      parameters: {
        AnalyticsEvents.paramSource: channel.value,
        AnalyticsEvents.paramLinkSource: linkSource,
        AnalyticsEvents.paramTargetScreen: target.screen.name,
        AnalyticsEvents.paramRestaurantId: target.restaurantId,
      },
    );
    _apply(target);
    _creditQrVisitIfRestaurant(target, channel: channel, linkSource: linkSource);
  }

  /// 외부 딥링크로 식당 상세 화면에 진입한 경우에만 방문 마일리지 적립과
  /// 그 식당 일반쿠폰(최초 1회) 발급을 시도한다. 푸시 탭은 제외한다.
  Future<void> _creditQrVisitIfRestaurant(
    DeepLinkTarget target, {
    required DeepLinkChannel channel,
    required String linkSource,
  }) async {
    if (target.screen != DeepLinkScreen.restaurantDetail) return;
    final restaurantId = target.restaurantId;
    if (restaurantId == null) return;
    // 푸시 탭은 매장 방문이 아니다. 서버도 source=push 를 거부하지만, 요청 자체를
    // 보내지 않아 source 를 모르는 서버에서도 적립·첫 쿠폰이 나가지 않게 한다.
    // 푸시로 식당을 연 규모는 deep_link_open(source=push_tap)으로 본다.
    if (channel == DeepLinkChannel.pushTap) return;
    // 콜드 스타트에서는 세션 복구보다 먼저 호출된다. 토큰 유무를 같이 남겨
    // 비로그인 스캔이 조용히 사라지는 규모를 본다.
    final hasToken = await ApiClient.hasAccessToken();
    final result = await MileageService.creditQrVisit(
      restaurantId,
      source: qrVisitServerSource(linkSource),
    );
    AnalyticsLogger.logEvent(
      AnalyticsEvents.qrVisitCredit,
      parameters: {
        AnalyticsEvents.paramRestaurantId: restaurantId,
        AnalyticsEvents.paramSource: channel.value,
        AnalyticsEvents.paramLinkSource: linkSource,
        AnalyticsEvents.paramResult:
            result.credited ? 'credited' : (result.code ?? 'not_credited'),
        AnalyticsEvents.paramPoints: result.delta,
        AnalyticsEvents.paramBalanceAfter: result.balance,
        AnalyticsEvents.paramCouponCount: result.issuedCoupons.length,
        AnalyticsEvents.paramAuthState: hasToken ? 'has_token' : 'no_token',
      },
    );
    if (result.couponIssued && result.issuedCoupons.isNotEmpty) {
      pendingQrVisitCoupon.value = QrVisitCouponIssued(
        restaurantId: restaurantId,
        codes: result.issuedCoupons.map((c) => c.code).toList(),
      );
    }
  }

  void _apply(DeepLinkTarget target) {
    pendingRestaurantId.value = target.restaurantId;
    if (target.walletTabIndex != null) {
      pendingWalletTab.value = target.walletTabIndex;
    }
    _pendingTabIndex = target.tabIndex;
    _pendingTarget = target;
    _tabController.add(target.tabIndex);
    _targetController.add(target);
  }
}
