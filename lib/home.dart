import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';
import 'affiliate_benefits_screen.dart';
import 'coupon_list_screen.dart';
import 'services/affiliate_service.dart';
import 'services/coupon_service.dart';
import 'services/api_client.dart';
import 'services/trend_service.dart';

const String _kAffiliatePlaceholderImage =
    'https://placehold.co/128x121?text=No+Image';

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
  static const String _defaultPromotionImage = 'https://placehold.co/345x220';
  late SharedPreferences prefs;
  List<TrendItem> _trends = [];
  final PageController _bannerController = PageController();
  List<AffiliateRestaurantSummary> _affiliateRestaurants = [];
  bool _isAffiliateLoading = false;
  String? _affiliateError;
  List<UserCoupon> _affiliateCoupons = [];
  Map<int, StampStatus> _affiliateStampStatuses = {};
  bool _affiliateRequiresLogin = false;
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
  bool _suppressWelcomeCoupon = false;
  @override
  void initState() {
    super.initState();
    _initializePrefs();
    _loadTrends();
    _loadAffiliateRestaurants();
  }

  Future<void> _initializePrefs() async {
    prefs = await SharedPreferences.getInstance();
    _suppressWelcomeCoupon =
        prefs.getBool(_kWelcomeCouponDismissedKey) ?? false;
    if (!_suppressWelcomeCoupon) {
      await _checkWelcomeCouponStatus();
    }
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
      final restaurants = await AffiliateService.fetchRestaurants();
      if (!mounted) return;
      setState(() {
        _affiliateRestaurants = restaurants;
      });
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
        _affiliateRequiresLogin = false;
      });
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _affiliateRequiresLogin = true;
        _affiliateCoupons = const <UserCoupon>[];
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
    } catch (e, stackTrace) {
      debugPrint('Failed to load affiliate coupons: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  List<UserCoupon> _couponsForAffiliate(int restaurantId) {
    if (_affiliateCoupons.isEmpty) return const <UserCoupon>[];
    return _affiliateCoupons
        .where((coupon) => coupon.restaurantId == restaurantId)
        .toList();
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
    await _ensureAffiliateUserData();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return AffiliateRestaurantDetailSheet(
          restaurant: restaurant,
          coupons: _couponsForAffiliate(restaurant.id),
          requiresLogin: _affiliateRequiresLogin,
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
            child: Container(
              width: 358,
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
                    '신규가입 쿠폰이 도착했어요',
                    style: TextStyle(
                      color: Color(0xFF39393E),
                      fontSize: 19,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w800,
                      height: 1.21,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '회원가입을 축하드려요!\n쿠폰함에서 확인하고 사용해 보세요.',
                    style: TextStyle(
                      color: Color(0xFF39393E),
                      fontSize: 14,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w500,
                      height: 1.29,
                    ),
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () {
                      setState(() {
                        dontShowAgain = !dontShowAgain;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: dontShowAgain,
                            onChanged: (value) {
                              setState(() {
                                dontShowAgain = value ?? false;
                              });
                            },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '다시 보지 않기',
                            style: TextStyle(
                              color: Color(0xFF4B5563),
                              fontSize: 13,
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
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
                      child: const Text('확인'),
                    ),
                  ),
                ],
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

  void _handleTrendTap(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _launchURL(trimmed);
  }

  void _openCouponList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CouponListScreen()),
    );
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
          imageUrl: 'https://placehold.co/345x220?text=Promo',
          title: '제휴 매장 혜택 모음',
          description: '주변 제휴 매장의 신규 쿠폰과 이벤트를 확인해보세요.',
          blogLink: 'https://example.com/promotions/benefits',
        ),
      ];

  Widget _buildPromotionBanner(double width) {
    final List<TrendItem> items = _promotionItems;
    final int itemCount = items.isNotEmpty ? items.length : 1;
    final bool hasRemoteData = _trends.isNotEmpty;
    final double bannerHeight = width <= 0 ? 0 : width * (219.53 / 345.0);

    return SizedBox(
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
                }
              },
              itemBuilder: (context, index) {
                final TrendItem item = items[index];
                return _buildPromotionSlide(item);
              },
            ),
          ),
          if (itemCount > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: _buildBannerIndicators(itemCount),
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
        ],
      ),
    );
  }

  Widget _buildPromotionSlide(TrendItem item) {
    final bool hasLink = item.hasBlogLink;
    final String title = (item.title != null && item.title!.trim().isNotEmpty)
        ? item.title!.trim()
        : _defaultPromotionTitle;
    final String description =
        (item.description != null && item.description!.trim().isNotEmpty)
            ? item.description!.trim()
            : _defaultPromotionDescription;

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasLink ? () => _handleTrendTap(item.blogLink!) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildTrendImage(item.imageUrl),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 18,
                    bottom: 24,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0.5, 0.0),
                      end: Alignment(0.5, 1.0),
                      colors: [
                        Color(0xFFEEEFF1),
                        Color(0xFFEDEEF0),
                        Color(0xFFEBECEE),
                        Color(0xFFEEEFF1),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildTrendArrowButton(
                        hasLink ? () => _handleTrendTap(item.blogLink!) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
    final String resolvedUrl =
        imageUrl.trim().isNotEmpty ? imageUrl : _defaultPromotionImage;
    return Image.network(
      resolvedUrl,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => Image.network(
        _defaultPromotionImage,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFE5E7EB),
        ),
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
              child: imagePath.startsWith('http')
                  ? Image.network(
                      imagePath,
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

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  Widget _buildAffiliateRestaurantsSection() {
    const header = Text(
      '내 주변에서 즐기는 우주라이크 혜택',
      style: TextStyle(
        color: Color(0xFF111827),
        fontSize: 18,
        fontFamily: 'Pretendard',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    );

    if (_isAffiliateLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          const SizedBox(
            height: 256,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_affiliateError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _affiliateError!,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    if (_affiliateRestaurants.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        Container(
          height: 256,
          width: double.infinity,
          color: Colors.white,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: _affiliateRestaurants.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final restaurant = _affiliateRestaurants[index];
              return _AffiliateRestaurantCard(
                restaurant: restaurant,
                onTap: () => _openAffiliateRestaurantDetail(restaurant),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double padding = screenWidth * 0.04;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
        onRefresh: _refreshFoodsAndRestaurants,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: padding * 0.8),
                _buildPromotionBanner(screenWidth),
                SizedBox(height: padding * 0.8),
                if (_hasAffiliateContent) ...[
                  _buildAffiliateRestaurantsSection(),
                  SizedBox(height: padding * 0.8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AffiliateRestaurantCard extends StatelessWidget {
  const _AffiliateRestaurantCard({
    required this.restaurant,
    required this.onTap,
  });

  final AffiliateRestaurantSummary restaurant;
  final VoidCallback onTap;

  String get _description {
    final raw = restaurant.description.trim();
    if (raw.isNotEmpty) {
      return raw;
    }
    return '상세 설명이 준비 중입니다.';
  }

  String get _displayName {
    // 식당명에서 마지막 "점" 부분 제거
    // 예: "스톡홀름샐러드 정문점" -> "스톡홀름샐러드"
    // 예: "대부 대왕유부초밥 경대점" -> "대부 대왕유부초밥"
    final name = restaurant.name.trim();

    // 마지막에 공백 + 한글 + "점" 패턴 제거
    final pattern = RegExp(r'\s+[가-힣]+점$');
    if (pattern.hasMatch(name)) {
      return name.replaceAll(pattern, '');
    }

    // 마지막에 "점"으로 끝나는 경우 (공백 없이)
    if (name.endsWith('점') && name.length > 1) {
      // 마지막 "점" 앞이 한글인 경우만 제거
      final lastChar = name[name.length - 2];
      if (RegExp(r'[가-힣]').hasMatch(lastChar)) {
        return name.substring(0, name.length - 1);
      }
    }

    return name;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        restaurant.imageUrls.isNotEmpty ? restaurant.imageUrls.first : null;
    return Material(
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
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12.6,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 128,
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
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                height: 22,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF312E81),
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
    );
  }

  Widget _buildImage(String? imageUrl) {
    final fallback = Image.asset(
      'assets/images/food_image0.png',
      width: 128,
      height: 121,
      fit: BoxFit.cover,
    );

    if (imageUrl == null || imageUrl.isEmpty) {
      return Image.network(
        _kAffiliatePlaceholderImage,
        width: 128,
        height: 121,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Image.network(
      imageUrl,
      width: 128,
      height: 121,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.network(
        _kAffiliatePlaceholderImage,
        width: 128,
        height: 121,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
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
          child: imageUrl.startsWith('http')
              ? Image.network(
                  imageUrl,
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
