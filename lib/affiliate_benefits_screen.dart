import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';

import 'services/affiliate_service.dart';
import 'services/api_client.dart';
import 'services/coupon_service.dart';

bool _isValidNetworkImageUrl(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

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
  'CAFE': _CategoryMeta('카페', 'assets/images/cafe.png'),
  'DONKATSU': _CategoryMeta('돈가스', 'assets/images/donkatsu.png'),
  'HAMBURGER': _CategoryMeta('햄버거', 'assets/images/hamburger.png'),
  'ETC': _CategoryMeta('기타', 'assets/images/total.png'),
};

const Map<String, String> _kCategoryAlias = {
  'ALL': 'ALL',
  '전체': 'ALL',
  'KOREAN': 'KOREAN',
  '한식': 'KOREAN',
  '고기/구이': 'KOREAN',
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
  'CAFE': 'CAFE',
  '카페': 'CAFE',
  'DONKATSU': 'DONKATSU',
  '돈가스': 'DONKATSU',
  'HAMBURGER': 'HAMBURGER',
  '햄버거': 'HAMBURGER',
  'ETC': 'ETC',
  '기타': 'ETC',
  '아시안': 'ETC',
};

const List<String> _kCategoryOrder = [
  'ALL',
  'KOREAN',
  'CHINESE',
  'JAPANESE',
  'WESTERN',
  'SNACK',
  'PUB',
  'CAFE',
  'DONKATSU',
  'HAMBURGER',
  'ETC',
];

class _CouponCounts {
  final int issued;
  final int redeemed;

  const _CouponCounts({required this.issued, required this.redeemed});

  int get total => issued + redeemed;
}

class _AffiliateBenefitsScreenState extends State<AffiliateBenefitsScreen> {
  static const String _kFavoriteAffiliateRestaurantIdsKey =
      'affiliate_favorite_restaurant_ids';
  static const String _kFavoriteGeneralRestaurantKeysKey =
      'general_favorite_restaurant_keys';
  static const String _kFavoriteGeneralRestaurantItemsKey =
      'general_favorite_restaurant_items';
  static const int _kGeneralRestaurantPageSize = 20;

  List<AffiliateRestaurantSummary> _affiliateRestaurants = [];
  List<GeneralRestaurantSummary> _generalRestaurants = [];
  List<UserCoupon> _issuedCoupons = [];
  Map<int, int> _couponCounts = {};
  Map<int, _CouponCounts> _couponCountsDetailed = {};
  Map<int, StampStatus> _stampStatuses = {};
  bool _isLoading = false;
  bool _isAppending = false;
  bool _hasMoreGeneralRestaurants = false;
  int? _nextGeneralOffset;
  String? _error;
  bool _requiresLogin = false;
  String _selectedCategory = 'ALL';
  List<String> _categories = const ['ALL'];
  bool _isOpeningDetail = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  Set<int> _favoriteAffiliateRestaurantIds = <int>{};
  Set<String> _favoriteGeneralRestaurantKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _searchFocusNode.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final favoriteState = await _loadFavoriteState();
      final response = await AffiliateService.fetchTabRestaurants(
        query: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        limit: _kGeneralRestaurantPageSize,
        offset: 0,
        includeAffiliates: true,
      );
      final affiliateRestaurants = response.affiliateRestaurants;
      final generalRestaurants = response.generalRestaurants;
      final issuedCoupons = await _fetchIssuedCoupons();
      final allCoupons = await _fetchAllCoupons();

      final categories = <String>{'ALL'};
      for (final restaurant in affiliateRestaurants) {
        final normalizedCategory = _normalizedCategoryForState(
          restaurant.category,
        );
        if (normalizedCategory.isNotEmpty) {
          categories.add(normalizedCategory);
        }
      }
      for (final restaurant in generalRestaurants) {
        final normalizedCategory = _normalizedCategoryForState(
          restaurant.category,
        );
        if (normalizedCategory.isNotEmpty) {
          categories.add(normalizedCategory);
        }
      }

      if (!mounted) return;
      setState(() {
        final shuffledAffiliate = List<AffiliateRestaurantSummary>.from(affiliateRestaurants);
        shuffledAffiliate.shuffle(math.Random());
        final shuffledGeneral = List<GeneralRestaurantSummary>.from(generalRestaurants);
        shuffledGeneral.shuffle(math.Random());
        _affiliateRestaurants = shuffledAffiliate;
        _generalRestaurants = shuffledGeneral;
        _issuedCoupons = _sortCouponsByStatus(issuedCoupons);
        _couponCounts = _buildCouponCounts(issuedCoupons);
        _couponCountsDetailed = _buildDetailedCouponCounts(allCoupons);
        _stampStatuses = {};
        _categories = _sortCategories(categories);
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = 'ALL';
        }
        _favoriteAffiliateRestaurantIds = favoriteState.$1;
        _favoriteGeneralRestaurantKeys = favoriteState.$2;
        _hasMoreGeneralRestaurants = response.generalPagination.hasMore;
        _nextGeneralOffset = response.generalPagination.nextOffset;
      });

      if (_requiresLogin || !mounted) return;

      try {
        final statuses = await _fetchStampStatuses(affiliateRestaurants);
        if (!mounted) return;
        setState(() {
          _stampStatuses = statuses;
          _affiliateRestaurants =
              _applyStampStatuses(_affiliateRestaurants, statuses);
        });
      } on ApiAuthException catch (e) {
        if (!mounted) return;
        setState(() {
          _requiresLogin = true;
          _stampStatuses = {};
        });
        _showSnack(e.message);
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
        setState(() {
          _isLoading = false;
          _isAppending = false;
        });
      }
    }
  }

  Future<(Set<int>, Set<String>)> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final rawAffiliate =
        prefs.getStringList(_kFavoriteAffiliateRestaurantIdsKey) ??
            const <String>[];
    final rawGeneral =
        prefs.getStringList(_kFavoriteGeneralRestaurantKeysKey) ??
            const <String>[];
    final affiliateIds = rawAffiliate
        .map((value) => int.tryParse(value))
        .whereType<int>()
        .toSet();
    final generalKeys = rawGeneral
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    return (affiliateIds, generalKeys);
  }

  Future<void> _persistFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final affiliateValues =
        _favoriteAffiliateRestaurantIds.map((id) => id.toString()).toList();
    final generalValues = _favoriteGeneralRestaurantKeys.toList();
    await prefs.setStringList(
        _kFavoriteAffiliateRestaurantIdsKey, affiliateValues);
    await prefs.setStringList(
        _kFavoriteGeneralRestaurantKeysKey, generalValues);
  }

  bool _isFavoriteAffiliateRestaurant(int restaurantId) {
    return _favoriteAffiliateRestaurantIds.contains(restaurantId);
  }

  String _generalRestaurantFavoriteKey(GeneralRestaurantSummary restaurant) {
    if (restaurant.id > 0) {
      return 'id:${restaurant.id}';
    }
    final normalizedUrl = restaurant.url.trim();
    if (normalizedUrl.isNotEmpty) {
      return 'url:$normalizedUrl';
    }
    return 'name:${restaurant.name.trim()}|addr:${restaurant.address.trim()}';
  }

  bool _isFavoriteGeneralRestaurant(GeneralRestaurantSummary restaurant) {
    return _favoriteGeneralRestaurantKeys
        .contains(_generalRestaurantFavoriteKey(restaurant));
  }

  Future<void> _setFavoriteAffiliateRestaurant(
    int restaurantId,
    bool isFavorite,
  ) async {
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
    setState(() {
      final next = Set<int>.from(_favoriteAffiliateRestaurantIds);
      if (isFavorite) {
        next.add(restaurantId);
      } else {
        next.remove(restaurantId);
      }
      _favoriteAffiliateRestaurantIds = next;
    });
    await _persistFavoriteState();
  }

  Future<void> _setFavoriteGeneralRestaurant(
    GeneralRestaurantSummary restaurant,
    bool isFavorite,
  ) async {
    final key = _generalRestaurantFavoriteKey(restaurant);
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantFavoriteToggle,
      parameters: {
        AnalyticsEvents.paramRestaurantId: restaurant.id,
        AnalyticsEvents.paramRestaurantName: restaurant.name,
        AnalyticsEvents.paramAction: isFavorite ? 'add' : 'remove',
      },
    );
    if (!mounted) return;
    setState(() {
      final next = Set<String>.from(_favoriteGeneralRestaurantKeys);
      if (isFavorite) {
        next.add(key);
      } else {
        next.remove(key);
      }
      _favoriteGeneralRestaurantKeys = next;
    });
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFavoriteGeneralRestaurantItemsKey);
    final snapshots = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          snapshots.addAll(decoded);
        }
      } catch (_) {}
    }
    if (isFavorite) {
      snapshots[key] = <String, dynamic>{
        'restaurant_id': restaurant.id,
        'name': restaurant.name,
        'description': restaurant.description,
        'address': restaurant.address,
        'category': restaurant.category,
        'zone': restaurant.zone,
        'phone_number': restaurant.phoneNumber,
        'url': restaurant.url,
      };
    } else {
      snapshots.remove(key);
    }
    await _persistFavoriteState();
    await prefs.setString(
      _kFavoriteGeneralRestaurantItemsKey,
      jsonEncode(snapshots),
    );
  }

  Future<void> _toggleFavoriteAffiliateRestaurant(int restaurantId) async {
    await _setFavoriteAffiliateRestaurant(
      restaurantId,
      !_isFavoriteAffiliateRestaurant(restaurantId),
    );
  }

  Future<void> _toggleFavoriteGeneralRestaurant(
    GeneralRestaurantSummary restaurant,
  ) async {
    await _setFavoriteGeneralRestaurant(
      restaurant,
      !_isFavoriteGeneralRestaurant(restaurant),
    );
  }

  Future<List<UserCoupon>> _fetchIssuedCoupons() async {
    try {
      final coupons = await CouponService.fetchMyCoupons(
        status: CouponStatus.issued,
      );
      if (mounted) {
        setState(() {
          _requiresLogin = false;
        });
      }
      return coupons;
    } on ApiAuthException catch (e) {
      if (mounted) {
        setState(() {
          _requiresLogin = true;
        });
      }
      _showSnack(e.message);
      return const [];
    } on ApiHttpException catch (e) {
      debugPrint('Coupon API error: HTTP ${e.statusCode}');
      return const [];
    } catch (e) {
      debugPrint('Coupon API unexpected error: $e');
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

      final current =
          counts[restaurantId] ?? const _CouponCounts(issued: 0, redeemed: 0);
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

  List<AffiliateRestaurantSummary> get _filteredAffiliateRestaurants {
    if (_selectedCategory == 'ALL') {
      return _affiliateRestaurants;
    }
    return _affiliateRestaurants
        .where(
          (restaurant) =>
              _normalizedCategoryForState(restaurant.category) ==
              _selectedCategory,
        )
        .toList();
  }

  List<GeneralRestaurantSummary> get _filteredGeneralRestaurants {
    if (_selectedCategory == 'ALL') {
      return _generalRestaurants;
    }
    return _generalRestaurants
        .where(
          (restaurant) =>
              _normalizedCategoryForState(restaurant.category) ==
              _selectedCategory,
        )
        .toList();
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    AnalyticsLogger.logEvent(
      'affiliate_category_click',
      parameters: {
        'category': category,
        'from_category': _selectedCategory,
      },
    );
    setState(() => _selectedCategory = category);
  }

  void _handleSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _load();
    });
  }

  void _handleSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = value);
    _load();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 280) {
      _appendGeneralRestaurants();
    }
  }

  Future<void> _appendGeneralRestaurants() async {
    if (_isLoading || _isAppending || !_hasMoreGeneralRestaurants) return;
    final nextOffset = _nextGeneralOffset;
    if (nextOffset == null) return;

    setState(() {
      _isAppending = true;
    });

    try {
      final response = await AffiliateService.fetchTabRestaurants(
        query: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        limit: _kGeneralRestaurantPageSize,
        offset: nextOffset,
        includeAffiliates: false,
      );
      if (!mounted) return;

      final existingKeys =
          _generalRestaurants.map(_generalRestaurantFavoriteKey).toSet();
      final incoming = response.generalRestaurants.where((restaurant) {
        return !existingKeys
            .contains(_generalRestaurantFavoriteKey(restaurant));
      }).toList();

      setState(() {
        _generalRestaurants = List<GeneralRestaurantSummary>.from(
          _generalRestaurants,
        )..addAll(incoming);
        _hasMoreGeneralRestaurants = response.generalPagination.hasMore;
        _nextGeneralOffset = response.generalPagination.nextOffset;
        _categories = _sortCategories({
          ..._categories,
          ..._generalRestaurants
              .map((restaurant) =>
                  _normalizedCategoryForState(restaurant.category))
              .where((category) => category.trim().isNotEmpty),
        });
      });
    } on ApiNetworkException catch (e) {
      _showSnack('일반 식당을 더 불러오지 못했어요. (${e.cause})');
    } on ApiHttpException catch (e) {
      _showSnack('일반 식당을 더 불러오지 못했어요. (HTTP ${e.statusCode})');
    } catch (_) {
      _showSnack('일반 식당을 더 불러오지 못했어요.');
    } finally {
      if (mounted) {
        setState(() {
          _isAppending = false;
        });
      }
    }
  }

  String _normalizeForSearch(String value) {
    return value.trim().toLowerCase();
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
    return _kCategoryAlias[normalized] ??
        _kCategoryAlias[category.trim()] ??
        normalized;
  }

  String _normalizedCategoryForState(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return '';
    final key = _normalizeCategoryKey(trimmed);
    if (_kCategoryMeta.containsKey(key)) {
      return key;
    }
    return trimmed;
  }

  _CategoryMeta _resolveCategoryMeta(String category) {
    final key = _normalizeCategoryKey(category);
    final meta = _kCategoryMeta[key];
    if (meta != null) {
      return meta;
    }
    final trimmed = category.trim();
    final label = trimmed.isEmpty ? '기타' : (category == 'ALL' ? '전체' : trimmed);
    return _CategoryMeta(label, _kCategoryMeta['ALL']!.assetPath);
  }

  List<UserCoupon> _couponsForRestaurant(int restaurantId) {
    final filtered = _issuedCoupons
        .where((coupon) => coupon.restaurantId == restaurantId)
        .toList();
    return _sortCouponsByStatus(filtered);
  }

  /// 식당의 쿠폰 목록을 서버에서 새로 불러옵니다.
  Future<List<UserCoupon>> _refreshCouponsForRestaurant(
      int restaurantId) async {
    try {
      final allCoupons = await CouponService.fetchMyCoupons(
        status: CouponStatus.issued,
      );
      return allCoupons
          .where((coupon) => coupon.restaurantId == restaurantId)
          .toList();
    } catch (e) {
      return const [];
    }
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
            issueKey: 'STAMP_REWARD:reward',
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
      final index = _affiliateRestaurants
          .indexWhere((restaurant) => restaurant.id == restaurantId);
      if (index != -1) {
        final updated = _copyRestaurantWithStampStatus(
          _affiliateRestaurants[index],
          status,
        );
        _affiliateRestaurants =
            List<AffiliateRestaurantSummary>.from(_affiliateRestaurants)
              ..[index] = updated;
      }
    });
  }

  Future<void> _openRestaurantDetail(
      AffiliateRestaurantSummary restaurant) async {
    if (_isOpeningDetail) return;
    AnalyticsLogger.logEvent(
      'affiliate_restaurant_click',
      parameters: {
        'restaurant_id': restaurant.id,
        'restaurant_name': restaurant.name,
        'category': restaurant.category,
        'zone': restaurant.zone,
      },
    );
    setState(() => _isOpeningDetail = true);
    // 식당 상세 화면을 열기 전에 최신 쿠폰 정보를 가져옵니다.
    List<UserCoupon> initialCoupons = _couponsForRestaurant(restaurant.id);
    try {
      if (!_requiresLogin) {
        try {
          final refreshedCoupons =
              await _refreshCouponsForRestaurant(restaurant.id);
          if (refreshedCoupons.isNotEmpty) {
            initialCoupons = refreshedCoupons;
            // 메인 화면의 쿠폰 목록도 업데이트
            setState(() {
              _issuedCoupons = _sortCouponsByStatus(
                List<UserCoupon>.from(_issuedCoupons)
                  ..removeWhere((c) => c.restaurantId == restaurant.id)
                  ..addAll(refreshedCoupons),
              );
              _couponCounts = _buildCouponCounts(_issuedCoupons);
            });
          }
        } catch (e) {
          // 쿠폰 새로고침 실패 시 기존 쿠폰 목록 사용
        }
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return AffiliateRestaurantDetailSheet(
            restaurant: restaurant,
            coupons: initialCoupons,
            requiresLogin: _requiresLogin,
            isFavorite: _isFavoriteAffiliateRestaurant(restaurant.id),
            onFavoriteChanged: (isFavorite) {
              _setFavoriteAffiliateRestaurant(restaurant.id, isFavorite);
            },
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
      if (mounted) {
        setState(() => _isOpeningDetail = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final appBar = AppBar(
      backgroundColor: const Color(0xFF172133),
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 0,
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: RefreshIndicator(
          // 화면 진입 시 로딩과 통일감 있게, 브랜드 컬러/두께를 맞춘 인디케이터 사용
          color: const Color(0xFF6366F1),
          backgroundColor: Colors.white,
          strokeWidth: 2,
          onRefresh: _load,
          child: ListView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(
            top: 16,
            // 마지막 식당 카드 한 블록 정도의 여백은 두어서
            // 하단 바와 겹치지 않고 자연스럽게 보이도록 유지합니다.
            bottom: 140,
          ),
          children: [
            _buildRestaurantSearchBar(),
            const SizedBox(height: 12),
            _buildCategoryFilter(),
            const SizedBox(height: 12),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: const Text(
                    '불러오는 중...',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else if (_filteredAffiliateRestaurants.isEmpty &&
                _filteredGeneralRestaurants.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    _normalizeForSearch(_searchQuery).isEmpty
                        ? '표시할 식당이 없어요.'
                        : '검색 결과가 없어요.',
                  ),
                ),
              )
            else ...[
              if (_filteredAffiliateRestaurants.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Text(
                    '제휴 식당',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
                ..._filteredAffiliateRestaurants.map(
                  (restaurant) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildAffiliateRestaurantCard(restaurant),
                  ),
                ),
              ],
              if (_filteredGeneralRestaurants.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Text(
                    '일반 식당',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
                ..._filteredGeneralRestaurants.map(
                  (restaurant) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildGeneralRestaurantCard(restaurant),
                  ),
                ),
                if (_isAppending)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildRestaurantSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFD9D9D9)),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            color: Color(0xFF39393E),
            fontSize: 14,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
          ),
          onChanged: _handleSearchChanged,
          onSubmitted: _handleSearchSubmitted,
          decoration: InputDecoration(
            border: InputBorder.none,
            isCollapsed: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            hintText: '식당명을 검색해보세요',
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w500,
            ),
            prefixIcon:
                const Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
            suffixIcon: _searchFocusNode.hasFocus ||
                    !_normalizeForSearch(_searchQuery).isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchFocusNode.hasFocus)
                        IconButton(
                          onPressed: () =>
                              FocusScope.of(context).unfocus(),
                          icon: const Icon(Icons.keyboard_hide, size: 20),
                          color: const Color(0xFF6B7280),
                          splashRadius: 18,
                          tooltip: '키보드 내리기',
                        ),
                      if (!_normalizeForSearch(_searchQuery).isEmpty)
                        IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _handleSearchSubmitted('');
                          },
                          icon: const Icon(Icons.close, size: 18),
                          color: const Color(0xFF6B7280),
                          splashRadius: 18,
                        ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    if (_categories.isEmpty) {
      return const SizedBox.shrink();
    }
    const double scale = 1.00; // 기존 1.125의 0.72배
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

  Widget _buildAffiliateRestaurantCard(AffiliateRestaurantSummary restaurant) {
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
      stampLabel = '스탬프 $stampCurrent/$stampTarget';
    } else if (stampCurrent > 0) {
      stampLabel = '스탬프 $stampCurrent개';
    } else {
      stampLabel = '스탬프 적립 없음';
    }

    return InkWell(
      onTap: () => _openRestaurantDetail(restaurant),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
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
              child: SizedBox(
                width: 108,
                height: 108,
                child: Container(
                  color: const Color(0xFFE5E7EB),
                  child: _isValidNetworkImageUrl(thumbnailUrl)
                      ? Image.network(
                          thumbnailUrl!.trim(),
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
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              _toggleFavoriteAffiliateRestaurant(restaurant.id),
                          splashRadius: 18,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          icon: Icon(
                            _isFavoriteAffiliateRestaurant(restaurant.id)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 20,
                            color: _isFavoriteAffiliateRestaurant(restaurant.id)
                                ? const Color(0xFFE11D48)
                                : const Color(0xFF9CA3AF),
                          ),
                          tooltip: _isFavoriteAffiliateRestaurant(restaurant.id)
                              ? '찜 해제'
                              : '찜하기',
                        ),
                        const Icon(
                          Icons.keyboard_arrow_right,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildStampTag(stampLabel, _requiresLogin),
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

  Widget _buildGeneralRestaurantCard(GeneralRestaurantSummary restaurant) {
    final isLiked = _isFavoriteGeneralRestaurant(restaurant);
    final hasUrl = restaurant.url.trim().isNotEmpty;
    final categoryLabel =
        _resolveCategoryMeta(_normalizedCategoryForState(restaurant.category))
            .label;
    final locationLabel = restaurant.zone.trim().isNotEmpty
        ? restaurant.zone.trim()
        : (restaurant.address.trim().isNotEmpty
            ? restaurant.address.trim()
            : '위치 정보 없음');

    return InkWell(
      onTap: hasUrl ? () => _openGeneralRestaurantUrl(restaurant.url) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 17,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    restaurant.name.isNotEmpty
                        ? restaurant.name
                        : '매장 정보를 찾을 수 없어요',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => _toggleFavoriteGeneralRestaurant(restaurant),
                  splashRadius: 18,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: isLiked
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF9CA3AF),
                  ),
                  tooltip: isLiked ? '찜 해제' : '찜하기',
                ),
                Icon(
                  Icons.keyboard_arrow_right,
                  color: hasUrl
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFFD1D5DB),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFEEF2FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      categoryLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
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

  Future<void> _openGeneralRestaurantUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      _showSnack('이 식당은 이동할 링크가 없어요.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _showSnack('유효한 링크가 아니에요.');
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _showSnack('링크를 열 수 없어요.');
      }
    } catch (_) {
      _showSnack('링크를 열 수 없어요.');
    }
  }

  void _showSnack(String message) {
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
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
    required this.isFavorite,
    required this.onFavoriteChanged,
    this.initialStampStatus,
    required this.onStampStatusUpdated,
    required this.onCouponRedeemed,
    required this.onRewardCouponsIssued,
  });

  final AffiliateRestaurantSummary restaurant;
  final List<UserCoupon> coupons;
  final bool requiresLogin;
  final bool isFavorite;
  final void Function(bool isFavorite) onFavoriteChanged;
  final StampStatus? initialStampStatus;
  final void Function(StampStatus status) onStampStatusUpdated;
  final void Function(String couponCode) onCouponRedeemed;
  final void Function(List<String> couponCodes) onRewardCouponsIssued;

  @override
  State<AffiliateRestaurantDetailSheet> createState() =>
      _AffiliateRestaurantDetailSheetState();
}

/// rewards가 비어 있을 때 사용하는 레거시 fallback
/// target=9만으로는 3·6·9 vs 5만 등 구분 불가 → 모두 5·10 패턴 사용
/// (다이와스시: target=9인데 5만 혜택 → 3·6·9 fallback 시 잘못된 3 표기)
List<StampReward> _fallbackRewardsForEmpty({int? target}) {
  return const [
    StampReward(stamps: 5, title: '5개 보상', subtitle: '3,000원 할인'),
    StampReward(stamps: 10, title: '10개 보상', subtitle: '10,000원 할인'),
  ];
}

class _AffiliateRestaurantDetailSheetState
    extends State<AffiliateRestaurantDetailSheet> {
  late List<UserCoupon> _coupons;
  StampStatus? _stampStatus;
  bool _isStampLoading = true;
  bool _isStampProcessing = false;
  String? _stampError;
  String? _processingCouponCode;
  final PageController _imagePageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentImageIndex = 0;
  late bool _isFavorite;
  double _lastLoggedScrollOffset = 0;

  /// API rewards 또는 레거시 fallback에서 threshold별 혜택 문구 반환 (THRESHOLD 패턴용)
  String? _stampBenefitFor(int threshold) {
    final status = _stampStatus;
    if (status == null) return null;
    final apiRewards = status.rewards.isNotEmpty
        ? status.rewards
        : _fallbackRewardsForEmpty(target: status.target);
    for (final r in apiRewards) {
      if (r.stamps == threshold) {
        return (r.subtitle != null && r.subtitle!.isNotEmpty)
            ? r.subtitle!
            : r.title;
      }
    }
    if (status.rewards.isEmpty) {
      if (threshold == 5) return '3,000원 할인';
      if (threshold == 10) return '10,000원 할인';
    }
    return null;
  }

  /// StampReward의 혜택 문구 반환 (subtitle 또는 title)
  String _benefitTextFor(StampReward r) {
    return (r.subtitle != null && r.subtitle!.isNotEmpty)
        ? r.subtitle!
        : (r.title ?? '리워드 쿠폰');
  }

  /// 현재 스탬프 수가 속한 구간의 혜택 (VISIT 패턴: 1~3개일 때 1~4 구간 혜택 표시 등)
  StampReward? _getCurrentReward() {
    final status = _stampStatus;
    if (status == null) return null;
    final apiRewards = status.rewards.isNotEmpty
        ? status.rewards
        : _fallbackRewardsForEmpty(target: status.target);
    final current = status.current;

    final visitRewards = apiRewards
        .where((r) => r.isVisitPattern && r.minVisit != null)
        .toList();
    if (visitRewards.isEmpty) return null;

    visitRewards.sort(
        (a, b) => (a.minVisit ?? 0).compareTo(b.minVisit ?? 0));
    for (final r in visitRewards) {
      final min = r.minVisit ?? 0;
      final max = r.maxVisit;
      if (current >= min && (max == null || current <= max)) {
        return r;
      }
    }
    return null;
  }

  /// 앞으로 받을 수 있는 가장 가까운 혜택 (THRESHOLD: stamps>current, VISIT: minVisit>current)
  StampReward? _getNextReward() {
    final status = _stampStatus;
    if (status == null) return null;
    final apiRewards = status.rewards.isNotEmpty
        ? status.rewards
        : _fallbackRewardsForEmpty(target: status.target);
    final current = status.current;

    final thresholdRewards = apiRewards
        .where((r) => r.stamps != null && r.stamps! > 0)
        .toList();
    final visitRewards = apiRewards
        .where((r) => r.isVisitPattern && r.minVisit != null)
        .toList();

    if (thresholdRewards.isNotEmpty) {
      thresholdRewards.sort((a, b) => (a.stamps ?? 0).compareTo(b.stamps ?? 0));
      for (final r in thresholdRewards) {
        if ((r.stamps ?? 0) > current) return r;
      }
    }
    if (visitRewards.isNotEmpty) {
      visitRewards.sort(
          (a, b) => (a.minVisit ?? 0).compareTo(b.minVisit ?? 0));
      for (final r in visitRewards) {
        if ((r.minVisit ?? 0) > current) return r;
      }
    }
    return null;
  }

  /// 다음 혜택에 대한 헤드라인 문구 생성
  String _formatRewardHeadline(StampReward r) {
    final benefit = _benefitTextFor(r);
    if (r.isVisitPattern && r.minVisit != null && r.maxVisit != null) {
      return '스탬프 ${r.minVisit}~${r.maxVisit}개 적립 시 $benefit 제공';
    }
    if (r.stamps != null) {
      return '스탬프 ${r.stamps}개 적립 시 $benefit 제공';
    }
    return '스탬프 적립 시 $benefit 제공';
  }

  /// API rewards 또는 fallback에서 threshold 목록 반환 (정렬됨, 그리드 milestone용)
  List<int> _stampThresholds() {
    final status = _stampStatus;
    if (status == null) return const [5, 10];
    final apiRewards = status.rewards.isNotEmpty
        ? status.rewards
        : _fallbackRewardsForEmpty(target: status.target);
    final list = <int>[];
    for (final r in apiRewards) {
      if (r.stamps != null && r.stamps! > 0) {
        list.add(r.stamps!);
      } else if (r.isVisitPattern && r.minVisit != null) {
        list.add(r.minVisit!);
      }
    }
    list.sort();
    final unique = list.toSet().toList()..sort();
    return unique.isNotEmpty ? unique : [5, 10];
  }

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
    _coupons = List<UserCoupon>.from(widget.coupons);
    _sortCoupons();
    _scrollController.addListener(_onScroll);
    _stampStatus = widget.initialStampStatus ??
        StampStatus(
          current: widget.restaurant.stampCurrent,
          target: widget.restaurant.stampTarget,
          updatedAt: null,
        );
    final hasInitialStatus = widget.initialStampStatus != null;
    final hasEmptyRewards =
        hasInitialStatus &&
        (widget.initialStampStatus!.rewards.isEmpty ||
            widget.initialStampStatus!.rewards
                .where((r) => r.stamps != null && r.stamps! > 0)
                .isEmpty);
    if (!widget.requiresLogin && (!hasInitialStatus || hasEmptyRewards)) {
      // 상세 시트는 단건 API로 전체 rewards 조회 (all API는 rewards 생략 가능)
      _isStampLoading = true;
      _loadStampStatus(
        showLoading: true,
        preferSingleApi: true,
      );
    } else {
      _isStampLoading = false;
      if (widget.requiresLogin) {
        _stampError = '로그인 후 스탬프 정보를 확인할 수 있어요.';
      }
    }
  }

  void _toggleFavorite() {
    setState(() {
      _isFavorite = !_isFavorite;
    });
    widget.onFavoriteChanged(_isFavorite);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _imagePageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if (offset > _lastLoggedScrollOffset + 100) {
      _lastLoggedScrollOffset = offset;
      AnalyticsLogger.logEvent(
        AnalyticsEvents.restaurantDetailScroll,
        parameters: {
          AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
          AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
          AnalyticsEvents.paramScrollDepth: offset.round(),
        },
      );
    }
  }

  Future<void> _loadStampStatus({
    bool showLoading = true,
    bool preferSingleApi = false,
  }) async {
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
      final status = await _fetchStampStatusWithFallback(
        preferSingleApi: preferSingleApi,
      );
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

  /// preferSingleApi: true면 all 대신 식당별 단건 API 사용 (rewards 전체 조회용)
  Future<StampStatus> _fetchStampStatusWithFallback(
      {bool preferSingleApi = false}) async {
    if (preferSingleApi) {
      return CouponService.fetchStampStatus(
        restaurantId: widget.restaurant.id,
      );
    }
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
      description: const [
        TextSpan(
          text: '스탬프를 적립하시겠습니까?\n\n관리자 비밀번호를 입력하시면\n\n스탬프 1개가 적립됩니다.',
          style: TextStyle(
            color: Color(0xFF39393E),
            fontSize: 14,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
            height: 0.70,
          ),
        ),
      ],
    );
    if (pin == null) return;

    setState(() {
      _isStampProcessing = true;
      _stampError = null;
    });
    final addResult = await CouponService.addStamp(
      restaurantId: widget.restaurant.id,
      pin: pin,
    );
    if (!mounted) return;
    if (!addResult.isSuccess) {
      setState(() {
        _isStampProcessing = false;
        _stampError = addResult.errorMessage ?? '요청이 실패했어요.';
      });
      return;
    }
    final result = addResult.result!;
    try {
      AnalyticsLogger.logEvent(
        AnalyticsEvents.stampIssued,
        parameters: {
          AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
          AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
          AnalyticsEvents.paramStampCountAfter: result.status.current,
        },
      );
      // result.status는 rewards, notes가 없으므로 재조회하여 전체 정보 갱신
      try {
        final fullStatus = await CouponService.fetchStampStatus(
          restaurantId: widget.restaurant.id,
        );
        if (!mounted) return;
        setState(() {
          _stampStatus = fullStatus;
        });
        widget.onStampStatusUpdated(fullStatus);
      } catch (_) {
        // 재조회 실패 시 current/target만 반영 (rewards/notes는 기존 유지)
        final merged = StampStatus(
          current: result.status.current,
          target: result.status.target,
          updatedAt: result.status.updatedAt,
          rewardCoupons: result.status.rewardCoupons,
          rewards: _stampStatus?.rewards ?? const [],
          notes: _stampStatus?.notes,
        );
        if (!mounted) return;
        setState(() {
          _stampStatus = merged;
        });
        widget.onStampStatusUpdated(merged);
      }
      _showSnack('스탬프를 적립했어요.');
      final rewardCodesSet = <String>{
        ...result.rewardCouponCodes.where((code) => code.isNotEmpty),
      };
      final reward = result.rewardCouponCode;
      if (reward != null && reward.isNotEmpty) {
        rewardCodesSet.add(reward);
      }
      final rewardCodes = rewardCodesSet.toList();

      // reward_coupons 기반 coupon_issued 로깅 (백엔드 형식)
      if (result.rewardCoupons.isNotEmpty) {
        for (final r in result.rewardCoupons) {
          if (r.couponCode.isEmpty) continue;
          final params = <String, Object>{
            AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
            AnalyticsEvents.paramCouponIssueSource: 'STAMP_REWARD',
            AnalyticsEvents.paramCouponCode: r.couponCode,
          };
          if (r.couponType.isNotEmpty) {
            params[AnalyticsEvents.paramCouponTypeCode] = r.couponType;
          }
          AnalyticsLogger.logEvent(
            AnalyticsEvents.couponIssued,
            parameters: params,
          );
        }
        await CouponService.markCouponsAsSeen(
            result.rewardCoupons.map((r) => r.couponCode));
      } else {
        for (final code in rewardCodes) {
          AnalyticsLogger.logEvent(
            AnalyticsEvents.couponIssued,
            parameters: {
              AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
              AnalyticsEvents.paramCouponIssueSource: 'STAMP_REWARD',
              AnalyticsEvents.paramCouponCode: code,
            },
          );
        }
        await CouponService.markCouponsAsSeen(rewardCodes);
      }

      if (rewardCodes.isNotEmpty) {
        AnalyticsLogger.logEvent(
          AnalyticsEvents.stampRewardCouponIssued,
          parameters: {
            AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
            AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
            AnalyticsEvents.paramCouponCount: rewardCodes.length,
            AnalyticsEvents.paramIssueSource: 'STAMP_REWARD',
          },
        );
        // 새로 발급된 쿠폰의 benefit 정보를 서버에서 가져오기 위해
        // 해당 식당의 쿠폰 목록을 다시 불러옵니다.
        try {
          final allCoupons = await CouponService.fetchMyCoupons(
            status: CouponStatus.issued,
          );
          final restaurantCoupons = allCoupons
              .where((coupon) => coupon.restaurantId == widget.restaurant.id)
              .toList();

          if (!mounted) return;

          final existingCodes = _coupons.map((coupon) => coupon.code).toSet();
          final newCoupons = restaurantCoupons
              .where((coupon) => !existingCodes.contains(coupon.code))
              .toList();

          if (newCoupons.isNotEmpty) {
            setState(() {
              _coupons = List<UserCoupon>.from(_coupons)..addAll(newCoupons);
              _sortCoupons();
            });
            widget.onRewardCouponsIssued(
                newCoupons.map((c) => c.code).toList());
          }

          final buffer = StringBuffer();
          if (newCoupons.isNotEmpty) {
            buffer.write(
                '새 리워드 쿠폰이 발급되었어요: ${newCoupons.map((c) => c.code).join(', ')}');
          } else {
            buffer.write('보유 중인 리워드 쿠폰을 다시 안내해드려요.');
          }
          buffer.write('\n현재 리워드 쿠폰: ${rewardCodes.join(', ')}');
          _showSnack(buffer.toString());
        } catch (e) {
          // 쿠폰 목록을 가져오는 데 실패한 경우, 기존 방식대로 처리
          final existingCodes = _coupons.map((coupon) => coupon.code).toSet();
          final newCodes = rewardCodes
              .where((code) => !existingCodes.contains(code))
              .toList();
          if (newCodes.isNotEmpty) {
            setState(() {
              _coupons = List<UserCoupon>.from(_coupons)
                ..addAll(
                  newCodes.map(
                  (code) => UserCoupon(
                    code: code,
                    status: CouponStatus.issued,
                    restaurantId: widget.restaurant.id,
                    issueKey: 'STAMP_REWARD:reward',
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
      }
    } on ApiAuthException catch (e) {
      if (mounted) setState(() => _stampError = e.message);
    } on ApiHttpException catch (e) {
      final msg = _extractDetailMessage(e.body) ??
          (e.statusCode == 400 || e.statusCode == 401
              ? '비밀번호가 올바르지 않아요. 다시 확인해 주세요.'
              : '요청이 실패했어요 (HTTP ${e.statusCode})');
      if (mounted) setState(() => _stampError = msg);
    } on ApiNetworkException catch (e) {
      if (mounted) setState(() => _stampError = '네트워크 오류: ${e.cause}');
    } catch (e) {
      if (mounted) setState(() => _stampError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isStampProcessing = false);
      }
    }
  }

  String? _formatExpiryDate(DateTime? expiresAt) {
    if (expiresAt == null) return null;

    final now = DateTime.now();
    final difference = expiresAt.difference(now);

    if (difference.isNegative) {
      return '만료됨';
    }

    if (difference.inHours < 24) {
      if (difference.inHours > 0) {
        return '${difference.inHours}시간 남음';
      }
      if (difference.inMinutes > 0) {
        return '${difference.inMinutes}분 남음';
      }
      return '곧 만료';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays}일 남음';
    }

    return '${expiresAt.year}.${expiresAt.month.toString().padLeft(2, '0')}.${expiresAt.day.toString().padLeft(2, '0')}까지';
  }

  Future<void> _handleRedeem(UserCoupon coupon) async {
    setState(() => _processingCouponCode = coupon.code);
    try {
      final success = await _showRedeemPinDialog(
        coupon: coupon,
        restaurantId: widget.restaurant.id,
        restaurantName: widget.restaurant.name,
        notes: coupon.benefit?.notesText,
      );
      if (!mounted) return;
      if (success) {
        setState(() {
          _coupons = _coupons.where((item) => item.code != coupon.code).toList();
        });
        widget.onCouponRedeemed(coupon.code);
        _showSnack('쿠폰을 사용했어요.');
      }
    } finally {
      if (mounted) {
        setState(() => _processingCouponCode = null);
      }
    }
  }

  /// 쿠폰 사용 PIN 다이얼로그. redeem 실패 시 입력창 내 에러 표시
  Future<bool> _showRedeemPinDialog({
    required UserCoupon coupon,
    required int restaurantId,
    String? restaurantName,
    String? notes,
  }) async {
    final controller = TextEditingController();
    String? error;
    bool isLoading = false;
    final hasNotes = notes != null && notes.isNotEmpty;
    return (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 360,
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
              ),
              child: Container(
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
                      const SizedBox(height: 22),
                      Text.rich(
                        const TextSpan(
                          text: '해당 쿠폰을 사용처리 하시겠습니까?\n\n관리자 비밀번호를 입력하시면\n\n즉시 사용처리 됩니다.',
                          style: TextStyle(
                            color: Color(0xFF39393E),
                            fontSize: 15,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w500,
                            height: 0.70,
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
                              color: const Color(0xFFE5E5E5),
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
                      const SizedBox(height: 26),
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
                                                coupon.couponIssueSource,
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
            ),
          );
        });
      },
    )) ?? false;
  }

  Future<String?> _promptForPin({
    required String title,
    required String confirmLabel,
    required List<TextSpan> description,
    String? notes,
  }) async {
    final controller = TextEditingController();
    String? error;
    final hasNotes = notes != null && notes.isNotEmpty;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 360,
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
              ),
              child: Container(
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
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF39393E),
                          fontSize: 19,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          height: 1.21,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text.rich(
                        TextSpan(children: description),
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
                              color: const Color(0xFFE5E5E5),
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
                      const SizedBox(height: 26),
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
                            onPressed: () => Navigator.of(dialogContext).pop(),
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
                            child: Text(confirmLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          );
        },
        );
      },
    );
  }

  void _showSnack(String message) {
    // 모달 시트 내 SnackBar → Scaffold 레이아웃 충돌 발생. 스탬프/쿠폰 에러는 _stampError 등으로 표시
    if (message.isEmpty || !mounted) return;
    // SnackBar 호출 제거 (ScaffoldLayout.performLayout 오류 원인)
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = widget.restaurant;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    // 아이폰 다이나믹 아일랜드 등을 고려한 최소 상단 여백
    final safeTopPadding = math.max(topPadding, 50.0);
    return Container(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.only(top: safeTopPadding),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroSection(restaurant),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildBenefitsTab(restaurant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Color(0xFF6B7280),
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitsTab(AffiliateRestaurantSummary restaurant) {
    return Column(
      key: const ValueKey('benefits'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStampSection(),
        const SizedBox(height: 24),
        _buildCouponSection(),
        const SizedBox(height: 32),
        _buildStoreInfoTab(restaurant),
      ],
    );
  }

  Widget _buildStoreInfoTab(AffiliateRestaurantSummary restaurant) {
    return Column(
      key: const ValueKey('info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget _buildRestaurantHeader(AffiliateRestaurantSummary restaurant) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            restaurant.name.isNotEmpty ? restaurant.name : '매장 정보를 찾을 수 없어요',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  restaurant.address.isNotEmpty
                      ? restaurant.address
                      : '주소 정보를 불러오지 못했어요.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (restaurant.category.isNotEmpty || restaurant.zone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (restaurant.category.isNotEmpty)
                        _buildInfoChip(restaurant.category),
                      if (restaurant.zone.isNotEmpty)
                        _buildInfoChip(restaurant.zone),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  tooltip: _isFavorite ? '찜 해제' : '찜하기',
                  color: _isFavorite
                      ? const Color(0xFFE11D48)
                      : const Color(0xFF6B7280),
                ),
                if (restaurant.url != null && restaurant.url!.isNotEmpty)
                  IconButton(
                    onPressed: _openRestaurantPage,
                    icon: const Icon(Icons.link),
                    tooltip: '매장 페이지 열기',
                    color: const Color(0xFF111439),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroSection(AffiliateRestaurantSummary restaurant) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: _buildImageCarousel(restaurant.imageUrls),
          ),
          _buildRestaurantHeader(restaurant),
        ],
      ),
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
            const SizedBox(height: 12),
            const Text(
              '하루 최대 3회 적립 가능',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_stampStatus?.notes != null &&
                _stampStatus!.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStampNotes(_stampStatus!.notes!),
            ],
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
                  disabledBackgroundColor: const Color(0xFF4B5563),
                  disabledForegroundColor: Colors.white,
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
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '적립 중...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
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
    final rewardThresholds = _stampThresholds();
    final total = math.max(
      status.target,
      rewardThresholds.isNotEmpty ? rewardThresholds.last : 10,
    );
    final filled = math.min(status.current, total);
    final milestoneSet = rewardThresholds.isNotEmpty
        ? rewardThresholds.toSet()
        : <int>{5, 10};

    // 메인 리워드 요약 문구: VISIT 패턴이면 현재 구간 혜택, 아니면 다음 목표 혜택 표시
    // (THRESHOLD: 1,3,5,7,10 / VISIT: 1~4, 5~9, 10 등 식당별 상이)
    String? headline;
    final currentReward = _getCurrentReward();
    final nextReward = _getNextReward();
    if (currentReward != null) {
      headline = _formatRewardHeadline(currentReward);
    } else if (nextReward != null) {
      headline = _formatRewardHeadline(nextReward);
    } else if (rewardThresholds.isNotEmpty ||
        (status.rewards.isNotEmpty || status.target > 0)) {
      headline = '준비된 리워드 혜택을 모두 받았어요!';
    }

    // 다음 혜택까지 남은 스탬프 수 (10개 도달 시 0으로 초기화되는 사이클)
    int remainingToNext = 0;
    if (nextReward != null) {
      if (nextReward.stamps != null) {
        remainingToNext = math.max(nextReward.stamps! - status.current, 0);
      } else if (nextReward.minVisit != null) {
        remainingToNext =
            math.max(nextReward.minVisit! - status.current, 0);
      }
    }
    // 정든밤: VISIT 패턴으로 항상 "리워드까지 1개 남았어요" 표기
    final isJeongdeunbam =
        widget.restaurant.name.contains('정든밤');
    if (isJeongdeunbam && nextReward != null) {
      remainingToNext = 1;
    }
    final remainingText = remainingToNext > 0
        ? '리워드까지 ${remainingToNext}개 남았어요'
        : '리워드 획득 조건을 달성했어요!';

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
        if (headline != null) ...[
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 5;
            const stampSpacing = 6.0;
            const rowSpacing = 8.0;
            final stampSize =
                (constraints.maxWidth - stampSpacing * (columns - 1)) / columns;

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
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '현재 진행도',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${status.current} / $total',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: total > 0 ? filled / total : 0.0,
            minHeight: 8,
            backgroundColor: Colors.white.withOpacity(0.16),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFFFACC15),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          remainingText,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
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

  /// 스탬프 비고(유의사항) 표시. 오버플로우 방지를 위해 maxHeight + 스크롤 적용
  Widget _buildStampNotes(String notes) {
    final lines = notes.split('\n').where((s) => s.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: lines.map((line) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      line.trim(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
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
    final thresholds = _stampThresholds();
    final reachedThresholds =
        thresholds.where((t) => status.current >= t).toList();
    final pendingThresholds =
        thresholds.where((t) => status.current < t).toList();
    final thresholdSet = thresholds.toSet();

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
        const TextSpan(text: ' 적립 시 '),
        TextSpan(text: benefit, style: highlightStyle),
        const TextSpan(text: ' 제공'),
      ], upcomingStyle);
    }

    Widget buildReachedMessage(String benefit) {
      return buildRichText([
        TextSpan(text: benefit, style: highlightStyle),
        const TextSpan(text: ' 혜택을 이미 받았어요.'),
      ], baseStyle);
    }

    final List<Widget> items = [];
    for (final threshold in reachedThresholds) {
      final benefit = _stampBenefitFor(threshold);
      if (benefit != null) {
        items.add(buildReachedMessage(benefit));
      } else {
        items.add(
          Text(
            '스탬프 ${threshold}개 리워드 쿠폰을 이미 받았어요.',
            style: baseStyle,
          ),
        );
      }
    }

    Widget? nextMessageWidget;
    if (status.current < 5 &&
        (thresholdSet.contains(5) || thresholds.isEmpty || status.target <= 5)) {
      final benefit = _stampBenefitFor(5);
      nextMessageWidget = benefit != null
          ? buildUpcomingMessage(5, benefit)
          : Text(
              '스탬프 5개까지 적립시 첫 번째 리워드 쿠폰 제공',
              style: upcomingStyle,
            );
    } else if (status.current < 10 &&
        (thresholdSet.contains(10) || thresholds.isEmpty || status.target <= 10)) {
      final benefit = _stampBenefitFor(10);
      nextMessageWidget = benefit != null
          ? buildUpcomingMessage(10, benefit)
          : Text(
              '스탬프 10개까지 적립시 두 번째 리워드 쿠폰 제공',
              style: upcomingStyle,
            );
    } else if (pendingThresholds.isNotEmpty) {
      final threshold = pendingThresholds.first;
      final benefit = _stampBenefitFor(threshold);
      if (benefit != null) {
        nextMessageWidget = buildRichText([
          TextSpan(text: '스탬프 ${threshold}개 적립 시 '),
          TextSpan(text: benefit, style: highlightStyle),
          const TextSpan(text: ' 제공'),
        ], upcomingStyle);
      } else {
        final text = _pendingRewardMessage(
          threshold,
          status.current,
          math.max(threshold - status.current, 0),
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
            '스탬프 ${remainingToTarget}개 적립시 리워드 쿠폰 제공',
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
          return '스탬프 $numeric개 리워드 쿠폰';
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
    // 공통 포맷: "스탬프 ~개 적립 시 ~ 제공"
    if (benefit != null) {
      return '스탬프 ${threshold}개 적립 시 $benefit 제공';
    }
    if (threshold == 5 && current < 5) {
      return '스탬프 5개 적립 시 첫 번째 리워드 쿠폰 제공';
    }
    if (threshold == 10 && current >= 5 && current < 10) {
      return '스탬프 10개 적립 시 두 번째 리워드 쿠폰 제공';
    }
    final milestoneName = _milestoneLabel(threshold);
    return '스탬프 ${threshold}개 적립 시 $milestoneName 제공';
  }

  String _milestoneLabel(int threshold) {
    switch (threshold) {
      case 5:
        return '첫 번째 리워드 쿠폰';
      case 10:
        return '두 번째 리워드 쿠폰';
      default:
        return '스탬프 $threshold개 리워드 쿠폰';
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
          Row(
            children: [
              const Text(
                '보유 쿠폰',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              if (!widget.requiresLogin)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '쿠폰 목록 새로고침',
                  onPressed: _refreshCoupons,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
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

  bool _isRefreshingCoupons = false;

  Future<void> _refreshCoupons() async {
    if (_isRefreshingCoupons || widget.requiresLogin) return;
    setState(() {
      _isRefreshingCoupons = true;
    });
    try {
      final allCoupons = await CouponService.fetchMyCoupons(
        status: CouponStatus.issued,
      );
      final restaurantCoupons = allCoupons
          .where((coupon) => coupon.restaurantId == widget.restaurant.id)
          .toList();
      if (!mounted) return;
      setState(() {
        _coupons = restaurantCoupons;
        _sortCoupons();
      });
    } catch (e) {
      // 새로고침 실패 시 조용히 처리 (이미 표시된 쿠폰 목록 유지)
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingCoupons = false;
        });
      }
    }
  }

  Widget _buildCouponTile(UserCoupon coupon) {
    final isProcessing = _processingCouponCode == coupon.code;
    final benefit = coupon.benefit;
    final title = benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle;
    final subtitle =
        benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle;
    final statusText = _couponStatusLabel(coupon.status);
    final expiryText = _formatExpiryDate(coupon.expiresAt);
    final expiryColor = const Color.fromARGB(255, 185, 183, 247);
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFD1D6FF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (expiryText != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: expiryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          expiryText,
                          style: TextStyle(
                            fontSize: 12,
                            color: expiryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: double.infinity,
              child: Align(
                alignment: Alignment.bottomRight,
                child: ElevatedButton(
                  onPressed: isProcessing || widget.requiresLogin
                      ? null
                      : () => _handleRedeem(coupon),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0B1033),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCarousel(List<String> imageUrls) {
    if (imageUrls.isEmpty) {
      return AspectRatio(
        aspectRatio: 3 / 2,
        child: Container(
          color: const Color(0xFFF3F4F6),
          child: const Center(
            child: Text(
              '등록된 사진이 없어요.',
              style: TextStyle(color: Color(0xFF9CA3AF)),
            ),
          ),
        ),
      );
    }

    final items = imageUrls.toList();
    return AspectRatio(
      aspectRatio: 3 / 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _imagePageController,
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemCount: items.length,
            itemBuilder: (context, index) {
              final url = items[index];
              return Container(
                color: const Color(0xFFE5E7EB),
                child: _isValidNetworkImageUrl(url)
                    ? Image.network(
                        url.trim(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
              );
            },
          ),
          if (items.length > 1)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: List.generate(items.length, (index) {
                    final isActive = index == _currentImageIndex;
                    return Container(
                      width: isActive ? 8 : 6,
                      height: isActive ? 8 : 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.6),
                      ),
                    );
                  }),
                ),
              ),
            ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
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
