import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';
import 'affiliate_benefits_screen.dart';
import 'coupon_list_screen.dart';
import 'featured/featured_campaign_screen.dart';
import 'mission/mission_track_screen.dart';
import 'mission/routine_missions.dart';
import 'services/affiliate_service.dart';
import 'services/coupon_service.dart';
import 'services/api_client.dart';
import 'services/mission_service.dart';
import 'services/popup_service.dart';
import 'services/promotion_service.dart';
import 'services/trend_service.dart';

bool _isValidHttpImageUrl(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  final hasHttpScheme = uri.scheme == 'http' || uri.scheme == 'https';
  return hasHttpScheme && uri.host.isNotEmpty;
}

// URL 열기 도구
class UrlLauncherUtil {
  static Future<void> launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);

    try {
      if (await canLaunchUrl(url)) {
        final bool launched = await launchUrl(
          url,
          mode: LaunchMode.platformDefault,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );

        if (!launched) {
          throw 'URL 실행 실패: $urlString';
        }
      } else {
        throw 'URL 실행 불가: $urlString';
      }
    } catch (e) {
      print('URL 실행 중 에러: $e');
      rethrow;
    }
  }
}

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});
  @override
  _HomeContentState createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  static const String _kWelcomeCouponDismissedKey =
      'welcome_coupon_dialog_dismissed';
  static const String _kPopupDismissedPrefix = 'home_popup_dismissed';
  static const String _kFavoriteRestaurantIdsKey =
      'affiliate_favorite_restaurant_ids';
  static const List<String> _kWelcomeCouponKeywords = <String>[
    '신규가입',
    '회원가입',
    '가입축하',
    '환영',
    'welcome',
    'new member',
    '가입 축하',
  ];
  static const String _defaultPromotionTitle = '우주라이크 사용 가이드';
  static const String _defaultPromotionDescription = '앱 사용 가이드를 바로 만나보세요.';
  static const String _defaultPromotionImage = 'https://placehold.co/345x220.png';
  late SharedPreferences prefs;
  List<TrendItem> _trends = [];
  final PageController _bannerController = PageController();
  List<AffiliateRestaurantSummary> _affiliateRestaurants = [];
  bool _isAffiliateLoading = false;
  String? _affiliateError;
  List<UserCoupon> _affiliateCoupons = [];
  List<UserCoupon> _homeCouponShowcase = const [];
  Map<int, StampStatus> _affiliateStampStatuses = {};
  bool _affiliateRequiresLogin = false;
  String _affiliateSource = 'all';
  Future<void>? _affiliateUserDataFuture;
  bool get _hasAffiliateContent =>
      _isAffiliateLoading ||
      _affiliateError != null ||
      _affiliateRestaurants.isNotEmpty;
  int _currentBannerIndex = 0;
  bool _isTrendLoading = false;
  bool _isCheckingWelcomeCoupon = false;
  bool _welcomeDialogVisible = false;
  bool _welcomePromptScheduled = false;
  bool _popupDialogVisible = false;
  bool _popupPromptScheduled = false;
  bool _suppressWelcomeCoupon = false;
  bool _isOpeningAffiliateDetail = false;
  String? _processingHomeCouponCode;
  Set<int> _favoriteRestaurantIds = <int>{};
  Timer? _bannerAutoScrollTimer;
  static const Duration _bannerAutoScrollDuration = Duration(seconds: 3);
  FeaturedCampaign? _featuredCampaign;
  MissionTrack? _missionTrack;
  int _featuredBannerIndex = 0;
  final PageController _featuredBannerController =
      PageController(viewportFraction: 0.92);

  @override
  void initState() {
    super.initState();
    _initializePrefs();
    _loadTrends();
    _loadAffiliateRestaurants();
    _loadFeaturedCampaign();
    _loadMissionTrack();
    _startBannerAutoScroll();
  }

  /// 홈 미션 배너용. 미션 트랙 화면과 같은 응답을 쓰고 별도 호출을 만들지 않는다 (스펙 7.3).
  Future<void> _loadMissionTrack() async {
    final track = await MissionService.fetchTrack();
    if (!mounted) return;
    // 초보자 미션이 끝나면 일간/주간 미션으로 이어진다. 둘 다 없을 때만 숨긴다.
    setState(() => _missionTrack =
        (track != null && (track.hasOngoing || track.hasRoutine))
            ? track
            : null);
  }

  Future<void> _loadFeaturedCampaign() async {
    try {
      final campaign = await PromotionService.fetchCurrentFeatured();
      if (!mounted) return;
      setState(() {
        _featuredCampaign =
            (campaign != null && campaign.hasItems) ? campaign : null;
        _featuredBannerIndex = 0;
      });
    } catch (e) {
      // 진행 중 기획전 확인 실패 시 섹션만 숨긴다 (스펙 7.4).
      debugPrint('Failed to load featured campaign: $e');
      if (!mounted) return;
      setState(() => _featuredCampaign = null);
    }
  }

  Future<void> _initializePrefs() async {
    prefs = await SharedPreferences.getInstance();
    _suppressWelcomeCoupon =
        prefs.getBool(_kWelcomeCouponDismissedKey) ?? false;
    final rawFavoriteIds =
        prefs.getStringList(_kFavoriteRestaurantIdsKey) ?? const <String>[];
    _favoriteRestaurantIds = rawFavoriteIds
        .map((value) => int.tryParse(value))
        .whereType<int>()
        .toSet();
    _scheduleHomePopupCheck();
    if (!_suppressWelcomeCoupon) {
      await _checkWelcomeCouponStatus();
    }
  }

  bool _isFavoriteRestaurant(int restaurantId) {
    return _favoriteRestaurantIds.contains(restaurantId);
  }

  Future<void> _setFavoriteRestaurant(int restaurantId, bool isFavorite) async {
    final next = Set<int>.from(_favoriteRestaurantIds);
    if (isFavorite) {
      next.add(restaurantId);
    } else {
      next.remove(restaurantId);
    }
    _favoriteRestaurantIds = next;
    await prefs.setStringList(
      _kFavoriteRestaurantIdsKey,
      _favoriteRestaurantIds.map((id) => id.toString()).toList(),
    );
    String restaurantName = '';
    for (final r in _affiliateRestaurants) {
      if (r.id == restaurantId) {
        restaurantName = r.name;
        break;
      }
    }
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantFavoriteToggle,
      parameters: {
        AnalyticsEvents.paramRestaurantId: restaurantId,
        AnalyticsEvents.paramRestaurantName: restaurantName,
        AnalyticsEvents.paramAction: isFavorite ? 'add' : 'remove',
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  void _scheduleHomePopupCheck() {
    if (_popupPromptScheduled) return;
    _popupPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _popupPromptScheduled = false;
      await _checkAndShowHomePopup();
    });
  }

  Future<void> _checkAndShowHomePopup() async {
    if (!mounted || _popupDialogVisible) return;
    try {
      final popups = await PopupService.fetchVisiblePopups();
      if (!mounted || popups.isEmpty) return;
      final candidates = popups
          .where((item) => !_isPopupDismissedToday(item.id))
          .toList(growable: false);
      if (!mounted || candidates.isEmpty) return;
      final preloadedImages = await _preloadPopupImages(candidates);
      if (!mounted) return;
      await _showHomePopupDialog(candidates, preloadedImages);
    } catch (_) {
      // Ignore popup failures; main content should remain unaffected.
    }
  }

  Future<Map<int, Uint8List?>> _preloadPopupImages(
    List<HomePopupItem> popups,
  ) async {
    final Map<int, Uint8List?> results = <int, Uint8List?>{};
    await Future.wait(
      popups.map((popup) async {
        results[popup.id] = await _fetchPopupImageBytes(popup.imageUrl);
      }),
    );
    return results;
  }

  Future<Uint8List?> _fetchPopupImageBytes(String imageUrl) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isPopupDismissedToday(int popupId) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final key = '$_kPopupDismissedPrefix:$popupId:$today';
    return prefs.getBool(key) ?? false;
  }

  Future<void> _markPopupDismissedToday(int popupId) async {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final key = '$_kPopupDismissedPrefix:$popupId:$today';
    await prefs.setBool(key, true);
  }

  Future<void> _showHomePopupDialog(
    List<HomePopupItem> popups,
    Map<int, Uint8List?> preloadedImages,
  ) async {
    if (!mounted || _popupDialogVisible) return;
    _popupDialogVisible = true;
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'popup',
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.62),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: Colors.transparent,
              child: _HomePopupCarouselDialog(
                popups: popups,
                preloadedImages: preloadedImages,
                onTapPopup: (popup) async {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  await _launchURL(popup.instagramUrl);
                },
                onDismissToday: (popup) async {
                  await _markPopupDismissedToday(popup.id);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                onClose: () {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    );
    _popupDialogVisible = false;
  }

  Future<void> _loadTrends() async {
    if (_isTrendLoading) return;
    if (!mounted) return;
    setState(() {
      _isTrendLoading = true;
    });
    try {
      final items = await TrendService.fetchTrends();
      if (!mounted) return;
      setState(() {
        _trends = items;
        _currentBannerIndex = 0;
      });
      if (_bannerController.hasClients && items.isNotEmpty) {
        _bannerController.jumpToPage(0);
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to load promotion banners: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('프로모션 배너를 불러오지 못했어요.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTrendLoading = false;
        });
      }
    }
  }

  Future<void> _loadAffiliateRestaurants() async {
    if (_isAffiliateLoading) return;
    if (!mounted) return;
    setState(() {
      _isAffiliateLoading = true;
      _affiliateError = null;
    });
    try {
      List<AffiliateRestaurantSummary> restaurants;
      String source = 'all';
      bool requiresLogin = false;
      try {
        final response = await AffiliateService.fetchActiveRestaurants();
        restaurants = response.restaurants;
        source = response.source;
      } on ApiAuthException {
        // 로그인 전에는 active API를 사용할 수 없어 전체 목록으로 폴백한다.
        restaurants = await AffiliateService.fetchRestaurants();
        source = 'all';
        requiresLogin = true;
      }
      if (!mounted) return;
      setState(() {
        final shuffled = List<AffiliateRestaurantSummary>.from(restaurants);
        shuffled.shuffle(math.Random());
        _affiliateRestaurants = shuffled;
        _affiliateSource = source;
        _affiliateRequiresLogin = requiresLogin;
        if (requiresLogin) {
          _affiliateCoupons = const <UserCoupon>[];
          _affiliateStampStatuses = const <int, StampStatus>{};
        }
      });
      if (!requiresLogin) {
        await _loadAffiliateProgressData();
      }
    } on ApiNetworkException catch (e) {
      debugPrint('Failed to load affiliate restaurants: $e');
      if (!mounted) return;
      setState(() {
        _affiliateError = '제휴 식당을 불러오지 못했어요. 네트워크 상태를 확인해주세요.';
      });
    } on ApiHttpException catch (e) {
      debugPrint('HTTP error while loading affiliate restaurants: $e');
      if (!mounted) return;
      setState(() {
        _affiliateError = '제휴 식당을 불러오지 못했어요. (HTTP ${e.statusCode})';
      });
    } catch (e, stackTrace) {
      debugPrint('Unexpected error while loading affiliate restaurants: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _affiliateError = '제휴 식당을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isAffiliateLoading = false;
      });
    }
  }

  Future<void> _loadAffiliateProgressData() async {
    try {
      final results = await Future.wait<dynamic>([
        CouponService.fetchMyCoupons(status: CouponStatus.issued),
        CouponService.fetchAllStampStatuses(),
      ]);
      if (!mounted) return;
      final coupons = results[0] as List<UserCoupon>;
      final stampCollection = results[1] as StampStatusCollection;
      final showcaseCoupons = _shuffleCouponsForHome(coupons);
      setState(() {
        _affiliateCoupons = coupons;
        _homeCouponShowcase = showcaseCoupons;
        _affiliateStampStatuses = stampCollection.statuses;
        _affiliateRequiresLogin = false;
      });
    } on ApiAuthException {
      if (!mounted) return;
      setState(() {
        _affiliateRequiresLogin = true;
        _affiliateCoupons = const <UserCoupon>[];
        _homeCouponShowcase = const <UserCoupon>[];
        _affiliateStampStatuses = const <int, StampStatus>{};
      });
    } on ApiNetworkException catch (e) {
      // 홈 화면에서는 제휴 진행 데이터(쿠폰/스탬프) 로딩 실패가 치명적이지 않으므로
      // 스택 트레이스는 출력하지 않고 조용히 무시한다.
      debugPrint('Failed to load affiliate progress data (network): $e');
    } on ApiHttpException catch (e) {
      debugPrint(
          'Failed to load affiliate progress data (http ${e.statusCode})');
    } on TimeoutException catch (e) {
      debugPrint('Failed to load affiliate progress data (timeout): $e');
    } catch (e) {
      debugPrint('Failed to load affiliate progress data: $e');
      // 디버그 환경에서도 과도한 스택 트레이스 출력은 사용자 혼란을 유발할 수 있어
      // 여기서는 출력하지 않는다.
    }
  }

  List<UserCoupon> _shuffleCouponsForHome(List<UserCoupon> coupons) {
    final issued = coupons
        .where((coupon) => coupon.status == CouponStatus.issued)
        .toList();
    // 만료일이 가까운 쿠폰을 앞에 배치하여 사용을 유도
    issued.sort((a, b) {
      final aExpiry = a.expiresAt;
      final bExpiry = b.expiresAt;
      if (aExpiry == null && bExpiry == null) return 0;
      if (aExpiry == null) return 1; // 만료일 없는 쿠폰은 뒤로
      if (bExpiry == null) return -1;
      return aExpiry.compareTo(bExpiry); // 만료일 가까운 순
    });
    return issued;
  }

  Future<void> _ensureAffiliateUserData() async {
    if (_affiliateRequiresLogin) return;
    if (_affiliateCoupons.isNotEmpty) return;
    final existing = _affiliateUserDataFuture;
    if (existing != null) {
      try {
        await existing;
      } catch (_) {}
      return;
    }
    final future = _loadAffiliateCoupons();
    _affiliateUserDataFuture = future;
    try {
      await future;
    } finally {
      if (identical(_affiliateUserDataFuture, future)) {
        _affiliateUserDataFuture = null;
      }
    }
  }

  Future<void> _loadAffiliateCoupons() async {
    try {
      final coupons =
          await CouponService.fetchMyCoupons(status: CouponStatus.issued);
      if (!mounted) return;
      setState(() {
        _affiliateCoupons = coupons;
        _homeCouponShowcase = _shuffleCouponsForHome(coupons);
        _affiliateRequiresLogin = false;
      });
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _affiliateRequiresLogin = true;
        _affiliateCoupons = const <UserCoupon>[];
        _homeCouponShowcase = const <UserCoupon>[];
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('네트워크 연결을 확인해주세요. (${e.cause})')),
      );
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('쿠폰 정보를 불러오지 못했어요. (HTTP ${e.statusCode})')),
      );
    } catch (e) {
      debugPrint('Failed to load affiliate coupons: $e');
    }
  }

  List<UserCoupon> _couponsForAffiliate(int restaurantId) {
    if (_affiliateCoupons.isEmpty) return const <UserCoupon>[];
    return _affiliateCoupons
        .where((coupon) => coupon.restaurantId == restaurantId)
        .toList();
  }

  int _issuedCouponCountForAffiliate(int restaurantId) {
    if (_affiliateCoupons.isEmpty) return 0;
    final now = DateTime.now();
    return _affiliateCoupons.where((coupon) {
      if (coupon.restaurantId != restaurantId) return false;
      if (coupon.status != CouponStatus.issued) return false;
      final expiresAt = coupon.expiresAt;
      return expiresAt == null || !expiresAt.isBefore(now);
    }).length;
  }

  StampStatus _resolvedStampStatusForAffiliate(AffiliateRestaurantSummary restaurant) {
    final fromServer = _affiliateStampStatuses[restaurant.id];
    if (fromServer != null) return fromServer;
    return StampStatus(
      current: restaurant.stampCurrent,
      target: restaurant.stampTarget,
    );
  }

  bool _isAffiliateInProgress(AffiliateRestaurantSummary restaurant) {
    final issuedCoupons = _issuedCouponCountForAffiliate(restaurant.id);
    final stampStatus = _resolvedStampStatusForAffiliate(restaurant);
    return issuedCoupons > 0 || (!_affiliateRequiresLogin && stampStatus.current > 0);
  }

  String _buildHomeStampLabel(AffiliateRestaurantSummary restaurant) {
    if (_affiliateRequiresLogin) return '스탬프 확인은 로그인 필요';
    final stamp = _resolvedStampStatusForAffiliate(restaurant);
    if (stamp.target > 0) return '스탬프 ${stamp.current}/${stamp.target}';
    if (stamp.current > 0) return '스탬프 ${stamp.current}개';
    return '스탬프 적립 없음';
  }

  String _buildHomeCouponLabel(int restaurantId) {
    if (_affiliateRequiresLogin) return '쿠폰 확인은 로그인 필요';
    final issued = _issuedCouponCountForAffiliate(restaurantId);
    if (issued <= 0) return '사용 가능 쿠폰 없음';
    return '사용 가능 쿠폰 ${issued}장';
  }

  List<AffiliateRestaurantSummary> get _displayAffiliateRestaurants {
    // 적립 중 3개 미만(제휴식당 전체)이든 3개 이상(적립 중)이든, 로드 시 한 번 셔플된 목록 사용
    return _affiliateRestaurants;
  }

  String? _formatCouponExpiry(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final now = DateTime.now();
    final difference = expiresAt.difference(now);
    if (difference.isNegative) return '만료됨';
    if (difference.inHours < 24) {
      if (difference.inHours > 0) return '${difference.inHours}시간 남음';
      if (difference.inMinutes > 0) return '${difference.inMinutes}분 남음';
      return '곧 만료';
    }
    if (difference.inDays < 7) return '${difference.inDays}일 남음';
    return '${expiresAt.year}.${expiresAt.month.toString().padLeft(2, '0')}.${expiresAt.day.toString().padLeft(2, '0')}까지';
  }

  void _handleAffiliateCouponRedeemed(String couponCode, int restaurantId) {
    if (!mounted) return;
    setState(() {
      _affiliateCoupons = _affiliateCoupons
          .where((coupon) => coupon.code != couponCode)
          .toList();
    });
  }

  void _handleAffiliateRewardCouponsIssued(
      List<String> couponCodes, int restaurantId) {
    if (couponCodes.isEmpty) return;
    final existingCodes =
        _affiliateCoupons.map((coupon) => coupon.code).toSet();
    final newCoupons = couponCodes
        .where((code) => !existingCodes.contains(code))
        .map(
          (code) => UserCoupon(
            code: code,
            status: CouponStatus.issued,
            restaurantId: restaurantId,
            issueKey: 'STAMP_REWARD:reward',
          ),
        )
        .toList();
    if (newCoupons.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _affiliateCoupons = List<UserCoupon>.from(_affiliateCoupons)
        ..addAll(newCoupons);
    });
  }

  void _handleAffiliateStampStatusUpdated(
      int restaurantId, StampStatus status) {
    if (!mounted) return;
    setState(() {
      _affiliateStampStatuses =
          Map<int, StampStatus>.from(_affiliateStampStatuses)
            ..[restaurantId] = status;
    });
  }

  Future<void> _openAffiliateRestaurantDetail(
      AffiliateRestaurantSummary restaurant) async {
    // Prevent multiple rapid clicks
    if (_isOpeningAffiliateDetail) return;

    setState(() => _isOpeningAffiliateDetail = true);

    try {
      await _ensureAffiliateUserData();
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return AffiliateRestaurantDetailSheet(
            restaurant: restaurant,
            coupons: _couponsForAffiliate(restaurant.id),
            requiresLogin: _affiliateRequiresLogin,
            source: 'home',
            isFavorite: _isFavoriteRestaurant(restaurant.id),
            onFavoriteChanged: (isFavorite) {
              _setFavoriteRestaurant(restaurant.id, isFavorite);
            },
            initialStampStatus: _affiliateStampStatuses[restaurant.id],
            onStampStatusUpdated: (status) =>
                _handleAffiliateStampStatusUpdated(restaurant.id, status),
            onCouponRedeemed: (code) =>
                _handleAffiliateCouponRedeemed(code, restaurant.id),
            onRewardCouponsIssued: (codes) =>
                _handleAffiliateRewardCouponsIssued(codes, restaurant.id),
          );
        },
      );
    } finally {
      // Reset flag after bottom sheet is closed
      if (mounted) {
        setState(() => _isOpeningAffiliateDetail = false);
      }
    }
  }

  Future<void> _checkWelcomeCouponStatus() async {
    if (_suppressWelcomeCoupon || _isCheckingWelcomeCoupon) return;
    _isCheckingWelcomeCoupon = true;
    try {
      final coupons =
          await CouponService.fetchMyCoupons(status: CouponStatus.issued);
      if (!mounted) return;
      final hasWelcomeCoupon = coupons.any(_isWelcomeCoupon);
      if (!hasWelcomeCoupon ||
          _welcomeDialogVisible ||
          _welcomePromptScheduled) {
        return;
      }
      _welcomePromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _welcomePromptScheduled = false;
          return;
        }
        _showWelcomeCouponDialog();
      });
    } catch (_) {
      // Ignore coupon fetch failures for the welcome dialog.
    } finally {
      _isCheckingWelcomeCoupon = false;
    }
  }

  bool _isWelcomeCoupon(UserCoupon coupon) {
    final benefit = coupon.benefit;
    final candidates = <String>[
      coupon.code,
      benefit?.title ?? '',
      benefit?.subtitle ?? '',
      benefit?.descriptionText ?? '',
    ];
    for (final value in candidates) {
      if (value.isEmpty) continue;
      final lower = value.toLowerCase();
      for (final keyword in _kWelcomeCouponKeywords) {
        if (lower.contains(keyword.toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _showWelcomeCouponDialog() async {
    if (!mounted || _welcomeDialogVisible) {
      _welcomePromptScheduled = false;
      return;
    }
    _welcomeDialogVisible = true;
    bool dontShowAgain = false;
    final bool? shouldSuppress = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                decoration: ShapeDecoration(
                  color: const Color(0xFFF2F2F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '신규가입 쿠폰이 도착했어요\n',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 19,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w800,
                        height: 1.21,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '회원가입을 축하드려요!\n신규가입 쿠폰이 발급되었어요.\n쿠폰함에서 확인하고 사용해 보세요.',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 15,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: const Color(0xFF39393E),
                              side: const BorderSide(color: Color(0xFFBABAC0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            child: const Text('확인'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(dontShowAgain),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1C203C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: -0.32,
                              ),
                            ),
                            child: const Text('다시 보지 않기'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    _welcomeDialogVisible = false;
    _welcomePromptScheduled = false;
    if (shouldSuppress == true) {
      _suppressWelcomeCoupon = true;
      await prefs.setBool(_kWelcomeCouponDismissedKey, true);
    }
  }

  void _handleTrendTap(TrendItem item, int index, bool hasRemoteData) {
    final String url = item.blogLink ?? '';
    final String title = (item.title != null && item.title!.trim().isNotEmpty)
        ? item.title!.trim()
        : _defaultPromotionTitle;
    AnalyticsLogger.logEvent(
      'home_banner_click',
      parameters: {
        'banner_index': index,
        'banner_title': title,
        'banner_url': url,
        'banner_source': hasRemoteData ? 'remote' : 'fallback',
      },
    );
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _launchURL(trimmed);
  }

  void _openCouponList() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CouponListScreen(source: 'home'),
      ),
    );
  }

  void _showHomeSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _extractDetailMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        const keys = ['detail', 'message', 'error'];
        for (final key in keys) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) return value;
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) return first;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // _promptForCouponPin 제거됨 → _showRedeemPinDialog 사용 (입력창 내 에러 표시)

  Future<void> _handleHomeCouponUse(UserCoupon coupon) async {
    if (_processingHomeCouponCode == coupon.code) return;
    final restaurantId = coupon.restaurantId;
    if (restaurantId == null) {
      _showHomeSnack('이 쿠폰은 사용 가능한 매장 정보가 없어요.');
      return;
    }

    UserCoupon? checkedCoupon;
    try {
      checkedCoupon = await CouponService.checkCoupon(couponCode: coupon.code);
    } on ApiAuthException catch (e) {
      _showHomeSnack(e.message);
      return;
    } on ApiHttpException catch (e) {
      _showHomeSnack(_extractDetailMessage(e.body) ?? '쿠폰 확인에 실패했어요.');
      return;
    } on ApiNetworkException catch (e) {
      _showHomeSnack('네트워크 오류: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _processingHomeCouponCode = coupon.code);
    try {
      final success = await _showRedeemPinDialog(
        coupon: coupon,
        restaurantId: restaurantId,
        restaurantName: coupon.benefit?.restaurantNameText,
        notes: checkedCoupon.benefit?.notesText,
        couponIssueSource: getCouponIssuanceSource(coupon.issueKey),
      );
      if (!mounted) return;
      if (success) {
        setState(() {
          _affiliateCoupons = _affiliateCoupons
              .where((element) => element.code != coupon.code)
              .toList();
          _homeCouponShowcase = _homeCouponShowcase
              .where((element) => element.code != coupon.code)
              .toList();
        });
        _showHomeSnack('쿠폰을 사용했어요.');
      }
    } finally {
      if (mounted && _processingHomeCouponCode == coupon.code) {
        setState(() => _processingHomeCouponCode = null);
      }
    }
  }

  /// 쿠폰 사용 PIN 다이얼로그. redeem 실패 시 입력창 내 에러 표시
  Future<bool> _showRedeemPinDialog({
    required UserCoupon coupon,
    required int restaurantId,
    String? restaurantName,
    String? notes,
    String? couponIssueSource,
  }) async {
    final controller = TextEditingController();
    String? error;
    bool isLoading = false;
    final hasNotes = notes != null && notes.isNotEmpty;
    final issueSource =
        couponIssueSource ?? coupon.couponIssueSource;
    return (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: 358,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: ShapeDecoration(
                color: const Color(0xFFF2F2F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '쿠폰 사용',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 19,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w800,
                        height: 1.21,
                      ),
                    ),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 330,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '해당 쿠폰을 사용처리 하시겠습니까?\n관리자 비밀번호를 입력하시면',
                                  style: TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 15,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w500,
                                    height: 1.20,
                                  ),
                                ),
                                TextSpan(
                                  text: ' 즉시 사용처리',
                                  style: TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 15,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w700,
                                    height: 1.20,
                                  ),
                                ),
                                TextSpan(
                                  text: ' 됩니다.',
                                  style: TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 15,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w500,
                                    height: 1.20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (hasNotes) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Color(0xFFE5E5E5),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '사용 조건',
                                  style: TextStyle(
                                    color: Color(0xFF797979),
                                    fontSize: 12,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  notes,
                                  style: const TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 14,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                    const SizedBox(height: 20),
                    const Text(
                      '비밀번호',
                      style: TextStyle(
                        color: Color(0xFF797979),
                        fontSize: 15,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      height: 40,
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(
                            width: 2,
                            color: Color(0xFFD9D9D9),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        maxLength: 4,
                        enabled: !isLoading,
                        style: const TextStyle(
                          color: Color(0xFF39393E),
                          fontSize: 16,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isLoading
                                ? null
                                : () => Navigator.of(dialogContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: const Color(0xFF39393E),
                              side: const BorderSide(color: Color(0xFFBABAC0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    final value = controller.text.trim();
                                    if (value.length != 4) {
                                      setState(() {
                                        error = 'PIN은 4자리 숫자여야 합니다.';
                                      });
                                      return;
                                    }
                                    setState(() {
                                      error = null;
                                      isLoading = true;
                                    });
                                    final result =
                                        await CouponService.redeemCouponWithoutThrow(
                                      couponCode: coupon.code,
                                      restaurantId: restaurantId,
                                      pin: value,
                                    );
                                    if (!dialogContext.mounted) return;
                                    if (result.isSuccess) {
                                      AnalyticsLogger.logEvent(
                                        AnalyticsEvents.couponRedeemed,
                                        parameters: {
                                          AnalyticsEvents.paramCouponCode:
                                              coupon.code,
                                          AnalyticsEvents.paramRestaurantId:
                                              restaurantId,
                                          AnalyticsEvents.paramRestaurantName:
                                              restaurantName ?? '',
                                          AnalyticsEvents.paramCouponIssueSource:
                                              issueSource,
                                        },
                                      );
                                      Navigator.of(dialogContext).pop(true);
                                    } else {
                                      setState(() {
                                        error = result.errorMessage ??
                                            '비밀번호가 올바르지 않아요. 다시 확인해 주세요.';
                                        isLoading = false;
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1C203C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: -0.32,
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('사용하기'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
    )) ?? false;
  }

  // URL 열기 함수
  Future<void> _launchURL(String url) async {
    try {
      await UrlLauncherUtil.launchURL(url);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('URL을 열 수 없습니다: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _refreshFoodsAndRestaurants() async {
    await Future.wait(<Future<void>>[
      _loadTrends(),
      _loadAffiliateRestaurants(),
      _loadFeaturedCampaign(),
    ]);
    if (!_suppressWelcomeCoupon) {
      await _checkWelcomeCouponStatus();
    }
  }

  List<TrendItem> get _promotionItems =>
      _trends.isNotEmpty ? _trends : _defaultPromotionItems;

  List<TrendItem> get _defaultPromotionItems => const <TrendItem>[
        TrendItem(
          imageUrl: _defaultPromotionImage,
          title: _defaultPromotionTitle,
          description: _defaultPromotionDescription,
          blogLink: 'https://example.com/guides/get-started',
        ),
        TrendItem(
          imageUrl: 'https://placehold.co/345x220.png?text=Promo',
          title: '제휴 매장 혜택 모음',
          description: '주변 제휴 매장의 신규 쿠폰과 이벤트를 확인해보세요.',
          blogLink: 'https://example.com/promotions/benefits',
        ),
      ];

  Widget _buildPromotionBanner(double width) {
    final List<TrendItem> items = _promotionItems;
    final int itemCount = items.isNotEmpty ? items.length : 1;
    final bool hasRemoteData = _trends.isNotEmpty;
    // 배너 비율: 가로:세로 = 5:2 → 세로 = 가로 * (2 / 5)
    final double bannerHeight = width <= 0 ? 0 : width * (2 / 5);

    // 로딩 중에는 해상도 표시(placehold) 대신 빈 영역만 표시
    if (_isTrendLoading && !hasRemoteData) {
      return SizedBox(
        height: bannerHeight,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Colors.grey.shade100,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: bannerHeight,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: PageView.builder(
                  key: ValueKey(
                      '${hasRemoteData ? 'remote' : 'fallback'}-$itemCount'),
                  controller: _bannerController,
                  itemCount: itemCount,
                  physics: itemCount > 1
                      ? const PageScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    if (_currentBannerIndex != index) {
                      setState(() {
                        _currentBannerIndex = index;
                      });
                      // 사용자가 수동으로 넘기면 타이머 재시작
                      _startBannerAutoScroll();
                    }
                  },
                  itemBuilder: (context, index) {
                    final TrendItem item = items[index];
                    return _buildPromotionSlide(item, index, hasRemoteData);
                  },
                ),
              ),
              if (_isTrendLoading && !hasRemoteData)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: Colors.black.withOpacity(0.05),
                    ),
                  ),
                ),
              if (_bannerAutoScrollTimer?.isActive ?? false)
                const SizedBox(), // Cleaned up debug text
            ],
          ),
        ),
        if (itemCount > 1)
          Padding(
            // 배너 설명과 인디케이터 사이, 인디케이터와 다음 섹션 사이
            // 간격을 동일하게 맞추기 위해 상하 대칭 패딩을 사용
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildBannerIndicators(itemCount),
          ),
      ],
    );
  }

  Widget _buildPromotionSlide(
    TrendItem item,
    int index,
    bool hasRemoteData,
  ) {
    final bool hasLink = item.hasBlogLink;

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap:
              hasLink ? () => _handleTrendTap(item, index, hasRemoteData) : null,
          child: _buildTrendImage(item.imageUrl),
        ),
      ),
    );
  }

  Widget _buildTrendArrowButton(VoidCallback? onPressed) {
    final bool isEnabled = onPressed != null;
    return SizedBox(
      width: 39.7,
      height: 40.99,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.arrow_forward,
                size: 24,
                color: isEnabled ? Colors.black : Colors.black26,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerIndicators(int itemCount) {
    if (itemCount <= 1) {
      return const SizedBox.shrink();
    }

    final int activeIndex = _currentBannerIndex % itemCount;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(itemCount, (index) {
        final bool isActive = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 12 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF312E81) : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildTrendImage(String imageUrl) {
    if (!_isValidHttpImageUrl(imageUrl)) {
      return Image.asset(
        'assets/images/food_image0.png',
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }
    return Image.network(
      imageUrl.trim(),
      width: double.infinity,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/food_image0.png',
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildMenuCard(String imagePath, String title, double width,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: EdgeInsets.only(right: width * 0.05),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: _isValidHttpImageUrl(imagePath)
                  ? Image.network(
                      imagePath.trim(),
                      height: width * 0.8,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/food_image0.png',
                          height: width * 0.8,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        );
                      },
                    )
                  : Image.asset(
                      imagePath,
                      height: width * 0.8,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            Padding(
              padding: EdgeInsets.all(width * 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: width * 0.08,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startBannerAutoScroll() {
    _bannerAutoScrollTimer?.cancel();

    _bannerAutoScrollTimer = Timer.periodic(_bannerAutoScrollDuration, (timer) {
      if (!mounted || !_bannerController.hasClients) {
        timer.cancel();
        return;
      }

      final itemCount = _promotionItems.length;
      if (itemCount <= 1) return;

      final nextPage = (_currentBannerIndex + 1) % itemCount;

      _bannerController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopBannerAutoScroll() {
    _bannerAutoScrollTimer?.cancel();
    _bannerAutoScrollTimer = null;
  }

  @override
  void dispose() {
    _stopBannerAutoScroll();
    _bannerController.dispose();
    _featuredBannerController.dispose();
    super.dispose();
  }

  // ===== 기획전 캐러셀 (스펙 7.4·7.5, 프로토타입 화면 4) =====

  void _openFeaturedCampaign() {
    final campaign = _featuredCampaign;
    if (campaign == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeaturedCampaignScreen(campaign: campaign),
      ),
    );
  }

  String? _featuredBannerImage(int itemIndex) {
    final campaign = _featuredCampaign;
    if (campaign == null || campaign.items.isEmpty) return null;
    // 배너 수가 기획전 매장 수보다 많아도 빈 배너가 없도록 순환 사용
    final item = campaign.items[itemIndex % campaign.items.length];
    for (final r in _affiliateRestaurants) {
      if (r.id == item.restaurantId && r.imageUrls.isNotEmpty) {
        return r.imageUrls.first;
      }
    }
    return null;
  }

  Widget _buildFeaturedCarousel(double width) {
    final campaign = _featuredCampaign;
    // 진행 중 기획전이 없으면 섹션 전체를 숨긴다. 빈 캐러셀 노출 금지 (스펙 7.4).
    if (campaign == null || !campaign.hasItems) {
      return const SizedBox.shrink();
    }

    final banners = <({String tag, String title, String subtitle})>[
      (tag: '기획전', title: campaign.title, subtitle: campaign.subtitle),
      (
        tag: '기획전 한정',
        title: '기획전 참여 매장',
        subtitle: '쿠폰·스탬프 혜택을\n한 번에 모아봤어요!',
      ),
      (
        tag: '우주라이크 PICK',
        title: '선별 매장 ${campaign.items.length}곳',
        subtitle: '우주라이크가 고른 매장에서만\n열리는 한정 혜택이에요.',
      ),
    ];
    // 카드 폭 = viewportFraction 0.92, 카드 사이 간격 10
    // 높이를 카드 폭에서 파생시켜 기기와 무관하게 에셋 비율(1080×1250 = 1 : 1.157)을 유지
    final double cardWidth = width * 0.92 - 10;
    final double bannerHeight = (cardWidth * 1.157).clamp(0.0, 480.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  campaign.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _openFeaturedCampaign,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '더보기 >',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12.5,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: bannerHeight,
            child: PageView.builder(
              controller: _featuredBannerController,
              // 수동 스와이프만 지원. 자동 넘김 타이머 없음 (스펙 7.5).
              physics: const PageScrollPhysics(),
              itemCount: banners.length,
              onPageChanged: (index) {
                if (_featuredBannerIndex != index) {
                  setState(() => _featuredBannerIndex = index);
                }
              },
              itemBuilder: (context, index) {
                final banner = banners[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _FeaturedBannerCard(
                    tag: banner.tag,
                    title: banner.title,
                    subtitle: banner.subtitle,
                    imageUrl: _featuredBannerImage(index),
                    fallbackAsset:
                        _kFeaturedFallbackAssets[index % _kFeaturedFallbackAssets.length],
                    onTap: _openFeaturedCampaign,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(banners.length, (index) {
              final bool isActive = index == _featuredBannerIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 12 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF312E81)
                      : const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ===== 미션 진행 배너 (프로토타입 화면 4 .mbanner, 스펙 7.5) =====
  // 진행 중 미션이 없으면 렌더링하지 않는다. 쿠폰 만료 정보는 넣지 않는다(중복 방지).
  Widget _buildMissionBanner() {
    final track = _missionTrack;
    if (track == null) return const SizedBox.shrink();
    // 초보자 미션을 다 끝냈으면 일간/주간 반복 미션 배너로 교체한다.
    if (track.beginnerDone && track.hasRoutine) {
      return RoutineMissionBanner(
        track: track,
        onTap: () {
          AnalyticsLogger.logEvent('mission_banner_tap', parameters: {
            'stage': 'routine',
            'remaining': track.routineRemaining,
          });
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MissionTrackScreen(),
            ),
          );
        },
      );
    }
    final total = track.missions.length;
    final remaining = track.remainingCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          AnalyticsLogger.logEvent('mission_banner_tap', parameters: {
            'remaining': remaining,
          });
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MissionTrackScreen(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7E9EF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A14123C),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '미션 깨고 쿠폰 받아가세요',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.46,
                            color: Color(0xFF191F28),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '간단한 미션 $total개, 지금 $remaining개 남았어요',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.12,
                            color: Color(0xFF4E5968),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Transform.rotate(
                    angle: -0.052, // -3deg (프로토타입 .mb-img)
                    child: Image.asset(
                      'assets/images/mission_banner.png',
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildMissionTrackStrip(track),
            ],
          ),
        ),
      ),
    );
  }

  /// 배너 하단 진행 트랙 (프로토타입 .trk): 노드 + 연결선, 마지막은 리워드 노드.
  Widget _buildMissionTrackStrip(MissionTrack track) {
    const primary = Color(0xFF312E81);
    const line = Color(0xFFE7E9EF);
    final missions = track.missions;
    if (missions.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < missions.length; i++) {
      final m = missions[i];
      final isLast = i == missions.length - 1;
      final done = m.status == MissionStatus.claimed;
      final current = m.status == MissionStatus.open ||
          m.status == MissionStatus.ready;

      children.add(
        isLast
            ? Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFBF3DC),
                  border: Border.all(color: const Color(0xFFE1B53E), width: 2),
                ),
                child: const Icon(Icons.card_giftcard,
                    size: 14, color: Color(0xFF8A6410)),
              )
            : Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? primary
                      : (current ? Colors.white : line),
                  border: current
                      ? Border.all(color: primary, width: 2.5)
                      : null,
                ),
                child: done
                    ? const Icon(Icons.check, size: 11, color: Colors.white)
                    : null,
              ),
      );
      if (!isLast) {
        children.add(
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: done ? primary : line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        );
      }
    }

    return Row(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double padding = screenWidth * 0.04;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white, // 스크롤 시 붉은/보라 tint 제거
        scrolledUnderElevation: 0, // 스크롤해도 그림자/색 변화 없도록
        elevation: 0,
        centerTitle: false,
        titleSpacing: padding,
        toolbarHeight: 56,
        title: SizedBox(
          width: 130,
          height: 47,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Would',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.87),
                      fontSize: 23,
                      fontFamily: 'Alkatra',
                      fontWeight: FontWeight.w400,
                      height: 2.61,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'U',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.87),
                      fontSize: 27,
                      fontFamily: 'Alkatra',
                      fontWeight: FontWeight.w500,
                      height: 2.22,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'Like',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.87),
                      fontSize: 23,
                      fontFamily: 'Alkatra',
                      fontWeight: FontWeight.w500,
                      height: 2.61,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: padding),
            child: Tooltip(
              message: 'My coupons',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openCouponList,
                child: Image.asset(
                  'assets/images/coupon.png',
                  width: 29,
                  height: 32,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        // 홈 화면 진입 시 로딩 스타일과 통일된 새로고침 인디케이터
        color: const Color(0xFF6366F1),
        backgroundColor: Colors.white,
        strokeWidth: 2,
        onRefresh: _refreshFoodsAndRestaurants,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding,
              padding,
              padding,
              140, // 하단 바와 겹치지 않도록 홈 화면도 동일한 여백 부여
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 미션 진행 배너 (프로토타입 화면 4 최상단). 진행 중 미션 없으면 미노출
                _buildMissionBanner(),
                // 기획전 캐러셀: 진행 중 기획전 있을 때만 노출 (기존 섹션 순서 유지)
                _buildFeaturedCarousel(screenWidth - padding * 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 이미지 준비 전까지 배너/썸네일 자리를 채우는 회색 플레이스홀더 색상.
/// 기획전 배너 폴백 이미지. 배너 순서대로 돌려 쓴다.
const List<String> _kFeaturedFallbackAssets = <String>[
  'assets/images/food_image0.png',
  'assets/images/food1.png',
  'assets/images/onboarding_hero_plate.png',
];

const Color _placeholderGray = Color(0xFFD9D9D9);
const Color _placeholderInk = Color(0xFF39393E);

class _FeaturedBannerCard extends StatelessWidget {
  const _FeaturedBannerCard({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackAsset,
    required this.onTap,
  });

  final String tag;
  final String title;
  final String subtitle;
  final String? imageUrl;

  /// 기획전 매장 사진이 없을 때 쓸 로컬 이미지. 배너가 회색으로 비지 않게 한다.
  final String fallbackAsset;
  final VoidCallback onTap;

  Widget _buildBackground() {
    final fallback = Image.asset(
      fallbackAsset,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(color: _placeholderGray),
    );
    if (!_isValidHttpImageUrl(imageUrl)) return fallback;
    return Image.network(
      imageUrl!.trim(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 이미지 로딩 전 바탕. 그 위에 기획전 매장 사진(없으면 로컬 이미지)을 채운다.
            const ColoredBox(color: _placeholderGray),
            _buildBackground(),
            // 사진 위에서도 문구가 읽히도록 하단 스크림을 깐다.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _placeholderInk,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: Color(0xE6FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AffiliateRestaurantCard extends StatelessWidget {
  const _AffiliateRestaurantCard({
    required this.restaurant,
    required this.stampLabel,
    required this.couponLabel,
    required this.isInProgress,
    required this.showProgressInfo,
    required this.onTap,
  });

  final AffiliateRestaurantSummary restaurant;
  final String stampLabel;
  final String couponLabel;
  final bool isInProgress;
  final bool showProgressInfo;
  final VoidCallback onTap;

  String get _description {
    final raw = restaurant.description.trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return '상세 설명이 준비 중입니다.';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        restaurant.imageUrls.isNotEmpty ? restaurant.imageUrls.first : null;
    return Stack(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 140,
              height: 256,
              decoration: ShapeDecoration(
                color: const Color(0xFFECEDEF),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: showProgressInfo && isInProgress
                        ? const Color(0xFF6366F1)
                        : Colors.transparent,
                    width: showProgressInfo && isInProgress ? 1.5 : 0,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 128,
                    height: 121,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _buildImage(imageUrl),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 104,
                    child: Text(
                      restaurant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12.6,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: SizedBox(
                      width: 128,
                      child: showProgressInfo
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _StatusChip(
                                  icon: Icons.local_activity_outlined,
                                  text: stampLabel,
                                ),
                                const SizedBox(height: 4),
                                _StatusChip(
                                  icon: Icons.confirmation_num_outlined,
                                  text: couponLabel,
                                ),
                              ],
                            )
                          : Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                _description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF585555),
                                  fontSize: 11.5,
                                  fontFamily: 'Pretendard',
                                  fontWeight: FontWeight.w400,
                                  height: 1.3,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 22,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color(0xFF2D3B53),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: onTap,
                      child: const Text(
                        '자세히 보기 >',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.3,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          height: 1.46,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showProgressInfo && isInProgress)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '진행중',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImage(String? imageUrl) {
    final fallback = Image.asset(
      'assets/images/food_image0.png',
      width: 128,
      height: 121,
      fit: BoxFit.cover,
    );

    if (!_isValidHttpImageUrl(imageUrl)) {
      return fallback;
    }

    return Image.network(
      imageUrl!.trim(),
      width: 128,
      height: 121,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 11,
            color: const Color(0xFF4F46E5),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 10.2,
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCouponCard extends StatelessWidget {
  const _HomeCouponCard({
    required this.coupon,
    required this.expiryText,
    required this.isProcessing,
    required this.onUsePressed,
  });

  final UserCoupon coupon;
  final String? expiryText;
  final bool isProcessing;
  final VoidCallback onUsePressed;

  @override
  Widget build(BuildContext context) {
    final benefit = coupon.benefit;
    final title = benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle;
    final subtitle = benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle;
    final restaurantName = benefit?.restaurantNameText;
    final restaurantLabel = (restaurantName != null && restaurantName.isNotEmpty)
        ? restaurantName
        : (coupon.restaurantId != null ? '적용 매장 ID: ${coupon.restaurantId}' : null);

    // 만료 임박 여부 (3일 이내)
    final expiresAt = coupon.expiresAt;
    final isExpiringSoon = expiresAt != null &&
        !expiresAt.difference(DateTime.now()).isNegative &&
        expiresAt.difference(DateTime.now()).inDays <= 3;
    final isExpiryDateUrgent = expiresAt != null &&
        expiresAt.difference(DateTime.now()) <= const Duration(days: 7);
    final expiryColor = isExpiryDateUrgent
        ? const Color(0xFFB87270)
        : const Color(0xFFE1B53E);

    return Container(
      width: 268,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF192132),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (restaurantLabel != null) ...[
            Text(
              restaurantLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: expiryText != null
                    ? Row(
                        children: [
                          Icon(
                            isExpiringSoon
                                ? Icons.warning_amber_rounded
                                : Icons.access_time,
                            size: 14,
                            color: expiryColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              expiryText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: expiryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: ElevatedButton(
                  onPressed: isProcessing ? null : onUsePressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isExpiringSoon
                        ? const Color(0xFFFFE082)
                        : Colors.white,
                    foregroundColor: isExpiringSoon
                        ? const Color(0xFF7F1D1D)
                        : const Color(0xFF0B1033),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isProcessing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isExpiringSoon
                                ? const Color(0xFF7F1D1D)
                                : const Color(0xFF0B1033),
                          ),
                        )
                      : Text(isExpiringSoon ? '지금 사용' : '사용'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FoodRestaurantListScreen extends StatefulWidget {
  const FoodRestaurantListScreen(
      {super.key, required this.foodName, this.imageUrl});

  final String foodName;
  final String? imageUrl;

  @override
  State<FoodRestaurantListScreen> createState() =>
      _FoodRestaurantListScreenState();
}

class _FoodRestaurantListScreenState extends State<FoodRestaurantListScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
            'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'food_names': [widget.foodName],
        }),
      );

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final restaurants =
            (decoded['random_restaurants'] as List<dynamic>? ?? const [])
                .map<Map<String, dynamic>>(
                    (item) => Map<String, dynamic>.from(item as Map))
                .toList();

        final position = await LocationHelper.getLatLon();
        final userLat = position?['lat'] ?? 35.8714;
        final userLon = position?['lon'] ?? 128.6014;

        final mapped = restaurants.map<Map<String, dynamic>>((restaurant) {
          final restLat =
              double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
          final restLon =
              double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
          final distance =
              DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          return {
            'name': restaurant['name'] ?? '이름 없음',
            'road_address': restaurant['road_address'] ?? '주소 정보 없음',
            'category_2': restaurant['category_2'] ??
                restaurant['category_1'] ??
                '카테고리 정보 없음',
            'distance': distance,
          };
        }).toList();

        if (!mounted) return;
        setState(() {
          _restaurants = mapped;
          _isLoading = false;
        });
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _restaurants = const [];
          _errorMessage = '추천할 만한 맛집을 찾지 못했어요.';
          _isLoading = false;
        });
      } else {
        throw Exception('음식점 정보를 불러오지 못했어요. (status ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '음식점 정보를 불러오지 못했어요. 다시 시도해주세요.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: Text('${widget.foodName} 추천 맛집'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRestaurants,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_restaurants.isEmpty) {
      return const Center(child: Text('추천할 만한 맛집을 찾지 못했어요.'));
    }

    final hasHeaderImage =
        widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final itemCount = _restaurants.length + (hasHeaderImage ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        int dataIndex = index;
        if (hasHeaderImage) {
          if (index == 0) {
            return _FoodHeader(
                imageUrl: widget.imageUrl!, foodName: widget.foodName);
          }
          dataIndex -= 1;
        }

        final restaurant = _restaurants[dataIndex];
        final distance = restaurant['distance'];
        final distanceText =
            distance is num ? '거리 ${distance.toStringAsFixed(1)} km' : null;

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            title: Text(restaurant['name'] ?? '이름 없음'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  restaurant['road_address'] ?? '주소 정보 없음',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                if (distanceText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    distanceText,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  restaurant['category_2'] ?? '카테고리 정보 없음',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FoodHeader extends StatelessWidget {
  const _FoodHeader({required this.imageUrl, required this.foodName});

  final String imageUrl;
  final String foodName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _isValidHttpImageUrl(imageUrl)
              ? Image.network(
                  imageUrl.trim(),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/food_image0.png',
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                )
              : Image.asset(
                  imageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
        ),
        const SizedBox(height: 12),
        Text(
          foodName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _HomePopupCarouselDialog extends StatefulWidget {
  const _HomePopupCarouselDialog({
    required this.popups,
    required this.preloadedImages,
    required this.onTapPopup,
    required this.onDismissToday,
    required this.onClose,
  });

  final List<HomePopupItem> popups;
  final Map<int, Uint8List?> preloadedImages;
  final Future<void> Function(HomePopupItem popup) onTapPopup;
  final Future<void> Function(HomePopupItem popup) onDismissToday;
  final VoidCallback onClose;

  @override
  State<_HomePopupCarouselDialog> createState() => _HomePopupCarouselDialogState();
}

class _HomePopupCarouselDialogState extends State<_HomePopupCarouselDialog> {
  late final PageController _controller;
  Timer? _autoSlideTimer;
  int _currentIndex = 0;
  static const Duration _autoSlideDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _stopAutoSlide();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    if (widget.popups.length <= 1) return;

    _autoSlideTimer = Timer.periodic(_autoSlideDuration, (timer) {
      if (!mounted || !_controller.hasClients) {
        timer.cancel();
        return;
      }

      final itemCount = widget.popups.length;
      if (itemCount <= 1) return;

      final nextPage = (_currentIndex + 1) % itemCount;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final currentPopup = widget.popups[_currentIndex];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 310,
            child: AspectRatio(
              // 에셋 규격 1080×1250 px (1 : 1.157) 기준
              aspectRatio: 1 / 1.157,
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.popups.length,
                physics: widget.popups.length > 1
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  if (_currentIndex != index) {
                    setState(() {
                      _currentIndex = index;
                    });
                    _startAutoSlide();
                  }
                },
                  itemBuilder: (context, index) {
                    final popup = widget.popups[index];
                    return GestureDetector(
                      onTap: () => widget.onTapPopup(popup),
                      child: Container(
                        color: const Color(0xFF111827),
                        child: _PopupImageView(
                          imageBytes: widget.preloadedImages[popup.id],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        if (widget.popups.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.popups.length, (index) {
              final active = index == _currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: active ? 10 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: 310,
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => widget.onDismissToday(currentPopup),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    '오늘 그만 보기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Container(width: 1, height: 18, color: Colors.white38),
              Expanded(
                child: TextButton(
                  onPressed: widget.onClose,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    '닫기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PopupImageView extends StatelessWidget {
  const _PopupImageView({required this.imageBytes});

  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    if (imageBytes == null || imageBytes!.isEmpty) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white70,
        ),
      );
    }
    return Image.memory(
      imageBytes!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}

