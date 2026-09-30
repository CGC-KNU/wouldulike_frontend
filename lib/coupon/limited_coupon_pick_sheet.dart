import 'package:flutter/material.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/data/campus_options.dart';
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
  /// 고른 식당 id. 여러 곳을 고르는 오퍼는 검색·카테고리를 바꿔도 선택을 유지한다.
  final List<int> _selectedIds = [];
  String _categoryKey = 'ALL';
  String _selectedCampus = kCampusFilterAll;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _submitting = false;
  String? _error;

  LimitedCouponOffer get offer => widget.offer;

  int get _picksNeeded => offer.picksNeeded < 1 ? 1 : offer.picksNeeded;

  bool get _selectionComplete => _selectedIds.length == _picksNeeded;

  void _toggle(int restaurantId) {
    setState(() {
      _error = null;
      if (!offer.isMultiPick) {
        _selectedIds
          ..clear()
          ..add(restaurantId);
        return;
      }
      if (_selectedIds.remove(restaurantId)) return;
      if (_selectedIds.length >= _picksNeeded) {
        _error = '$_picksNeeded곳까지 고를 수 있어요. 바꾸려면 먼저 하나를 빼 주세요.';
        return;
      }
      _selectedIds.add(restaurantId);
    });
  }

  /// 단일 선택은 목록이 바뀌면 보이지 않는 식당이 선택된 채 남지 않게 비운다.
  void _resetSingleSelection() {
    if (!offer.isMultiPick) _selectedIds.clear();
  }

  late final List<AffiliateRestaurantSummary> _restaurants = [
    for (final r in offer.restaurants)
      AffiliateRestaurantSummary(
        id: r.restaurantId,
        name: r.name,
        description: r.benefitLine ?? r.notes ?? '',
        address: '',
        category: r.category ?? '',
        zone: r.zone ?? '',
        campus: r.campus,
        phoneNumber: '',
        url: '',
        imageUrls: r.imageUrl == null || r.imageUrl!.isEmpty
            ? const []
            : [r.imageUrl!],
        stampCurrent: 0,
        stampTarget: 0,
      ),
  ];

  /// 후보 식당들에 실제로 찍혀 있는 대학가 값. 하나도 없으면(구버전 응답 등)
  /// 필터를 아예 보여주지 않는다.
  late final List<String> _campusOptions = {
    for (final r in _restaurants)
      if (r.campus != null && r.campus!.trim().isNotEmpty) r.campus!.trim(),
  }.toList()
    ..sort();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AffiliateRestaurantSummary> get _visibleRestaurants {
    final query = _searchQuery.trim().toLowerCase();
    return _restaurants.where((r) {
      if (_selectedCampus != kCampusFilterAll && r.campus != _selectedCampus) {
        return false;
      }
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
    if (!_selectionComplete) {
      setState(() => _error = offer.isMultiPick
          ? '식당 $_picksNeeded곳을 골라 주세요.'
          : '식당을 선택해 주세요.');
      return;
    }
    final ids = List<int>.of(_selectedIds);
    final allowed = ids.every(
        (id) => offer.restaurants.any((r) => r.restaurantId == id));
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
      restaurantId: ids.first,
      restaurantIds: offer.isMultiPick ? ids : null,
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      setState(() {
        _submitting = false;
        _error = result.errorMessage ?? '쿠폰을 받지 못했어요.';
      });
      return;
    }
    // period == DAILY인 단일 선택 오퍼는 오늘 이미 받았으면 새로 발급하지
    // 않고 오늘 받은 쿠폰을 그대로 201로 돌려준다. 고른 식당과 다르면 새로
    // 받은 게 아니라는 뜻이니 축하 팝업 대신 안내만 하고 끝낸다.
    // (다중 선택 오퍼는 issued_coupons 순서가 선택 순서와 다를 수 있어
    // 이 비교 대상이 아니다.)
    if (!offer.isMultiPick &&
        result.issuedCoupons.isNotEmpty &&
        result.issuedCoupons.first.restaurantId != null &&
        result.issuedCoupons.first.restaurantId != ids.first) {
      setState(() {
        _submitting = false;
        _error = '오늘은 이미 받았어요.';
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
    final restaurantByCode = {
      for (final coupon in result.issuedCoupons)
        if (coupon.code.isNotEmpty) coupon.code: coupon.restaurantId,
    };
    for (final code in codes) {
      final restaurantId =
          restaurantByCode[code] ?? (ids.length == 1 ? ids.first : null);
      AnalyticsLogger.logEvent(
        AnalyticsEvents.couponClaim,
        parameters: {
          AnalyticsEvents.paramCouponCode: code,
          if (restaurantId != null)
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

  String get _buttonLabel {
    if (_submitting) return '받는 중…';
    if (!offer.isMultiPick) return '이 식당 쿠폰 받기';
    if (_selectionComplete) return '$_picksNeeded곳 쿠폰 받기';
    return '식당 고르기 (${_selectedIds.length}/$_picksNeeded)';
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
              Text(
                offer.isMultiPick
                    ? '쿠폰을 받을 식당 $_picksNeeded곳을 골라 주세요.'
                    : '원하는 식당을 선택해 주세요.',
                style: OnboardingStyle.subtitle,
              ),
              if (offer.pickCount > offer.remainingCount &&
                  offer.remainingCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${offer.pickCount}곳 중 ${offer.pickCount - offer.remainingCount}곳은 이미 받았어요.',
                  style: OnboardingStyle.caption,
                ),
              ],
              if (offer.validHours != null && offer.validHours! > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '받은 시각부터 ${offer.validHours}시간 동안 쓸 수 있어요.',
                  style: OnboardingStyle.caption,
                ),
              ] else if (offer.validDays != null && offer.validDays! > 0) ...[
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
              if (_campusOptions.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildCampusFilter(),
                ),
                const SizedBox(height: 8),
              ],
              _buildSearchBar(),
              const SizedBox(height: 4),
              CategoryStrip(
                selected: _categoryKey,
                onSelect: (key) => setState(() {
                  _categoryKey = key;
                  _resetSingleSelection();
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
                  enabled: !_submitting && _selectionComplete,
                ),
                onPressed: _submitting || !_selectionComplete ? null : _claim,
                child: Text(_buttonLabel),
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

  String _campusFilterLabel(String value) =>
      value == kCampusFilterAll ? '전체' : value;

  /// 이 오퍼 식당에 실제로 있는 대학가만 고른다. 없으면 호출하지 않는다.
  Widget _buildCampusFilter() {
    final options = <String>[kCampusFilterAll, ..._campusOptions];
    final isFiltered = _selectedCampus != kCampusFilterAll;
    return PopupMenuButton<String>(
      enabled: !_submitting,
      offset: const Offset(0, 8),
      color: Colors.white,
      elevation: 3,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == _selectedCampus) return;
        setState(() {
          _selectedCampus = value;
          _resetSingleSelection();
          _error = null;
        });
      },
      itemBuilder: (context) => [
        for (final value in options)
          PopupMenuItem<String>(
            value: value,
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _campusFilterLabel(value),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: value == _selectedCampus
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: value == _selectedCampus
                          ? OnboardingStyle.primary
                          : OnboardingStyle.ink,
                    ),
                  ),
                ),
                if (value == _selectedCampus)
                  const Icon(Icons.check_rounded,
                      size: 18, color: OnboardingStyle.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: ShapeDecoration(
          color: isFiltered ? OnboardingStyle.accentSoft : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color:
                  isFiltered ? OnboardingStyle.accent : OnboardingStyle.line,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _campusFilterLabel(_selectedCampus),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isFiltered
                    ? OnboardingStyle.primary
                    : OnboardingStyle.body,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color:
                  isFiltered ? OnboardingStyle.primary : OnboardingStyle.body,
            ),
          ],
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
          _resetSingleSelection();
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
                      _resetSingleSelection();
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
      selectedIndex: null,
      isSelected: (r) => _selectedIds.contains(r.id),
      onSelect: _submitting ? (_) {} : (i) => _toggle(visible[i].id),
      onRetry: () {},
      detailOf: (summary) {
        final source = _offerRestaurant(summary.id);
        if (source == null) return null;
        return source.benefitLine;
      },
    );
  }
}
