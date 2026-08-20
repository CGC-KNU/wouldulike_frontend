import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'affiliate_benefits_screen.dart';
import 'config/analytics_events.dart';
import 'services/affiliate_service.dart';
import 'utils/analytics_logger.dart';
import 'services/api_client.dart';
import 'services/coupon_service.dart';

const String _kFavoriteRestaurantIdsKey = 'affiliate_favorite_restaurant_ids';
const String _kFavoriteGeneralRestaurantKeysKey =
    'general_favorite_restaurant_keys';
const String _kFavoriteGeneralRestaurantItemsKey =
    'general_favorite_restaurant_items';

class _CouponCounts {
  const _CouponCounts({
    required this.total,
    required this.issued,
  });

  final int total;
  final int issued;
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

bool _isValidNetworkImageUrl(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

class FavoriteRestaurantsScreen extends StatefulWidget {
  const FavoriteRestaurantsScreen({super.key});

  @override
  State<FavoriteRestaurantsScreen> createState() =>
      _FavoriteRestaurantsScreenState();
}

class _FavoriteRestaurantsScreenState extends State<FavoriteRestaurantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  bool _isSearching = false;

  List<AffiliateRestaurantSummary> _restaurants = [];
  List<GeneralRestaurantSummary> _generalRestaurants = [];
  Set<int> _favoriteIds = <int>{};
  Set<String> _favoriteGeneralKeys = <String>{};
  Map<int, StampStatus> _stampStatuses = {};
  Map<int, _CouponCounts> _couponCountsDetailed = {};
  List<String> _categories = const ['ALL'];
  String _selectedCategory = 'ALL';
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isOpeningDetail = false;
  bool _requiresLogin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _isSearching = true;
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _isSearching = false);
    });
  }

  void _handleSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = value;
      _isSearching = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawFavoriteIds =
          prefs.getStringList(_kFavoriteRestaurantIdsKey) ?? const <String>[];
      final rawGeneralKeys =
          prefs.getStringList(_kFavoriteGeneralRestaurantKeysKey) ??
              const <String>[];
      final rawGeneralItems =
          prefs.getString(_kFavoriteGeneralRestaurantItemsKey);
      final favoriteIds = rawFavoriteIds
          .map((value) => int.tryParse(value))
          .whereType<int>()
          .toSet();
      final favoriteGeneralKeys = rawGeneralKeys
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      final generalSnapshotMap = <String, dynamic>{};
      if (rawGeneralItems != null && rawGeneralItems.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawGeneralItems);
          if (decoded is Map<String, dynamic>) {
            generalSnapshotMap.addAll(decoded);
          }
        } catch (_) {}
      }
      final all = await AffiliateService.fetchRestaurants();
      final favorites = all
          .where((restaurant) => favoriteIds.contains(restaurant.id))
          .toList();
      final generalFavorites = favoriteGeneralKeys
          .map((key) {
            final raw = generalSnapshotMap[key];
            if (raw is Map<String, dynamic>) {
              return GeneralRestaurantSummary.fromJson(raw);
            }
            if (raw is Map) {
              return GeneralRestaurantSummary.fromJson(
                Map<String, dynamic>.from(raw),
              );
            }
            return null;
          })
          .whereType<GeneralRestaurantSummary>()
          .toList();
      if (generalFavorites.length < favoriteGeneralKeys.length) {
        try {
          final response = await AffiliateService.fetchTabRestaurants(
            limit: 50,
            offset: 0,
            includeAffiliates: true,
          );
          final resolved = response.generalRestaurants.where((restaurant) {
            final key = _generalFavoriteKey(restaurant);
            return favoriteGeneralKeys.contains(key) &&
                !generalFavorites.any(
                  (item) => _generalFavoriteKey(item) == key,
                );
          }).toList();
          if (resolved.isNotEmpty) {
            generalFavorites.addAll(resolved);
            for (final item in resolved) {
              generalSnapshotMap[_generalFavoriteKey(item)] = <String, dynamic>{
                'restaurant_id': item.id,
                'name': item.name,
                'description': item.description,
                'address': item.address,
                'category': item.category,
                'zone': item.zone,
                'phone_number': item.phoneNumber,
                'url': item.url,
              };
            }
            await prefs.setString(
              _kFavoriteGeneralRestaurantItemsKey,
              jsonEncode(generalSnapshotMap),
            );
          }
        } catch (_) {}
      }
      List<UserCoupon> allCoupons = const <UserCoupon>[];
      try {
        allCoupons = await CouponService.fetchMyCoupons();
        _requiresLogin = false;
      } on ApiAuthException {
        _requiresLogin = true;
      } catch (_) {}
      final categories = <String>{'ALL'};
      for (final restaurant in favorites) {
        final norm = _normalizedCategoryForState(restaurant.category);
        if (norm.isNotEmpty) categories.add(norm);
      }
      for (final restaurant in generalFavorites) {
        final norm = _normalizedCategoryForState(restaurant.category);
        if (norm.isNotEmpty) categories.add(norm);
      }
      if (!mounted) return;
      setState(() {
        _favoriteIds = favoriteIds;
        _favoriteGeneralKeys = favoriteGeneralKeys;
        _restaurants = favorites;
        _generalRestaurants = generalFavorites;
        _couponCountsDetailed = _buildDetailedCouponCounts(allCoupons);
        _stampStatuses = {};
        _categories = _sortCategories(categories);
        _selectedCategory = 'ALL';
      });

      if (_requiresLogin || !mounted) return;
      try {
        final statuses = await _fetchStampStatuses(favorites);
        if (!mounted) return;
        setState(() {
          _stampStatuses = statuses;
        });
      } on ApiAuthException {
        if (!mounted) return;
        setState(() {
          _requiresLogin = true;
          _stampStatuses = {};
        });
      } on ApiNetworkException {
        // 네트워크 일시 이슈로 스탬프 동기화가 실패하면 기존 값을 유지한다.
      } on ApiHttpException {
        // 일부 매장의 스탬프 조회 실패는 무시한다.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '찜한 식당을 불러오지 못했어요.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(AffiliateRestaurantSummary restaurant) async {
    final id = restaurant.id;
    final next = Set<int>.from(_favoriteIds);
    final shouldFavorite = !next.contains(id);
    if (shouldFavorite) {
      next.add(id);
    } else {
      next.remove(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kFavoriteRestaurantIdsKey,
      next.map((e) => e.toString()).toList(),
    );
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantFavoriteToggle,
      parameters: {
        AnalyticsEvents.paramRestaurantId: id,
        AnalyticsEvents.paramRestaurantName: restaurant.name,
        AnalyticsEvents.paramAction: shouldFavorite ? 'add' : 'remove',
      },
    );
    if (!mounted) return;
      setState(() {
        _favoriteIds = next;
        _restaurants =
            _restaurants.where((item) => next.contains(item.id)).toList();
        final categories = <String>{'ALL'};
        for (final item in _restaurants) {
          final norm = _normalizedCategoryForState(item.category);
          if (norm.isNotEmpty) categories.add(norm);
        }
        for (final item in _generalRestaurants) {
          final norm = _normalizedCategoryForState(item.category);
          if (norm.isNotEmpty) categories.add(norm);
        }
        _categories = _sortCategories(categories);
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = 'ALL';
        }
      });
  }

  String _generalFavoriteKey(GeneralRestaurantSummary restaurant) {
    if (restaurant.id > 0) {
      return 'id:${restaurant.id}';
    }
    final normalizedUrl = restaurant.url.trim();
    if (normalizedUrl.isNotEmpty) {
      return 'url:$normalizedUrl';
    }
    return 'name:${restaurant.name.trim()}|addr:${restaurant.address.trim()}';
  }

  Future<void> _toggleGeneralFavorite(
      GeneralRestaurantSummary restaurant) async {
    final key = _generalFavoriteKey(restaurant);
    final next = Set<String>.from(_favoriteGeneralKeys);
    final shouldFavorite = !next.contains(key);
    if (shouldFavorite) {
      next.add(key);
    } else {
      next.remove(key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kFavoriteGeneralRestaurantKeysKey, next.toList());

    final rawGeneralItems =
        prefs.getString(_kFavoriteGeneralRestaurantItemsKey);
    final generalSnapshotMap = <String, dynamic>{};
    if (rawGeneralItems != null && rawGeneralItems.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawGeneralItems);
        if (decoded is Map<String, dynamic>) {
          generalSnapshotMap.addAll(decoded);
        }
      } catch (_) {}
    }
    if (shouldFavorite) {
      generalSnapshotMap[key] = <String, dynamic>{
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
      generalSnapshotMap.remove(key);
    }
    await prefs.setString(
      _kFavoriteGeneralRestaurantItemsKey,
      jsonEncode(generalSnapshotMap),
    );

    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantFavoriteToggle,
      parameters: {
        AnalyticsEvents.paramRestaurantId: restaurant.id,
        AnalyticsEvents.paramRestaurantName: restaurant.name,
        AnalyticsEvents.paramAction: shouldFavorite ? 'add' : 'remove',
      },
    );
    if (!mounted) return;
      setState(() {
        _favoriteGeneralKeys = next;
        _generalRestaurants = _generalRestaurants
            .where((item) => next.contains(_generalFavoriteKey(item)))
            .toList();
        final categories = <String>{'ALL'};
        for (final item in _restaurants) {
          final norm = _normalizedCategoryForState(item.category);
          if (norm.isNotEmpty) categories.add(norm);
        }
        for (final item in _generalRestaurants) {
          final norm = _normalizedCategoryForState(item.category);
          if (norm.isNotEmpty) categories.add(norm);
        }
        _categories = _sortCategories(categories);
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = 'ALL';
        }
      });
  }

  Map<int, _CouponCounts> _buildDetailedCouponCounts(
    List<UserCoupon> coupons,
  ) {
    final counts = <int, _CouponCounts>{};
    for (final coupon in coupons) {
      final restaurantId = coupon.restaurantId;
      if (restaurantId == null) continue;
      final issued = coupon.status == CouponStatus.issued ? 1 : 0;
      final current = counts[restaurantId];
      if (current == null) {
        counts[restaurantId] = _CouponCounts(total: 1, issued: issued);
      } else {
        counts[restaurantId] = _CouponCounts(
          total: current.total + 1,
          issued: current.issued + issued,
        );
      }
    }
    return counts;
  }

  Future<Map<int, StampStatus>> _fetchStampStatuses(
    List<AffiliateRestaurantSummary> restaurants,
  ) async {
    final statuses = <int, StampStatus>{};
    final targetIds = restaurants
        .map((restaurant) => restaurant.id)
        .where((id) => id != 0)
        .toSet();

    try {
      final collection = await CouponService.fetchAllStampStatuses();
      for (final id in targetIds) {
        final status = collection.statuses[id];
        if (status != null) {
          statuses[id] = status;
        }
      }
    } on ApiAuthException {
      rethrow;
    } catch (_) {}

    for (final id in targetIds) {
      if (statuses.containsKey(id)) continue;
      try {
        final status = await CouponService.fetchStampStatus(restaurantId: id);
        statuses[id] = status;
      } on ApiAuthException {
        rethrow;
      } catch (_) {
        // 개별 매장 실패는 무시하고 가능한 항목만 반영한다.
      }
    }

    return statuses;
  }

  void _handleStampStatusUpdated(int restaurantId, StampStatus status) {
    setState(() {
      _stampStatuses = Map<int, StampStatus>.from(_stampStatuses)
        ..[restaurantId] = status;
    });
  }

  void _handleCouponRedeemed(String couponCode, int restaurantId) {
    final current = _couponCountsDetailed[restaurantId];
    if (current == null) return;
    if (current.issued <= 0) return;
    setState(() {
      _couponCountsDetailed =
          Map<int, _CouponCounts>.from(_couponCountsDetailed)
            ..[restaurantId] = _CouponCounts(
              total: current.total,
              issued: current.issued - 1,
            );
    });
  }

  void _handleRewardCouponsIssued(List<String> couponCodes, int restaurantId) {
    final issuedCount =
        couponCodes.where((code) => code.trim().isNotEmpty).length;
    if (issuedCount <= 0) return;
    final current = _couponCountsDetailed[restaurantId];
    setState(() {
      _couponCountsDetailed =
          Map<int, _CouponCounts>.from(_couponCountsDetailed)
            ..[restaurantId] = _CouponCounts(
              total: (current?.total ?? 0) + issuedCount,
              issued: (current?.issued ?? 0) + issuedCount,
            );
    });
  }

  Future<List<UserCoupon>> _fetchIssuedCouponsByRestaurant(
    int restaurantId,
  ) async {
    final coupons = await CouponService.fetchMyCoupons(
      status: CouponStatus.issued,
    );
    return coupons
        .where((coupon) => coupon.restaurantId == restaurantId)
        .toList();
  }

  Future<void> _openRestaurantDetail(
      AffiliateRestaurantSummary restaurant) async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);

    bool requiresLogin = false;
    List<UserCoupon> coupons = const <UserCoupon>[];
    StampStatus? initialStampStatus = _stampStatuses[restaurant.id];

    try {
      try {
        coupons = await _fetchIssuedCouponsByRestaurant(restaurant.id);
      } on ApiAuthException {
        requiresLogin = true;
      } on ApiHttpException {
        // 상세 시트는 열고 쿠폰 정보만 비운다.
      } on ApiNetworkException {
        // 상세 시트는 열고 쿠폰 정보만 비운다.
      }

      if (!requiresLogin && initialStampStatus == null && restaurant.id != 0) {
        try {
          initialStampStatus =
              await CouponService.fetchStampStatus(restaurantId: restaurant.id);
        } on ApiAuthException {
          requiresLogin = true;
        } catch (_) {}
      }

      if (!mounted) return;
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
            coupons: coupons,
            requiresLogin: requiresLogin,
            source: 'favorite_restaurants',
            isFavorite: _favoriteIds.contains(restaurant.id),
            onFavoriteChanged: (isFavorite) {
              _toggleFavorite(restaurant);
            },
            initialStampStatus: initialStampStatus,
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
      } else {
        _isOpeningDetail = false;
      }
    }
  }

  List<AffiliateRestaurantSummary> get _filteredRestaurants {
    final categoryFiltered = _selectedCategory == 'ALL'
        ? _restaurants
        : _restaurants
            .where((restaurant) =>
                _normalizedCategoryForState(restaurant.category) ==
                _selectedCategory)
            .toList();
    final normalizedQuery = _normalizeForSearch(_searchQuery);
    if (normalizedQuery.isEmpty) return categoryFiltered;

    final scored = <MapEntry<AffiliateRestaurantSummary, int>>[];
    for (final restaurant in categoryFiltered) {
      final score = _searchMatchScore(restaurant.name, normalizedQuery);
      if (score != null) {
        scored.add(MapEntry(restaurant, score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = a.value.compareTo(b.value);
      if (scoreCompare != 0) return scoreCompare;
      return a.key.name.compareTo(b.key.name);
    });

    return scored.map((entry) => entry.key).toList();
  }

  List<GeneralRestaurantSummary> get _filteredGeneralRestaurants {
    final categoryFiltered = _selectedCategory == 'ALL'
        ? _generalRestaurants
        : _generalRestaurants
            .where((restaurant) =>
                _normalizedCategoryForState(restaurant.category) ==
                _selectedCategory)
            .toList();
    final normalizedQuery = _normalizeForSearch(_searchQuery);
    if (normalizedQuery.isEmpty) return categoryFiltered;

    final scored = <MapEntry<GeneralRestaurantSummary, int>>[];
    for (final restaurant in categoryFiltered) {
      final score = _searchMatchScore(restaurant.name, normalizedQuery);
      if (score != null) {
        scored.add(MapEntry(restaurant, score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = a.value.compareTo(b.value);
      if (scoreCompare != 0) return scoreCompare;
      return a.key.name.compareTo(b.key.name);
    });

    return scored.map((entry) => entry.key).toList();
  }

  String _normalizeForSearch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), '').trim();
  }

  int? _searchMatchScore(String restaurantName, String normalizedQuery) {
    final normalizedName = _normalizeForSearch(restaurantName);
    if (normalizedName.isEmpty) return null;

    if (normalizedName == normalizedQuery) return 0;
    if (normalizedName.startsWith(normalizedQuery)) return 10;
    if (normalizedName.contains(normalizedQuery)) return 20;

    var wordPrefixMatched = false;
    final queryLen = normalizedQuery.length;
    final words = restaurantName
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(_normalizeForSearch);
    for (final word in words) {
      if (word.startsWith(normalizedQuery)) {
        wordPrefixMatched = true;
        break;
      }
    }
    if (wordPrefixMatched) return 30;

    final fullPrefix = normalizedName.length >= queryLen
        ? normalizedName.substring(0, queryLen)
        : normalizedName;
    final baseTolerance = queryLen <= 3 ? 1 : 2;
    final fullDistance = _levenshteinDistance(normalizedQuery, fullPrefix);
    if (fullDistance <= baseTolerance) return 40 + fullDistance;

    var bestWordDistance = 999;
    for (final word in words) {
      final wordPrefix =
          word.length >= queryLen ? word.substring(0, queryLen) : word;
      final distance = _levenshteinDistance(normalizedQuery, wordPrefix);
      if (distance < bestWordDistance) {
        bestWordDistance = distance;
      }
    }
    if (bestWordDistance <= 1) return 50 + bestWordDistance;
    return null;
  }

  int _levenshteinDistance(String a, String b) {
    final aLen = a.length;
    final bLen = b.length;
    if (aLen == 0) return bLen;
    if (bLen == 0) return aLen;
    var previous = List<int>.generate(bLen + 1, (i) => i);
    var current = List<int>.filled(bLen + 1, 0);
    for (var i = 1; i <= aLen; i++) {
      current[0] = i;
      for (var j = 1; j <= bLen; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;
        current[j] = math.min(math.min(deletion, insertion), substitution);
      }
      final temp = previous;
      previous = current;
      current = temp;
    }
    return previous[bLen];
  }

  String _normalizeCategoryKey(String category) {
    final normalized = category.trim().toUpperCase();
    return _kCategoryAlias[normalized] ??
        _kCategoryAlias[category.trim()] ??
        normalized;
  }

  int _categoryOrderIndex(String category) {
    final normalized = _normalizeCategoryKey(category);
    final index = _kCategoryOrder.indexOf(normalized);
    return index == -1 ? _kCategoryOrder.length : index;
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
    if (meta != null) return meta;
    final trimmed = category.trim();
    return _CategoryMeta(
        trimmed.isEmpty ? '기타' : trimmed, _kCategoryMeta['ALL']!.assetPath);
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      backgroundColor: const Color(0xFF172133),
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.white,
      title: const Text(
        '찜한 식당',
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
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
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
          color: const Color(0xFF6366F1),
          backgroundColor: Colors.white,
          strokeWidth: 2,
          onRefresh: _load,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 16, bottom: 140),
            children: [
              _buildSearchBar(),
              const SizedBox(height: 12),
              _buildCategoryFilter(),
              const SizedBox(height: 12),
              if (_isLoading || _isSearching)
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
              else if (_filteredRestaurants.isEmpty &&
                  _filteredGeneralRestaurants.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _normalizeForSearch(_searchQuery).isEmpty
                          ? '찜한 식당이 없습니다.'
                          : '검색 결과가 없어요.',
                    ),
                  ),
                )
              else ...[
              if (_filteredRestaurants.isNotEmpty) ...[
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
                ..._filteredRestaurants.map((restaurant) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildRestaurantCard(restaurant),
                  );
                }),
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
                ..._filteredGeneralRestaurants.map((restaurant) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildGeneralRestaurantCard(restaurant),
                  );
                }),
              ],
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
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
    if (_categories.isEmpty) return const SizedBox.shrink();
    const double scale = 1.00;
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
            onTap: () {
              if (_selectedCategory == category) return;
              setState(() => _selectedCategory = category);
            },
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
                  horizontal: 6 * scale, vertical: 8 * scale),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Image.asset(meta.assetPath, fit: BoxFit.contain),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(meta.label,
                      style: textStyle, textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRestaurantCard(AffiliateRestaurantSummary restaurant) {
    final hasImage = restaurant.imageUrls.isNotEmpty;
    final thumbnailUrl = hasImage ? restaurant.imageUrls.first : null;
    final isLiked = _favoriteIds.contains(restaurant.id);
    final couponCounts = _couponCountsDetailed[restaurant.id];
    final stampStatus = _stampStatuses[restaurant.id];
    final stampCurrent =
        stampStatus != null ? stampStatus.current : restaurant.stampCurrent;
    final stampTarget =
        stampStatus != null ? stampStatus.target : restaurant.stampTarget;
    final stampLabel = _requiresLogin
        ? '스탬프 확인은 로그인 필요'
        : (stampTarget > 0
            ? '스탬프 $stampCurrent/$stampTarget'
            : (stampCurrent > 0 ? '스탬프 $stampCurrent개' : '스탬프 적립 없음'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openRestaurantDetail(restaurant),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFDDDDDD)),
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
                            errorBuilder: (_, __, ___) => const Icon(
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
                            onPressed: () => _toggleFavorite(restaurant),
                            splashRadius: 18,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 20,
                              color: isLiked
                                  ? const Color(0xFFE11D48)
                                  : const Color(0xFF9CA3AF),
                            ),
                            tooltip: isLiked ? '찜 해제' : '찜하기',
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
      ),
    );
  }

  Widget _buildGeneralRestaurantCard(GeneralRestaurantSummary restaurant) {
    final isLiked =
        _favoriteGeneralKeys.contains(_generalFavoriteKey(restaurant));
    final hasUrl = restaurant.url.trim().isNotEmpty;
    final categoryLabel = _resolveCategoryMeta(restaurant.category).label;
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
                  onPressed: () => _toggleGeneralFavorite(restaurant),
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
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        _showSnack('링크를 열 수 없어요.');
      }
    } catch (_) {
      _showSnack('링크를 열 수 없어요.');
    }
  }

  void _showSnack(String message) {
    if (!mounted || message.isEmpty) return;
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
      couponText = '사용 가능 쿠폰 ${couponCounts.issued}/${couponCounts.total}';
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
          SvgPicture.asset(
            'assets/images/coupon.svg',
            width: 12,
            height: 12,
            fit: BoxFit.contain,
            colorFilter:
                const ColorFilter.mode(Color(0xFF1F2937), BlendMode.srcIn),
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
