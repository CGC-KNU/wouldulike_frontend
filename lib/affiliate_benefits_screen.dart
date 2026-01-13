import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/affiliate_service.dart';
import 'services/api_client.dart';
import 'services/coupon_service.dart';

StampStatus _defaultStampStatusForRestaurant(
  AffiliateRestaurantSummary restaurant, {
  int? fallbackTarget,
  bool preferZeroTarget = false,
}) {
  final resolvedTarget = preferZeroTarget
      ? 0
      : (restaurant.stampTarget > 0
          ? restaurant.stampTarget
          : (fallbackTarget ?? 0));
  return StampStatus(
    current: 0,
    target: resolvedTarget,
    updatedAt: null,
  );
}

class AffiliateBenefitsScreen extends StatefulWidget {
  const AffiliateBenefitsScreen({super.key});

  @override
  State<AffiliateBenefitsScreen> createState() =>
      _AffiliateBenefitsScreenState();
}

class _CategoryMeta {
  const _CategoryMeta(this.label, this.assetPath);

  final String label;
  final String assetPath;
}

const Map<String, _CategoryMeta> _kCategoryMeta = {
  'ALL': _CategoryMeta('전체', 'assets/images/total.png'),
  'KOREAN': _CategoryMeta('한식', 'assets/images/korean.png'),
  'CHINESE': _CategoryMeta('중식', 'assets/images/chinese.png'),
  'JAPANESE': _CategoryMeta('일식', 'assets/images/japanese.png'),
  'WESTERN': _CategoryMeta('양식', 'assets/images/western.png'),
  'SNACK': _CategoryMeta('분식', 'assets/images/snack.png'),
  'PUB': _CategoryMeta('술집', 'assets/images/pub.png'),
  'OTHER': _CategoryMeta('기타', 'assets/images/other.png'),
};

const Map<String, String> _kCategoryAlias = {
  'ALL': 'ALL',
  '전체': 'ALL',
  'KOREAN': 'KOREAN',
  '한식': 'KOREAN',
  'CHINESE': 'CHINESE',
  '중식': 'CHINESE',
  'JAPANESE': 'JAPANESE',
  '일식': 'JAPANESE',
  'WESTERN': 'WESTERN',
  '양식': 'WESTERN',
  'SNACK': 'SNACK',
  '분식': 'SNACK',
  'PUB': 'PUB',
  'BAR': 'PUB',
  '술집': 'PUB',
  'OTHER': 'OTHER',
  '기타': 'OTHER',
  'ETC': 'OTHER',
};

const List<String> _kCategoryOrder = [
  'ALL',
  'KOREAN',
  'CHINESE',
  'JAPANESE',
  'WESTERN',
  'SNACK',
  'PUB',
  'OTHER',
];

class _AffiliateBenefitsScreenState extends State<AffiliateBenefitsScreen> {
  List<AffiliateRestaurantSummary> _restaurants = [];
  List<UserCoupon> _issuedCoupons = [];
  Map<int, int> _couponCounts = {};
  Map<int, StampStatus> _stampStatuses = {};
  bool _isLoading = false;
  String? _error;
  bool _requiresLogin = false;
  String _selectedCategory = 'ALL';
  List<String> _categories = const ['ALL'];
  bool _isOpeningDetail = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final restaurants = await AffiliateService.fetchRestaurants();
      final issuedCoupons = await _fetchIssuedCoupons();

      final categories = <String>{'ALL'};
      for (final restaurant in restaurants) {
        if (restaurant.category.isNotEmpty) {
          categories.add(restaurant.category);
        }
      }

      if (!mounted) return;
      setState(() {
        _restaurants = restaurants;
        _issuedCoupons = _sortCouponsByStatus(issuedCoupons);
        _couponCounts = _buildCouponCounts(issuedCoupons);
        _stampStatuses = {};
        _categories = categories.toList();
        _selectedCategory = 'ALL';
      });

      if (_requiresLogin || !mounted) return;

      try {
        final statuses = await _fetchStampStatuses(restaurants);
        if (!mounted) return;
        setState(() {
          _stampStatuses = statuses;
          _restaurants = _applyStampStatuses(_restaurants, statuses);
        });
      } on ApiAuthException catch (e) {
        if (!mounted) return;
        setState(() {
          _requiresLogin = true;
          _error = e.message;
          _stampStatuses = {};
        });
      } on ApiNetworkException catch (_) {
        // Silently ignore stamp sync failures caused by transient connectivity issues.
      } on ApiHttpException catch (_) {
        // Silently ignore stamp sync failures caused by per-restaurant API errors.
      }
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() => _error = '네트워크 연결 오류: $e');
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'HTTP ${e.statusCode}: ${e.body}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<UserCoupon>> _fetchIssuedCoupons() async {
    try {
      final coupons = await CouponService.fetchMyCoupons(
        status: CouponStatus.issued,
      );
      if (mounted) {
        setState(() => _requiresLogin = false);
      }
      return coupons;
    } on ApiAuthException catch (e) {
      if (mounted) {
        setState(() {
          _requiresLogin = true;
          _error = e.message;
        });
      }
      return const [];
    } on ApiHttpException catch (e) {
      if (mounted) {
        setState(() {
          _requiresLogin = false;
          _error = 'HTTP ${e.statusCode}: ${e.body}';
        });
      }
      return const [];
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
      return const [];
    }
  }

  Map<int, int> _buildCouponCounts(List<UserCoupon> coupons) {
    final counts = <int, int>{};
    for (final coupon in coupons) {
      final restaurantId = coupon.restaurantId;
      if (restaurantId == null) continue;
      counts.update(restaurantId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  int _couponStatusPriority(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return 0;
      case CouponStatus.redeemed:
        return 1;
      case CouponStatus.expired:
        return 2;
      case CouponStatus.canceled:
        return 3;
      case CouponStatus.unknown:
        return 4;
    }
  }

  List<UserCoupon> _sortCouponsByStatus(List<UserCoupon> coupons) {
    final sorted = List<UserCoupon>.from(coupons);
    sorted.sort((a, b) {
      final priorityDiff =
          _couponStatusPriority(a.status) - _couponStatusPriority(b.status);
      if (priorityDiff != 0) return priorityDiff;
      return a.code.compareTo(b.code);
    });
    return sorted;
  }

  Future<Map<int, StampStatus>> _fetchStampStatuses(
      List<AffiliateRestaurantSummary> restaurants) async {
    try {
      final collection = await CouponService.fetchAllStampStatuses();
      return _mergeWithDefaultStampStatuses(
        restaurants,
        collection,
      );
    } on ApiAuthException {
      rethrow;
    } catch (_) {
      // Fallback to per-restaurant fetching when the bulk endpoint fails.
      final statuses = <int, StampStatus>{};
      for (final restaurant in restaurants) {
        if (restaurant.id == 0) continue;
        try {
          final status = await CouponService.fetchStampStatus(
            restaurantId: restaurant.id,
          );
          statuses[restaurant.id] = status;
        } on ApiAuthException {
          rethrow;
        } catch (_) {
          // Ignore per-restaurant failures so other entries can still load.
        }
      }
      return _mergeWithDefaultStampStatuses(
        restaurants,
        StampStatusCollection(
          statuses: statuses,
          defaultTarget: null,
          hasResults: statuses.isNotEmpty,
        ),
      );
    }
  }

  Map<int, StampStatus> _mergeWithDefaultStampStatuses(
    List<AffiliateRestaurantSummary> restaurants,
    StampStatusCollection collection,
  ) {
    final merged = Map<int, StampStatus>.from(collection.statuses);
    for (final restaurant in restaurants) {
      final restaurantId = restaurant.id;
      if (restaurantId == 0 || merged.containsKey(restaurantId)) continue;
      merged[restaurantId] = _defaultStampStatusForRestaurant(
        restaurant,
        fallbackTarget: collection.defaultTarget,
        preferZeroTarget: !collection.hasResults,
      );
    }
    return merged;
  }

  AffiliateRestaurantSummary _copyRestaurantWithStampStatus(
      AffiliateRestaurantSummary restaurant, StampStatus status) {
    return AffiliateRestaurantSummary(
      id: restaurant.id,
      name: restaurant.name,
      description: restaurant.description,
      address: restaurant.address,
      category: restaurant.category,
      zone: restaurant.zone,
      phoneNumber: restaurant.phoneNumber,
      url: restaurant.url,
      imageUrls: restaurant.imageUrls,
      stampCurrent: status.current,
      stampTarget: status.target,
    );
  }

  List<AffiliateRestaurantSummary> _applyStampStatuses(
    List<AffiliateRestaurantSummary> restaurants,
    Map<int, StampStatus> statuses,
  ) {
    if (statuses.isEmpty) return restaurants;
    return restaurants
        .map(
          (restaurant) => statuses.containsKey(restaurant.id)
              ? _copyRestaurantWithStampStatus(
                  restaurant, statuses[restaurant.id]!)
              : restaurant,
        )
        .toList();
  }

  List<AffiliateRestaurantSummary> get _filteredRestaurants {
    if (_selectedCategory == 'ALL') return _restaurants;
    return _restaurants
        .where((restaurant) => restaurant.category == _selectedCategory)
        .toList();
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() => _selectedCategory = category);
  }

  List<String> _sortCategories(Iterable<String> source) {
    final list = source.toSet().toList();
    list.sort((a, b) {
      final orderA = _categoryOrderIndex(a);
      final orderB = _categoryOrderIndex(b);
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      return a.compareTo(b);
    });
    return list;
  }

  int _categoryOrderIndex(String category) {
    final normalized = _normalizeCategoryKey(category);
    final index = _kCategoryOrder.indexOf(normalized);
    return index == -1 ? _kCategoryOrder.length : index;
  }

  String _normalizeCategoryKey(String category) {
    final normalized = category.trim().toUpperCase();
    return _kCategoryAlias[normalized] ?? _kCategoryAlias[category.trim()] ?? 'OTHER';
  }

  _CategoryMeta _resolveCategoryMeta(String category) {
    final key = _normalizeCategoryKey(category);
    final meta = _kCategoryMeta[key];
    if (meta != null) {
      return meta;
    }
    final trimmed = category.trim();
    final label = trimmed.isEmpty ? '기타' : (category == 'ALL' ? '전체' : trimmed);
    return _CategoryMeta(label, _kCategoryMeta['OTHER']!.assetPath);
  }

  List<UserCoupon> _couponsForRestaurant(int restaurantId) {
    final filtered = _issuedCoupons
        .where((coupon) => coupon.restaurantId == restaurantId)
        .toList();
    return _sortCouponsByStatus(filtered);
  }

  void _handleCouponRedeemed(String couponCode, int restaurantId) {
    setState(() {
      _issuedCoupons =
          _issuedCoupons.where((coupon) => coupon.code != couponCode).toList();
      final current = _couponCounts[restaurantId] ?? 0;
      if (current <= 1) {
        _couponCounts.remove(restaurantId);
      } else {
        _couponCounts[restaurantId] = current - 1;
      }
    });
  }

  void _handleRewardCouponsIssued(List<String> couponCodes, int restaurantId) {
    if (couponCodes.isEmpty) return;
    final existingCodes = _issuedCoupons.map((coupon) => coupon.code).toSet();
    final newCoupons = couponCodes
        .where((code) => code.isNotEmpty && !existingCodes.contains(code))
        .map(
          (code) => UserCoupon(
            code: code,
            status: CouponStatus.issued,
            restaurantId: restaurantId,
          ),
        )
        .toList();
    if (newCoupons.isEmpty) return;
    setState(() {
      _issuedCoupons = _sortCouponsByStatus(
          List<UserCoupon>.from(_issuedCoupons)..addAll(newCoupons));
      _couponCounts.update(
        restaurantId,
        (value) => value + newCoupons.length,
        ifAbsent: () => newCoupons.length,
      );
    });
  }

  void _handleStampStatusUpdated(int restaurantId, StampStatus status) {
    setState(() {
      _stampStatuses = Map<int, StampStatus>.from(_stampStatuses)
        ..[restaurantId] = status;
      final index = _restaurants
          .indexWhere((restaurant) => restaurant.id == restaurantId);
      if (index != -1) {
        final updated = _copyRestaurantWithStampStatus(
          _restaurants[index],
          status,
        );
        _restaurants = List<AffiliateRestaurantSummary>.from(_restaurants)
          ..[index] = updated;
      }
    });
  }

  Future<void> _openRestaurantDetail(
      AffiliateRestaurantSummary restaurant) async {
    // Prevent multiple rapid clicks
    if (_isOpeningDetail) return;

    setState(() => _isOpeningDetail = true);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return AffiliateRestaurantDetailSheet(
            restaurant: restaurant,
            coupons: _couponsForRestaurant(restaurant.id),
            requiresLogin: _requiresLogin,
            initialStampStatus: _stampStatuses[restaurant.id],
            onStampStatusUpdated: (status) =>
                _handleStampStatusUpdated(restaurant.id, status),
            onCouponRedeemed: (code) =>
                _handleCouponRedeemed(code, restaurant.id),
            onRewardCouponsIssued: (codes) =>
                _handleRewardCouponsIssued(codes, restaurant.id),
          );
        },
      );
    } finally {
      // Reset flag after bottom sheet is closed
      if (mounted) {
        setState(() => _isOpeningDetail = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final appBar = AppBar(
      backgroundColor: const Color(0xFF172133),
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      title: const Text(
        '제휴 / 혜택',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 1,
          color: Color(0x33FFFFFF),
        ),
      ),
    );

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: appBar,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: appBar,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _buildCategoryFilter(),
            const SizedBox(height: 12),
            if (_filteredRestaurants.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('표시할 제휴 매장이 없어요.')),
              )
            else
              ..._filteredRestaurants
                  .map((restaurant) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: _buildRestaurantCard(restaurant),
                      ))
                  .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    if (_categories.isEmpty) {
      return const SizedBox.shrink();
    }
    const double scale = 1.125;
    return SizedBox(
      height: 90 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => SizedBox(width: 12 * scale),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          final meta = _resolveCategoryMeta(category);
          final textStyle = TextStyle(
            color: selected ? const Color(0xFF172133) : const Color(0xFF797979),
            fontSize: 12 * scale,
            fontFamily: 'Pretendard',
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            height: 1.92,
          );

          return InkWell(
            onTap: () => _selectCategory(category),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52 * scale,
              height: 66 * scale,
              decoration: ShapeDecoration(
                color: selected
                    ? const Color(0x99C7CDD1)
                    : const Color(0xFFF9FAFB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 6 * scale,
                vertical: 8 * scale,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Image.asset(
                      meta.assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    meta.label,
                    style: textStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRestaurantCard(AffiliateRestaurantSummary restaurant) {
    final couponCount = _couponCounts[restaurant.id] ?? 0;
    final hasImage = restaurant.imageUrls.isNotEmpty;
    final String? thumbnailUrl = hasImage ? restaurant.imageUrls.first : null;
    final stampStatus = _stampStatuses[restaurant.id];
    final stampCurrent =
        stampStatus != null ? stampStatus.current : restaurant.stampCurrent;
    final stampTarget =
        stampStatus != null ? stampStatus.target : restaurant.stampTarget;
    final couponLabel = _requiresLogin
        ? '로그인이 필요해요'
        : couponCount > 0
            ? '보유 쿠폰 $couponCount'
            : '보유 쿠폰 없음';
    String stampLabel;
    Color stampBackground = const Color(0xFFF5F3FF);
    Color stampTextColor = const Color(0xFF5B21B6);
    if (_requiresLogin) {
      stampLabel = '스탬프 확인은 로그인 필요';
      stampBackground = const Color(0xFFFFF1F2);
      stampTextColor = const Color(0xFFDC2626);
    } else if (stampTarget > 0) {
      stampLabel = '스탬프 ${stampCurrent}/${stampTarget}';
    } else if (stampCurrent > 0) {
      stampLabel = '스탬프 ${stampCurrent}개';
    } else {
      stampLabel = '스탬프 적립 없음';
      stampBackground = const Color(0xFFF3F4F6);
      stampTextColor = const Color(0xFF4B5563);
    }

    return InkWell(
      onTap: () => _openRestaurantDetail(restaurant),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: Container(
                color: const Color(0xFFE5E7EB),
                width: 108,
                height: 108,
                child: thumbnailUrl != null
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, event) {
                          if (event == null) return child;
                          final expected = event.expectedTotalBytes;
                          final loaded = event.cumulativeBytesLoaded;
                          final progress = expected != null && expected > 0
                              ? loaded / expected
                              : null;
                          return Center(
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF6366F1),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                          Icons.store_mall_directory_outlined,
                          size: 36,
                          color: Color(0xFF6B7280),
                        ),
                      )
                    : const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 36,
                        color: Color(0xFF6B7280),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name.isNotEmpty
                                ? restaurant.name
                                : '매장 정보를 찾을 수 없어요',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_right,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      restaurant.address.isNotEmpty
                          ? restaurant.address
                          : '주소 정보를 불러오지 못했어요.',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildTag(restaurant.category.isNotEmpty
                            ? restaurant.category
                            : '카테고리 정보 없음'),
                        if (restaurant.zone.isNotEmpty)
                          _buildTag(restaurant.zone),
                        _buildTag(couponLabel,
                            background: const Color(0xFFF3F4F6),
                            textColor: _requiresLogin
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF4B5563)),
                        _buildTag(
                          stampLabel,
                          background: stampBackground,
                          textColor: stampTextColor,
                        ),
                      ],
                    ),
                    if (restaurant.phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '전화: ${restaurant.phoneNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String label,
      {Color background = const Color(0xFFEEF2FF),
      Color textColor = const Color(0xFF312E81)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class AffiliateRestaurantDetailSheet extends StatefulWidget {
  const AffiliateRestaurantDetailSheet({
    super.key,
    required this.restaurant,
    required this.coupons,
    required this.requiresLogin,
    this.initialStampStatus,
    required this.onStampStatusUpdated,
    required this.onCouponRedeemed,
    required this.onRewardCouponsIssued,
  });

  final AffiliateRestaurantSummary restaurant;
  final List<UserCoupon> coupons;
  final bool requiresLogin;
  final StampStatus? initialStampStatus;
  final void Function(StampStatus status) onStampStatusUpdated;
  final void Function(String couponCode) onCouponRedeemed;
  final void Function(List<String> couponCodes) onRewardCouponsIssued;

  @override
  State<AffiliateRestaurantDetailSheet> createState() =>
      _AffiliateRestaurantDetailSheetState();
}

class _AffiliateRestaurantDetailSheetState
    extends State<AffiliateRestaurantDetailSheet> {
  late List<UserCoupon> _coupons;
  StampStatus? _stampStatus;
  bool _isStampLoading = true;
  bool _isStampProcessing = false;
  String? _stampError;
  String? _processingCouponCode;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _coupons = List<UserCoupon>.from(widget.coupons);
    _sortCoupons();
    _stampStatus = widget.initialStampStatus ??
        StampStatus(
          current: widget.restaurant.stampCurrent,
          target: widget.restaurant.stampTarget,
          updatedAt: null,
        );
    final hasInitialStatus = widget.initialStampStatus != null;
    if (!widget.requiresLogin && !hasInitialStatus) {
      _isStampLoading = true;
      _loadStampStatus(showLoading: true);
    } else {
      _isStampLoading = false;
      if (widget.requiresLogin) {
        _stampError = '로그인 후 스탬프 정보를 확인할 수 있어요.';
      }
    }
  }

  Future<void> _loadStampStatus({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isStampLoading = true;
        _stampError = null;
      });
    } else {
      setState(() {
        _stampError = null;
      });
    }
    try {
      final status = await _fetchStampStatusWithFallback();
      if (!mounted) return;
      setState(() {
        _stampStatus = status;
      });
      widget.onStampStatusUpdated(status);
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError = e.message;
      });
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError =
            _extractDetailMessage(e.body) ?? 'HTTP ${e.statusCode}: ${e.body}';
      });
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError = '네트워크 오류: ${e.cause}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isStampLoading = false);
      }
    }
  }

  Future<StampStatus> _fetchStampStatusWithFallback() async {
    try {
      final collection = await CouponService.fetchAllStampStatuses();
      return collection.statuses[widget.restaurant.id] ??
          _defaultStampStatusForRestaurant(
            widget.restaurant,
            fallbackTarget: collection.defaultTarget,
            preferZeroTarget: !collection.hasResults,
          );
    } on ApiAuthException {
      rethrow;
    } catch (_) {
      return CouponService.fetchStampStatus(
        restaurantId: widget.restaurant.id,
      );
    }
  }

  Future<void> _handleAddStamp() async {
    final pin = await _promptForPin(
      title: '스탬프 적립',
      confirmLabel: '적립하기',
    );
    if (pin == null) return;

    setState(() => _isStampProcessing = true);
    try {
      final result = await CouponService.addStamp(
        restaurantId: widget.restaurant.id,
        pin: pin,
      );
      if (!mounted) return;
      setState(() {
        _stampStatus = result.status;
      });
      widget.onStampStatusUpdated(result.status);
      _showSnack('스탬프를 적립했어요.');
      final rewardCodesSet = <String>{
        ...result.rewardCouponCodes.where((code) => code.isNotEmpty),
      };
      final reward = result.rewardCouponCode;
      if (reward != null && reward.isNotEmpty) {
        rewardCodesSet.add(reward);
      }
      final rewardCodes = rewardCodesSet.toList();
      if (rewardCodes.isNotEmpty) {
        final existingCodes = _coupons.map((coupon) => coupon.code).toSet();
        final newCodes =
            rewardCodes.where((code) => !existingCodes.contains(code)).toList();
        if (newCodes.isNotEmpty) {
          setState(() {
            _coupons = List<UserCoupon>.from(_coupons)
              ..addAll(
                newCodes.map(
                  (code) => UserCoupon(
                    code: code,
                    status: CouponStatus.issued,
                    restaurantId: widget.restaurant.id,
                  ),
                ),
              );
            _sortCoupons();
          });
          widget.onRewardCouponsIssued(newCodes);
        }
        final buffer = StringBuffer();
        if (newCodes.isNotEmpty) {
          buffer.write('새 리워드 쿠폰이 발급되었어요: ${newCodes.join(', ')}');
        } else {
          buffer.write('보유 중인 리워드 쿠폰을 다시 안내해드려요.');
        }
        buffer.write('\n현재 리워드 쿠폰: ${rewardCodes.join(', ')}');
        _showSnack(buffer.toString());
      }
    } on ApiAuthException catch (e) {
      _showSnack(e.message);
    } on ApiHttpException catch (e) {
      _showSnack(
          _extractDetailMessage(e.body) ?? '요청이 실패했어요 (HTTP ${e.statusCode})');
    } on ApiNetworkException catch (e) {
      _showSnack('네트워크 오류: ${e.cause}');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isStampProcessing = false);
      }
    }
  }

  Future<void> _handleRedeem(UserCoupon coupon) async {
    final pin = await _promptForPin(
      title: '쿠폰 사용',
      confirmLabel: '사용하기',
    );
    if (pin == null) return;

    setState(() => _processingCouponCode = coupon.code);
    try {
      await CouponService.redeemCoupon(
        couponCode: coupon.code,
        restaurantId: widget.restaurant.id,
        pin: pin,
      );
      if (!mounted) return;
      setState(() {
        _coupons = _coupons.where((item) => item.code != coupon.code).toList();
      });
      widget.onCouponRedeemed(coupon.code);
      _showSnack('쿠폰을 사용했어요.');
    } on ApiAuthException catch (e) {
      _showSnack(e.message);
    } on ApiHttpException catch (e) {
      _showSnack(
          _extractDetailMessage(e.body) ?? '요청이 실패했어요 (HTTP ${e.statusCode})');
    } on ApiNetworkException catch (e) {
      _showSnack('네트워크 오류: ${e.cause}');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _processingCouponCode = null);
      }
    }
  }

  Future<String?> _promptForPin({
    required String title,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: InputDecoration(
                      labelText: 'PIN (4자리)',
                      counterText: '',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '제휴 매장 관리자가 제공한 4자리 PIN을 입력해 주세요.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.length != 4) {
                      setState(() {
                        error = 'PIN은 4자리 숫자여야 합니다.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSnack(String message) {
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectTab(int index) {
    if (_selectedTabIndex == index) return;
    setState(() => _selectedTabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = widget.restaurant;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  restaurant.name.isNotEmpty
                      ? restaurant.name
                      : '매장 정보를 찾을 수 없어요',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 20),
                _buildTabSwitcher(),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectedTabIndex == 0
                      ? _buildBenefitsTab()
                      : _buildStoreInfoTab(restaurant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    const labels = ['혜택', '매장 정보'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE7E9F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = _selectedTabIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectTab(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0B1033).withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: selected
                          ? const Color(0xFF111439)
                          : const Color(0xFF6B6F94),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBenefitsTab() {
    return Column(
      key: const ValueKey('benefits'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStampSection(),
        const SizedBox(height: 24),
        _buildCouponSection(),
      ],
    );
  }

  Widget _buildStoreInfoTab(AffiliateRestaurantSummary restaurant) {
    return Column(
      key: const ValueKey('info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageCarousel(restaurant.imageUrls),
        const SizedBox(height: 24),
        const Text(
          '기본 정보',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoRow(
          '주소',
          restaurant.address.isNotEmpty
              ? restaurant.address
              : '주소 정보를 불러오지 못했어요.',
        ),
        const SizedBox(height: 12),
        _buildInfoRow(
          '전화번호',
          restaurant.phoneNumber.isNotEmpty
              ? restaurant.phoneNumber
              : '전화번호 정보가 없어요.',
        ),
        if (restaurant.category.isNotEmpty || restaurant.zone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (restaurant.category.isNotEmpty)
                  _buildInfoChip(restaurant.category),
                if (restaurant.zone.isNotEmpty) _buildInfoChip(restaurant.zone),
              ],
            ),
          ),
        if (restaurant.url != null && restaurant.url!.isNotEmpty) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _openRestaurantPage,
            icon: const Icon(Icons.open_in_new),
            label: const Text('매장 페이지 열기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF111439),
              side: const BorderSide(color: Color(0xFFE0E3FF)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStampSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1033), Color(0xFF1C2470)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.card_giftcard,
                  color: Color(0xFFFFB800),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '스탬프 혜택',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '스탬프 갱신',
                onPressed: _isStampLoading || widget.requiresLogin
                    ? null
                    : _loadStampStatus,
                icon: const Icon(Icons.refresh),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.requiresLogin)
            const Text(
              '로그인 후 스탬프를 적립할 수 있어요.',
              style: TextStyle(color: Colors.white70),
            )
          else if (_isStampLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            )
          else ...[
            _buildStampProgress(),
            const SizedBox(height: 16),
            _buildRewardMessage(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.requiresLogin || _isStampProcessing
                    ? null
                    : _handleAddStamp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B1033),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _isStampProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0B1033),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('적립 중...'),
                        ],
                      )
                    : const Text('스탬프 적립하기'),
              ),
            ),
          ],
          if (_stampError != null) ...[
            const SizedBox(height: 12),
            Text(
              _stampError!,
              style: const TextStyle(
                color: Color(0xFFFFA5A5),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStampProgress() {
    final status = _stampStatus;
    if (status == null) {
      return const Text(
        '스탬프 정보를 불러오지 못했어요.',
        style: TextStyle(color: Colors.white70),
      );
    }
    final rewardThresholds = status.rewardCoupons
        .map((reward) => reward.threshold)
        .where((threshold) => threshold > 0)
        .toSet()
        .toList()
      ..sort();
    final total = math.max(
      status.target,
      rewardThresholds.isNotEmpty ? rewardThresholds.last : 10,
    );
    final filled = math.min(status.current, total);
    final milestoneSet =
        rewardThresholds.isNotEmpty ? rewardThresholds.toSet() : <int>{5, 10};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '현재 진행도',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(total, (index) {
            final isFilled = index < filled;
            final isMilestone = milestoneSet.contains(index + 1);
            return _buildStampIcon(
              filled: isFilled,
              showMilestoneGlow: isMilestone && isFilled,
            );
          }),
        ),
        const SizedBox(height: 16),
        Text(
          '${status.current} / $total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (status.updatedAt != null) ...[
          const SizedBox(height: 6),
          Text(
            '업데이트: ${_formatDate(status.updatedAt!)}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
            ),
          ),
        ],
      ],
    );
  }

  void _sortCoupons() {
    _coupons.sort((a, b) {
      int priority(CouponStatus status) {
        switch (status) {
          case CouponStatus.issued:
            return 0;
          case CouponStatus.redeemed:
            return 1;
          case CouponStatus.expired:
            return 2;
          case CouponStatus.canceled:
            return 3;
          case CouponStatus.unknown:
            return 4;
        }
      }

      final diff = priority(a.status) - priority(b.status);
      if (diff != 0) return diff;
      return a.code.compareTo(b.code);
    });
  }

  Widget _buildRewardMessage() {
    final status = _stampStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }
    final rewards = status.rewardCoupons.toList()
      ..sort((a, b) => a.threshold.compareTo(b.threshold));

    final List<Widget> items = [];
    final reachedRewards =
        rewards.where((reward) => status.current >= reward.threshold).toList();
    final pendingRewards =
        rewards.where((reward) => status.current < reward.threshold).toList();
    final thresholds = rewards.map((reward) => reward.threshold).toSet();

    for (final reward in reachedRewards) {
      final label = _rewardCouponLabel(reward);
      final code = reward.couponCode.trim();
      final buffer = StringBuffer('$label을 이미 받았어요.');
      if (code.isNotEmpty) {
        buffer.write(' (코드: $code)');
      }
      items.add(
        Text(
          buffer.toString(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    String? nextMessage;
    if (status.current < 5 &&
        (thresholds.contains(5) || rewards.isEmpty || status.target <= 5)) {
      nextMessage = '스탬프 5개까지 적립하면 첫 번째 리워드 쿠폰을 받을 수 있어요.';
    } else if (status.current < 10 &&
        (thresholds.contains(10) || rewards.isEmpty || status.target <= 10)) {
      nextMessage = '스탬프 10개까지 적립하면 두 번째 리워드 쿠폰을 받을 수 있어요.';
    } else if (pendingRewards.isNotEmpty) {
      final reward = pendingRewards.first;
      final remaining = math.max(reward.threshold - status.current, 0);
      nextMessage =
          _pendingRewardMessage(reward.threshold, status.current, remaining);
    }

    if (nextMessage == null) {
      final remainingToTarget = math.max(status.target - status.current, 0);
      if (remainingToTarget > 0) {
        nextMessage = '스탬프 ${remainingToTarget}개 더 적립하면 리워드 쿠폰을 받을 수 있어요.';
      }
    }

    if (nextMessage != null) {
      items.add(
        Text(
          nextMessage,
          style: const TextStyle(
            color: Color(0xFF9FA7FF),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        const Text(
          '준비된 리워드 쿠폰을 모두 받았어요!',
          style: TextStyle(
            color: Color(0xFF9FA7FF),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          items[i],
        ],
      ],
    );
  }

  String _rewardCouponLabel(StampRewardCoupon reward) {
    final type = reward.couponType.trim();
    if (type.isNotEmpty) {
      const prefix = 'STAMP_REWARD_';
      final upper = type.toUpperCase();
      if (upper.startsWith(prefix)) {
        final suffix = type.substring(prefix.length);
        final numeric = int.tryParse(suffix);
        if (numeric != null) {
          return '스탬프 ${numeric}개 리워드 쿠폰';
        }
        final readableSuffix = suffix.replaceAll('_', ' ');
        return '스탬프 ${reward.threshold}개 리워드 쿠폰 (${readableSuffix.isNotEmpty ? readableSuffix : suffix})';
      }
      final readable = type.replaceAll('_', ' ');
      return '스탬프 ${reward.threshold}개 리워드 쿠폰 (${readable.isNotEmpty ? readable : type})';
    }
    return '스탬프 ${reward.threshold}개 리워드 쿠폰';
  }

  String _pendingRewardMessage(int threshold, int current, int remaining) {
    if (threshold == 5 && current < 5) {
      return '스탬프 5개까지 적립하면 첫 번째 리워드 쿠폰을 받을 수 있어요.';
    }
    if (threshold == 10 && current >= 5 && current < 10) {
      return '스탬프 10개까지 적립하면 두 번째 리워드 쿠폰을 받을 수 있어요.';
    }
    final milestoneName = _milestoneLabel(threshold);
    final prefix = remaining <= 0 ? '이제' : '스탬프 ${remaining}개 더 적립하면';
    return '$prefix $milestoneName을 받을 수 있어요.';
  }

  String _milestoneLabel(int threshold) {
    switch (threshold) {
      case 5:
        return '첫 번째 리워드 쿠폰';
      case 10:
        return '두 번째 리워드 쿠폰';
      default:
        return '스탬프 ${threshold}개 리워드 쿠폰';
    }
  }

  Widget _buildStampIcon(
      {required bool filled, required bool showMilestoneGlow}) {
    final decoration = BoxDecoration(
      color: filled ? Colors.white : Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: filled ? Colors.white : Colors.white.withOpacity(0.18),
        width: 1.2,
      ),
      boxShadow: showMilestoneGlow
          ? [
              BoxShadow(
                color: const Color(0xFF8B92FF).withOpacity(0.45),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ]
          : null,
    );

    return Container(
      width: 44,
      height: 44,
      decoration: decoration,
      alignment: Alignment.center,
      child: filled
          ? Image.asset(
              'assets/images/would_logo.png',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.check_circle,
                color: Color(0xFF0B1033),
              ),
            )
          : Icon(
              Icons.circle_outlined,
              color: Colors.white.withOpacity(0.35),
              size: 16,
            ),
    );
  }

  Widget _buildCouponSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E3FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '보유 쿠폰',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.requiresLogin)
            const Text(
              '로그인하면 제휴 쿠폰을 확인할 수 있어요.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else if (_coupons.isEmpty)
            const Text(
              '사용 가능한 쿠폰이 없어요.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else
            Column(
              children:
                  _coupons.map((coupon) => _buildCouponTile(coupon)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCouponTile(UserCoupon coupon) {
    final isProcessing = _processingCouponCode == coupon.code;
    final benefit = coupon.benefit;
    final title = benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle;
    final subtitle =
        benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle;
    final String restaurantLabel = benefit?.restaurantNameText ??
        (coupon.restaurantId != null
            ? '사용 가능 매장 ID: ${coupon.restaurantId}'
            : '사용 가능한 매장 정보가 없어요.');
    final statusText = _couponStatusLabel(coupon.status);
    final statusColor = _couponStatusColor(coupon.status);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E3FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        restaurantLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4B5563),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4C5395),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isProcessing || widget.requiresLogin
                ? null
                : () => _handleRedeem(coupon),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B1033),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('사용'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCarousel(List<String> imageUrls) {
    if (imageUrls.isEmpty) {
      return Container(
        height: 132,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Center(
          child: Text(
            '등록된 사진이 없어요.',
            style: TextStyle(color: Color(0xFF9CA3AF)),
          ),
        ),
      );
    }

    final items = imageUrls.take(4).toList();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final url = items[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 132,
              color: const Color(0xFFE5E7EB),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF4B5563),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openRestaurantPage() async {
    final url = widget.restaurant.url;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('유효한 링크가 아니에요.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('링크를 열 수 없어요.');
    }
  }

  String _couponStatusLabel(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return '사용 가능';
      case CouponStatus.redeemed:
        return '사용됨';
      case CouponStatus.expired:
        return '만료됨';
      case CouponStatus.canceled:
        return '취소됨';
      case CouponStatus.unknown:
        return '상태 확인 불가';
    }
  }

  Color _couponStatusColor(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return const Color(0xFF10B981);
      case CouponStatus.redeemed:
        return const Color(0xFF6366F1);
      case CouponStatus.expired:
        return const Color(0xFFF97316);
      case CouponStatus.canceled:
        return const Color(0xFFEF4444);
      case CouponStatus.unknown:
        return const Color(0xFF6B7280);
    }
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String? _extractDetailMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        const keys = ['detail', 'message', 'error'];
        for (final key in keys) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) {
            return value;
          }
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) {
              return first;
            }
          }
        }
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is String && value.isNotEmpty) {
            return value;
          }
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) {
              return first;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
