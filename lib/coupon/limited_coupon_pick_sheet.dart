import 'package:flutter/material.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/onboarding/onboarding_style.dart';
import 'package:new1/onboarding/widgets/restaurant_pick_list.dart';
import 'package:new1/services/affiliate_service.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/utils/analytics_logger.dart';
import 'package:new1/widgets/category_strip.dart';

class LimitedCouponPickResult {
  const LimitedCouponPickResult({
    required this.claimed,
    this.issuedCodes = const [],
    this.title,
  });

  final bool claimed;
  final List<String> issuedCodes;
  final String? title;
}

/// 기획전 한정쿠폰 식당 선택. 온보딩 튜토리얼과 같은 전체 화면 선택 UI.
Future<LimitedCouponPickResult?> showLimitedCouponPickSheet(
  BuildContext context, {
  required LimitedCouponOffer offer,
}) {
  return Navigator.of(context, rootNavigator: true).push<LimitedCouponPickResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LimitedCouponPickSheet(offer: offer),
    ),
  );
}

class LimitedCouponPickSheet extends StatefulWidget {
  const LimitedCouponPickSheet({super.key, required this.offer});

  final LimitedCouponOffer offer;

  @override
  State<LimitedCouponPickSheet> createState() => _LimitedCouponPickSheetState();
}

class _LimitedCouponPickSheetState extends State<LimitedCouponPickSheet> {
  int? _selectedIndex;
  String _categoryKey = 'ALL';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _submitting = false;
  String? _error;

  LimitedCouponOffer get offer => widget.offer;

  late final List<AffiliateRestaurantSummary> _restaurants = [
    for (final r in offer.restaurants)
      AffiliateRestaurantSummary(
        id: r.restaurantId,
        name: r.name,
        description: r.benefitLine ?? r.notes ?? '',
        address: '',
        category: r.category ?? '',
        zone: r.zone ?? '',
        phoneNumber: '',
        url: '',
        imageUrls: r.imageUrl == null || r.imageUrl!.isEmpty
            ? const []
            : [r.imageUrl!],
        stampCurrent: 0,
        stampTarget: 0,
      ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AffiliateRestaurantSummary> get _visibleRestaurants {
    final query = _searchQuery.trim().toLowerCase();
    return _restaurants.where((r) {
      if (_categoryKey != 'ALL' &&
          normalizeCategoryKey(r.category) != _categoryKey) {
        return false;
      }
      if (query.isEmpty) return true;
      return r.name.toLowerCase().contains(query) ||
          r.category.toLowerCase().contains(query) ||
          r.zone.toLowerCase().contains(query);
    }).toList();
  }

  LimitedCouponRestaurant? _offerRestaurant(int restaurantId) {
    for (final r in offer.restaurants) {
      if (r.restaurantId == restaurantId) return r;
    }
    return null;
  }

  Future<void> _claim() async {
    final visible = _visibleRestaurants;
    if (_selectedIndex == null || _selectedIndex! >= visible.length) {
      setState(() => _error = '식당을 선택해 주세요.');
      return;
    }
    final restaurantId = visible[_selectedIndex!].id;
    final allowed =
        offer.restaurants.any((r) => r.restaurantId == restaurantId);
    if (!allowed) {
      setState(() => _error = '이 식당은 한정쿠폰 대상이 아니에요.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    final result = await CouponService.claimLimitedCoupon(
      couponTypeCode: offer.couponTypeCode,
      restaurantId: restaurantId,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _submitting = false;
        _error = result.errorMessage ?? '쿠폰을 받지 못했어요.';
      });
      return;
    }
    final codes = result.issuedCoupons
        .map((c) => c.code)
        .where((c) => c.isNotEmpty)
        .toList();
    if (result.couponCode != null &&
        result.couponCode!.isNotEmpty &&
        !codes.contains(result.couponCode)) {
      codes.insert(0, result.couponCode!);
    }
    // 사용자가 「받기」를 눌러 **성공한** 순간. coupon_issued(보였다)와 달리
    // 이건 행동이라 전환율의 분자로 쓸 수 있다. 실패는 위에서 이미 돌아갔다.
    // 쿠폰이 여럿이면 장마다 찍어 coupon_code 로 사용과 이을 수 있게 둔다.
    for (final code in codes) {
      AnalyticsLogger.logEvent(
        AnalyticsEvents.couponClaim,
        parameters: {
          AnalyticsEvents.paramCouponCode: code,
          AnalyticsEvents.paramRestaurantId: restaurantId,
          AnalyticsEvents.paramCouponTypeCode: offer.couponTypeCode,
          AnalyticsEvents.paramSource: 'limited_coupon_sheet',
        },
      );
    }
    Navigator.of(context).pop(
      LimitedCouponPickResult(
        claimed: true,
        issuedCodes: codes,
        title: offer.couponTypeTitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = offer.couponTypeTitle?.trim();
    final visible = _visibleRestaurants;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (title != null && title.isNotEmpty) ? title : '어디서 쓸까요?',
                style: OnboardingStyle.title,
              ),
              const SizedBox(height: 8),
              const Text(
                '원하는 식당을 선택해 주세요.',
                style: OnboardingStyle.subtitle,
              ),
              if (offer.validDays != null && offer.validDays! > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '받은 날부터 ${offer.validDays}일 동안 쓸 수 있어요.',
                  style: OnboardingStyle.caption,
                ),
              ],
              if (offer.redeemBonus) ...[
                const SizedBox(height: 6),
                const Text(
                  '이 쿠폰을 사용하면 한정쿠폰이 한 장 더 지급됩니다.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: OnboardingStyle.primary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildSearchBar(),
              const SizedBox(height: 4),
              CategoryStrip(
                selected: _categoryKey,
                onSelect: (key) => setState(() {
                  _categoryKey = key;
                  _selectedIndex = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildRestaurantList(visible)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OnboardingStyle.danger,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                style: OnboardingStyle.primaryButton(
                  enabled: !_submitting && _selectedIndex != null,
                ),
                onPressed: _submitting || _selectedIndex == null ? null : _claim,
                child: Text(_submitting ? '받는 중…' : '이 식당 쿠폰 받기'),
              ),
              Center(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(
                            const LimitedCouponPickResult(claimed: false),
                          ),
                  style: TextButton.styleFrom(
                    foregroundColor: OnboardingStyle.muted,
                    textStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('나중에'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      decoration: ShapeDecoration(
        color: const Color(0xFFF4F5F7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        enabled: !_submitting,
        style: const TextStyle(
          color: Color(0xFF39393E),
          fontSize: 14,
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w600,
        ),
        onChanged: (value) => setState(() {
          _searchQuery = value;
          _selectedIndex = null;
          _error = null;
        }),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          hintText: '식당 검색',
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 14.5,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
          ),
          prefixIcon:
              const Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: const Color(0xFF6B7280),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _selectedIndex = null;
                    });
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildRestaurantList(List<AffiliateRestaurantSummary> visible) {
    if (visible.isEmpty && _restaurants.isNotEmpty) {
      return const Center(
        child: Text('조건에 맞는 식당이 없어요', style: OnboardingStyle.subtitle),
      );
    }
    return RestaurantPickList(
      loading: false,
      failed: visible.isEmpty,
      restaurants: visible,
      selectedIndex: _selectedIndex,
      onSelect: _submitting
          ? (_) {}
          : (i) => setState(() {
                _selectedIndex = i;
                _error = null;
              }),
      onRetry: () {},
      detailOf: (summary) {
        final source = _offerRestaurant(summary.id);
        if (source == null) return null;
        return source.benefitLine;
      },
    );
  }
}
