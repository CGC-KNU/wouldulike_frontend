import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

class _CouponCounts {
  final int issued;
  final int redeemed;

  const _CouponCounts({required this.issued, required this.redeemed});

  int get total => issued + redeemed;
}

class _AffiliateBenefitsScreenState extends State<AffiliateBenefitsScreen> {
  List<AffiliateRestaurantSummary> _restaurants = [];
  List<UserCoupon> _issuedCoupons = [];
  Map<int, int> _couponCounts = {};
  Map<int, _CouponCounts> _couponCountsDetailed = {};
  Map<int, StampStatus> _stampStatuses = {};
  bool _isLoading = false;
  String? _error;
  bool _requiresLogin = false;
  String _selectedCategory = 'ALL';
  List<String> _categories = const ['ALL'];

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
      final allCoupons = await _fetchAllCoupons();

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
        _couponCountsDetailed = _buildDetailedCouponCounts(allCoupons);
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

  Future<List<UserCoupon>> _fetchAllCoupons() async {
    try {
      final coupons = await CouponService.fetchMyCoupons();
      return coupons;
    } catch (e) {
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

  Map<int, _CouponCounts> _buildDetailedCouponCounts(List<UserCoupon> coupons) {
    final counts = <int, _CouponCounts>{};
    for (final coupon in coupons) {
      final restaurantId = coupon.restaurantId;
      if (restaurantId == null) continue;
      
      final current = counts[restaurantId] ?? const _CouponCounts(issued: 0, redeemed: 0);
      if (coupon.status == CouponStatus.issued) {
        counts[restaurantId] = _CouponCounts(
          issued: current.issued + 1,
          redeemed: current.redeemed,
        );
      } else if (coupon.status == CouponStatus.redeemed) {
        counts[restaurantId] = _CouponCounts(
          issued: current.issued,
          redeemed: current.redeemed + 1,
        );
      }
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
      // Update detailed coupon counts: move one from issued to redeemed
      final currentDetailed = _couponCountsDetailed[restaurantId];
      if (currentDetailed != null && currentDetailed.issued > 0) {
        _couponCountsDetailed[restaurantId] = _CouponCounts(
          issued: currentDetailed.issued - 1,
          redeemed: currentDetailed.redeemed + 1,
        );
      } else if (currentDetailed == null) {
        _couponCountsDetailed[restaurantId] = const _CouponCounts(
          issued: 0,
          redeemed: 1,
        );
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
      // Update detailed coupon counts: add new issued coupons
      final currentDetailed = _couponCountsDetailed[restaurantId];
      if (currentDetailed != null) {
        _couponCountsDetailed[restaurantId] = _CouponCounts(
          issued: currentDetailed.issued + newCoupons.length,
          redeemed: currentDetailed.redeemed,
        );
      } else {
        _couponCountsDetailed[restaurantId] = _CouponCounts(
          issued: newCoupons.length,
          redeemed: 0,
        );
      }
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
    final couponCounts = _couponCountsDetailed[restaurant.id];
    final hasImage = restaurant.imageUrls.isNotEmpty;
    final String? thumbnailUrl = hasImage ? restaurant.imageUrls.first : null;
    final stampStatus = _stampStatuses[restaurant.id];
    final stampCurrent =
        stampStatus != null ? stampStatus.current : restaurant.stampCurrent;
    final stampTarget =
        stampStatus != null ? stampStatus.target : restaurant.stampTarget;
    
    String stampLabel;
    if (_requiresLogin) {
      stampLabel = '스탬프 확인은 로그인 필요';
    } else if (stampTarget > 0) {
      stampLabel = '스탬프 ${stampCurrent}/${stampTarget}';
    } else if (stampCurrent > 0) {
      stampLabel = '스탬프 ${stampCurrent}개';
    } else {
      stampLabel = '스탬프 적립 없음';
    }

    return InkWell(
      onTap: () => _openRestaurantDetail(restaurant),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 372,
        height: 142.48,
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(
              width: 1,
              color: Color(0xFFDDDDDD),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
              child: Container(
                color: const Color(0xFFE5E7EB),
                width: 108,
                height: 142.48,
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStampTag(stampLabel, _requiresLogin),
                        const SizedBox(height: 4),
                        _buildCouponTag(couponCounts),
                      ],
                    ),
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

  Widget _buildCouponTag(_CouponCounts? couponCounts) {
    String couponText;
    if (_requiresLogin) {
      couponText = '로그인이 필요해요';
    } else if (couponCounts == null || couponCounts.total == 0) {
      couponText = '보유 쿠폰 없음';
    } else {
      final issued = couponCounts.issued;
      final total = couponCounts.total;
      couponText = '사용 가능 쿠폰 $issued/$total';
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: ShapeDecoration(
        color: const Color(0xFFEEF4FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/coupon_status.png',
            width: 12,
            height: 12,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 4),
          Text(
            couponText,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStampTag(String stampLabel, bool requiresLogin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: ShapeDecoration(
        color: const Color(0xFFFFF8E1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/images/medal.svg',
            width: 12,
            height: 12,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 4),
          Text(
            stampLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: requiresLogin
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF1F2937),
            ),
          ),
        ],
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
  static const Map<String, Map<int, String>> _kStampBenefitMessages = {
    '정든밤': {
      5: '감자튀김 서비스',
      10: '메인메뉴 택 1',
    },
    '깨꼬닭': {
      5: '닭껍질 튀김',
      10: '후라이드 똥집',
    },
    '깨꼬닭 본점': {
      5: '닭껍질 튀김',
      10: '후라이드 똥집',
    },
    '한끼갈비': {
      5: '납작만두',
      10: '납작만두',
    },
    '고니식탁': {
      5: '계란말이 서비스',
      10: '찌개 1인분 서비스',
    },
    '테이크어바이트': {
      5: '음료 또는 5% 할인 쿠폰',
      10: '파스타 중 1개 무료',
    },
    '스톡홀롬샐러드정문점': {
      5: '아메리카노 교환권',
      10: '샐러드 50% 할인(최대 5,000원)',
    },
    '스톡홀름샐러드 정문점': {
      5: '아메리카노 교환권',
      10: '샐러드 50% 할인(최대 5,000원)',
    },
    '마름모식당': {
      5: '미니우동 또는 미니 냉우동',
      10: '들기름우동 서비스',
    },
    '벨로': {
      5: '현금 결제 시 20% 할인 쿠폰',
      10: '현금 결제 시 20% 할인 쿠폰',
    },
    '팀스쿠치나': {
      5: '안티파스토 샐러드 서비스',
      10: '새우 오로라 크림파스타 또는 트러플 새우 카펠리니',
    },
    '팀스 쿠치나': {
      5: '안티파스토 샐러드 서비스',
      10: '새우 오로라 크림파스타 또는 트러플 새우 카펠리니',
    },
    '대부': {
      5: '교자만두 서비스',
      10: '새우튀김 샐러드 서비스',
    },
    '대부 대왕유부초밥 경대점': {
      5: '교자만두 서비스',
      10: '새우튀김 샐러드 서비스',
    },
    '부리또': {
      5: '치즈스틱 서비스',
      10: '치킨부리또 1개 서비스',
    },
    '부리또익스프레스': {
      5: '치즈스틱 서비스',
      10: '치킨부리또 1개 서비스',
    },
    '다이와스시': {
      5: '타코야끼 10개 서비스',
      10: '모듬초밥 5pcs 서비스',
    },
    '라보': {
      5: '탕수육 M 서비스',
      10: '탕수육 L 서비스',
    },
  };

  late List<UserCoupon> _coupons;
  StampStatus? _stampStatus;
  bool _isStampLoading = true;
  bool _isStampProcessing = false;
  String? _stampError;
  String? _processingCouponCode;
  int _selectedTabIndex = 0;

  String? _stampBenefitFor(int threshold) {
    final restaurantName = widget.restaurant.name.trim();
    if (restaurantName.isEmpty) return null;
    final benefits = _kStampBenefitMessages[restaurantName];
    return benefits?[threshold];
  }

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

    return Container(
      color: Colors.white,
      child: SafeArea(
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

    // 5x2 그리드로 스탬프 배치
    final rows = <List<int>>[];
    for (int i = 0; i < total; i += 5) {
      final row = <int>[];
      for (int j = i; j < math.min(i + 5, total); j++) {
        row.add(j);
      }
      rows.add(row);
    }

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
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 5;
            const stampSpacing = 6.0;
            const rowSpacing = 8.0;
            final stampSize =
                (constraints.maxWidth - stampSpacing * (columns - 1)) /
                    columns;

            return Column(
              children: rows.asMap().entries.map((entry) {
                final rowIndex = entry.key;
                final row = entry.value;
                final isLastRow = rowIndex == rows.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLastRow ? 0 : rowSpacing),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: row.asMap().entries.map((colEntry) {
                      final colIndex = colEntry.key;
                      final stampIndex = colEntry.value;
                      final isLastCol = colIndex == row.length - 1;
                      final isFilled = stampIndex < filled;
                      final isMilestone = milestoneSet.contains(stampIndex + 1);
                      return Padding(
                        padding: EdgeInsets.only(
                          right: isLastCol ? 0 : stampSpacing,
                        ),
                        child: _buildStampIcon(
                          filled: isFilled,
                          showMilestoneGlow: isMilestone && isFilled,
                          size: stampSize,
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            );
          },
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

    const baseStyle = TextStyle(
      color: Colors.white70,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    const upcomingStyle = TextStyle(
      color: Color(0xFF9FA7FF),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    const highlightColor = Color(0xFFFFB800);
    final highlightStyle = baseStyle.copyWith(
      color: highlightColor,
      fontWeight: FontWeight.w700,
    );

    RichText buildRichText(List<TextSpan> spans, TextStyle style) {
      return RichText(
        text: TextSpan(
          style: style,
          children: spans,
        ),
      );
    }

    Widget buildUpcomingMessage(int threshold, String benefit) {
      return buildRichText([
        const TextSpan(text: '스탬프 '),
        TextSpan(text: '${threshold}개', style: highlightStyle),
        const TextSpan(text: '까지 적립하면 '),
        TextSpan(text: benefit, style: highlightStyle),
        const TextSpan(text: ' 혜택을 받을 수 있어요.'),
      ], upcomingStyle);
    }

    Widget buildReachedMessage(String benefit) {
      return buildRichText([
        TextSpan(text: benefit, style: highlightStyle),
        const TextSpan(text: ' 혜택을 이미 받았어요.'),
      ], baseStyle);
    }

    for (final reward in reachedRewards) {
      final benefit = _stampBenefitFor(reward.threshold);
      if (benefit != null) {
        items.add(buildReachedMessage(benefit));
      } else {
        final label = _rewardCouponLabel(reward);
        final code = reward.couponCode.trim();
        final buffer = StringBuffer('$label을 이미 받았어요.');
        if (code.isNotEmpty) {
          buffer.write(' (코드: $code)');
        }
        items.add(
          Text(
            buffer.toString(),
            style: baseStyle,
          ),
        );
      }
    }

    Widget? nextMessageWidget;
    if (status.current < 5 &&
        (thresholds.contains(5) || rewards.isEmpty || status.target <= 5)) {
      final benefit = _stampBenefitFor(5);
      nextMessageWidget = benefit != null
          ? buildUpcomingMessage(5, benefit)
          : Text(
              '스탬프 5개까지 적립하면 첫 번째 리워드 쿠폰을 받을 수 있어요.',
              style: upcomingStyle,
            );
    } else if (status.current < 10 &&
        (thresholds.contains(10) || rewards.isEmpty || status.target <= 10)) {
      final benefit = _stampBenefitFor(10);
      nextMessageWidget = benefit != null
          ? buildUpcomingMessage(10, benefit)
          : Text(
              '스탬프 10개까지 적립하면 두 번째 리워드 쿠폰을 받을 수 있어요.',
              style: upcomingStyle,
            );
    } else if (pendingRewards.isNotEmpty) {
      final reward = pendingRewards.first;
      final benefit = _stampBenefitFor(reward.threshold);
      if (benefit != null) {
        final remaining = math.max(reward.threshold - status.current, 0);
        final prefix = remaining <= 0
            ? '이제 '
            : '스탬프 ${remaining}개 더 적립하면 ';
        nextMessageWidget = buildRichText([
          TextSpan(text: prefix),
          TextSpan(text: benefit, style: highlightStyle),
          const TextSpan(text: ' 혜택을 받을 수 있어요.'),
        ], upcomingStyle);
      } else {
        final remaining = math.max(reward.threshold - status.current, 0);
        final text = _pendingRewardMessage(
          reward.threshold,
          status.current,
          remaining,
        );
        nextMessageWidget = Text(
          text,
          style: upcomingStyle,
        );
      }
    }

    if (nextMessageWidget == null) {
      final remainingToTarget = math.max(status.target - status.current, 0);
      if (remainingToTarget > 0) {
        final benefit = _stampBenefitFor(status.target);
        if (benefit != null) {
          nextMessageWidget = buildUpcomingMessage(status.target, benefit);
        } else {
          nextMessageWidget = Text(
            '스탬프 ${remainingToTarget}개 더 적립하면 리워드 쿠폰을 받을 수 있어요.',
            style: upcomingStyle,
          );
        }
      }
    }

    if (nextMessageWidget != null) {
      items.add(nextMessageWidget);
    }

    if (items.isEmpty) {
      items.add(
        const Text(
          '준비된 리워드 혜택을 모두 받았어요!',
          style: upcomingStyle,
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
    final benefit = _stampBenefitFor(threshold);
    if (benefit != null) {
      final prefix = remaining <= 0 ? '이제' : '스탬프 ${remaining}개 더 적립하면';
      return '$prefix $benefit 혜택을 받을 수 있어요.';
    }
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

  Widget _buildStampIcon({
    required bool filled,
    required bool showMilestoneGlow,
    double size = 50,
  }) {
    final decoration = ShapeDecoration(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: filled ? const Color(0xFF0B1033) : const Color(0xFFCBD5F5),
          width: 1.4,
        ),
      ),
      shadows: showMilestoneGlow
          ? [
              BoxShadow(
                color: const Color(0xFF8B92FF).withOpacity(0.45),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ]
          : null,
    );

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: filled
          ? ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.asset(
                'assets/images/would_logo.png',
                width: size * 0.72,
                height: size * 0.72,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.restaurant,
                  color: const Color(0xFF0B1033),
                  size: size * 0.6,
                ),
              ),
            )
          : const SizedBox.shrink(),
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
    final statusText = _couponStatusLabel(coupon.status);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1033), Color(0xFF1C2470)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCouponStatusBadge(coupon.status, statusText),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFD1D6FF),
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
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0B1033),
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
                      color: Color(0xFF0B1033),
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

  Widget _buildCouponStatusBadge(CouponStatus status, String text) {
    Color background;
    Color foreground;
    switch (status) {
      case CouponStatus.issued:
        background = const Color(0xFFCAE4FF);
        foreground = const Color(0xFF0B4E8A);
        break;
      case CouponStatus.redeemed:
        background = const Color(0xFFFFD5E6);
        foreground = const Color(0xFF8A1D4F);
        break;
      default:
        background = Colors.white.withOpacity(0.15);
        foreground = Colors.white;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
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
