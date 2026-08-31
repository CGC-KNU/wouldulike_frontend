import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:new1/widgets/coupon_ticket_card.dart';
import 'package:new1/widgets/stamp_asset_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';

import 'models/coupon_benefits_summary.dart';
import 'services/demo_wallet.dart';
import 'services/affiliate_service.dart';
import 'services/api_client.dart';
import 'services/app_config_service.dart';
import 'services/coupon_service.dart';
import 'services/favorites_service.dart';
import 'widgets/network_thumb.dart';
import 'coupon/redeem_pin_dialog.dart';
import 'widgets/coupon_issued_dialog.dart';
import 'services/deep_link_service.dart';
import 'services/master_content.dart';
import 'widgets/restaurant_coupon_benefits_content.dart';

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
  const AffiliateBenefitsScreen({
    super.key,
    this.appBarTitle,
    this.lockFavoritesOnly = false,
  });

  /// null이면 메인 탭용(투명·타이틀 없음), 값이 있으면 뒤로가기 있는 일반 화면으로 표시.
  final String? appBarTitle;

  /// true면 '찜한 식당만' 필터를 항상 켜 둔 채로 고정한다 (마이페이지 '찜한 식당' 진입용).
  final bool lockFavoritesOnly;

  @override
  State<AffiliateBenefitsScreen> createState() =>
      _AffiliateBenefitsScreenState();
}

class _CategoryMeta {
  const _CategoryMeta(this.label, this.assetPath);

  final String label;
  final String assetPath;
}

/// 정렬 기준. 이전 '추천순'은 서버 응답 순서를 그대로 쓰는 것뿐이라 기준이 없어 걷어냈다.
/// 거리·평점 데이터가 API에 없으므로, 앱이 실제로 가진 값(보유 쿠폰·스탬프)으로만 정의한다.
/// 브랜드 테마 팔레트. 식당 탭 전반(스탬프·CTA·배지)을 이 색으로 통일한다.
class _Theme {
  static const deep = Color(0xFF312E81); // 강조/CTA
  static const primary = Color(0xFF4F46E5); // 기본 인디고
  static const light = Color(0xFF7C64EE); // 그라데이션 끝
  static const soft = Color(0xFFEEF0FF); // 배경 톤
  static const border = Color(0xFFC7CCFF); // 강조 테두리
  static const track = Color(0xFFE7E9F5); // 미적립 도트
}

/// 찜한 일반 식당을 구분하는 키. id가 없으면 url, 그것도 없으면 이름+주소로 떨어진다.
String generalRestaurantFavoriteKey(GeneralRestaurantSummary restaurant) {
  if (restaurant.id > 0) {
    return 'id:${restaurant.id}';
  }
  final normalizedUrl = restaurant.url.trim();
  if (normalizedUrl.isNotEmpty) {
    return 'url:$normalizedUrl';
  }
  return 'name:${restaurant.name.trim()}|addr:${restaurant.address.trim()}';
}

/// 찜한 일반 식당 목록 병합.
/// 일반 식당은 20개씩 페이징이라 찜한 곳이 아직 로드되지 않았을 수 있다.
/// 로드된 목록에 있으면 그 값을, 없으면 찜할 때 저장해 둔 스냅샷을 쓴다.
List<GeneralRestaurantSummary> mergeFavoriteGeneralRestaurants({
  required List<GeneralRestaurantSummary> loaded,
  required Set<String> favoriteKeys,
  required Map<String, dynamic> snapshots,
}) {
  final byKey = <String, GeneralRestaurantSummary>{};
  for (final restaurant in loaded) {
    final key = generalRestaurantFavoriteKey(restaurant);
    if (favoriteKeys.contains(key)) {
      byKey[key] = restaurant;
    }
  }
  for (final key in favoriteKeys) {
    if (byKey.containsKey(key)) continue;
    final raw = snapshots[key];
    if (raw is Map) {
      try {
        byKey[key] = GeneralRestaurantSummary.fromJson(
          Map<String, dynamic>.from(raw),
        );
      } catch (_) {}
    }
  }
  return byKey.values.toList();
}

String _categoryKeyOf(String category) {
  return MasterContent.normalize(category, unknownAsEtc: false);
}

enum _RestaurantSort {
  benefit('받은 혜택 많은 순'),
  stampSoon('스탬프 적립 임박순'),
  name('이름순');

  const _RestaurantSort(this.label);

  final String label;
}

class _CouponCounts {
  final int issued;
  final int redeemed;

  const _CouponCounts({required this.issued, required this.redeemed});

  int get total => issued + redeemed;
}

class _StampAddRequest {
  const _StampAddRequest({
    required this.pin,
    required this.count,
  });

  final String pin;
  final int count;
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
  // 필터/정렬: 거리·영업시간 데이터가 API에 없어 쿠폰·스탬프 보유 여부로만 거른다.
  bool _couponOnly = false;
  bool _stampOnly = false;

  /// 정렬 드롭다운의 '찜한 식당만' 항목. 정렬이 아니라 필터라 별도 상태로 둔다.
  bool _favoriteOnly = false;
  _RestaurantSort _sortMode = _RestaurantSort.benefit;
  List<String> _categories = const ['ALL'];
  bool _isOpeningDetail = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  /// 스크롤을 내리면 카테고리 줄을 접어 카드가 더 보이게 한다.
  bool _categoryCollapsed = false;
  Set<int> _favoriteAffiliateRestaurantIds = <int>{};
  Set<String> _favoriteGeneralRestaurantKeys = <String>{};

  /// 찜한 일반 식당의 저장본(key → 식당 JSON).
  /// 일반 식당 목록은 20개씩 페이징이라, 아직 로드되지 않은 찜도 '찜한 식당만'에서 보이게 하려고 쓴다.
  Map<String, dynamic> _favoriteGeneralSnapshots = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    if (widget.lockFavoritesOnly) {
      _favoriteOnly = true;
    }
    _scrollController.addListener(_handleScroll);
    _searchFocusNode.addListener(() => setState(() {}));
    DeepLinkService.instance.pendingRestaurantId
        .addListener(_handleDeepLinkRestaurant);
    _load();
  }

  @override
  void dispose() {
    DeepLinkService.instance.pendingRestaurantId
        .removeListener(_handleDeepLinkRestaurant);
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleDeepLinkRestaurant() {
    final id = DeepLinkService.instance.pendingRestaurantId.value;
    if (id == null) return;
    final restaurant =
        _affiliateRestaurants.where((r) => r.id == id).firstOrNull;
    if (restaurant == null) {
      // 로딩이 완료됐는데도 없으면 해당 식당이 목록에 없는 것이므로 pending 값 초기화
      if (!_isLoading)
        DeepLinkService.instance.pendingRestaurantId.value = null;
      return;
    }
    DeepLinkService.instance.pendingRestaurantId.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openRestaurantDetail(restaurant);
    });
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
        final shuffledAffiliate =
            List<AffiliateRestaurantSummary>.from(affiliateRestaurants);
        shuffledAffiliate.shuffle(math.Random());
        final shuffledGeneral =
            List<GeneralRestaurantSummary>.from(generalRestaurants);
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
        _favoriteGeneralSnapshots = favoriteState.$3;
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
        _handleDeepLinkRestaurant();
      }
    }
  }

  Future<(Set<int>, Set<String>, Map<String, dynamic>)>
      _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    final remoteIds = await FavoritesService.loadIds();
    final rawAffiliate =
        prefs.getStringList(_kFavoriteAffiliateRestaurantIdsKey) ??
            const <String>[];
    final rawGeneral =
        prefs.getStringList(_kFavoriteGeneralRestaurantKeysKey) ??
            const <String>[];
    final affiliateIds = {
      ...rawAffiliate
          .map((value) => int.tryParse(value))
          .whereType<int>(),
      ...remoteIds,
    };
    final generalKeys = rawGeneral
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final snapshots = <String, dynamic>{};
    final rawItems = prefs.getString(_kFavoriteGeneralRestaurantItemsKey);
    if (rawItems != null && rawItems.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawItems);
        if (decoded is Map<String, dynamic>) {
          snapshots.addAll(decoded);
        }
      } catch (_) {}
    }
    return (affiliateIds, generalKeys, snapshots);
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

  String _generalRestaurantFavoriteKey(GeneralRestaurantSummary restaurant) =>
      generalRestaurantFavoriteKey(restaurant);

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
    await FavoritesService.setFavorite(restaurantId, isFavorite);
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
    if (restaurant.id > 0) {
      await FavoritesService.setFavorite(restaurant.id, isFavorite);
    }
    if (mounted) {
      setState(() => _favoriteGeneralSnapshots = snapshots);
    }
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
      couponBenefitsSummary: restaurant.couponBenefitsSummary,
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

  bool get _hasBenefitFilter => _couponOnly || _stampOnly;

  /// 지금 이 매장에서 쓸 수 있는 쿠폰 수 (발급 상태)
  int _usableCouponCount(int restaurantId) =>
      _couponCountsDetailed[restaurantId]?.issued ?? 0;

  /// 지금 이 매장에서 스탬프를 적립 중인지 (한 개 이상 찍었는지).
  /// 스탬프 제도를 운영하는 매장 전체가 아니라, 실제로 사용자가 적립을
  /// 시작한 매장만 골라야 "스탬프" 필터가 의미가 있다.
  bool _isEarningStamp(AffiliateRestaurantSummary restaurant) {
    final current = _stampStatuses[restaurant.id]?.current ?? restaurant.stampCurrent;
    return current > 0;
  }

  /// 다음 보상까지 남은 스탬프. 스탬프가 없는 매장은 뒤로 밀리도록 큰 값.
  int _stampsToReward(AffiliateRestaurantSummary restaurant) {
    final status = _stampStatuses[restaurant.id];
    final target = status?.target ?? restaurant.stampTarget;
    final current = status?.current ?? restaurant.stampCurrent;
    if (target <= 0) return 1 << 20;
    final remain = target - current;
    return remain <= 0 ? 0 : remain;
  }

  void _sortAffiliates(List<AffiliateRestaurantSummary> list) {
    switch (_sortMode) {
      case _RestaurantSort.benefit:
        list.sort((a, b) {
          final byCoupon =
              _usableCouponCount(b.id).compareTo(_usableCouponCount(a.id));
          if (byCoupon != 0) return byCoupon;
          final byStamp = _stampsToReward(a).compareTo(_stampsToReward(b));
          if (byStamp != 0) return byStamp;
          return a.name.compareTo(b.name);
        });
      case _RestaurantSort.stampSoon:
        list.sort((a, b) {
          final byStamp = _stampsToReward(a).compareTo(_stampsToReward(b));
          if (byStamp != 0) return byStamp;
          return a.name.compareTo(b.name);
        });
      case _RestaurantSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
  }

  List<AffiliateRestaurantSummary> get _filteredAffiliateRestaurants {
    var list = _selectedCategory == 'ALL'
        ? List<AffiliateRestaurantSummary>.from(_affiliateRestaurants)
        : _affiliateRestaurants
            .where(
              (restaurant) =>
                  _normalizedCategoryForState(restaurant.category) ==
                  _selectedCategory,
            )
            .toList();
    if (_favoriteOnly) {
      list = list.where((r) => _isFavoriteAffiliateRestaurant(r.id)).toList();
    }
    if (_couponOnly) {
      list = list.where((r) => _usableCouponCount(r.id) > 0).toList();
    }
    if (_stampOnly) {
      list = list.where(_isEarningStamp).toList();
    }
    _sortAffiliates(list);
    return list;
  }

  /// 찜한 일반 식당 목록.
  /// 로드된 페이지에 없는 찜은 저장해 둔 스냅샷으로 되살려, 스크롤 위치와 무관하게 전부 보이게 한다.
  List<GeneralRestaurantSummary> get _favoriteGeneralRestaurants =>
      mergeFavoriteGeneralRestaurants(
        loaded: _generalRestaurants,
        favoriteKeys: _favoriteGeneralRestaurantKeys,
        snapshots: _favoriteGeneralSnapshots,
      );

  List<GeneralRestaurantSummary> get _filteredGeneralRestaurants {
    // 쿠폰·스탬프 필터가 켜지면 일반 식당은 해당 혜택이 없으므로 숨긴다.
    if (_hasBenefitFilter) return const [];
    if (_favoriteOnly) {
      final favorites = _selectedCategory == 'ALL'
          ? _favoriteGeneralRestaurants
          : _favoriteGeneralRestaurants
              .where(
                (restaurant) =>
                    _normalizedCategoryForState(restaurant.category) ==
                    _selectedCategory,
              )
              .toList();
      favorites.sort((a, b) => a.name.compareTo(b.name));
      return favorites;
    }
    final list = _selectedCategory == 'ALL'
        ? List<GeneralRestaurantSummary>.from(_generalRestaurants)
        : _generalRestaurants
            .where(
              (restaurant) =>
                  _normalizedCategoryForState(restaurant.category) ==
                  _selectedCategory,
            )
            .toList();
    // 일반 식당은 쿠폰·스탬프 데이터가 없어 정렬 기준과 무관하게 이름순으로 고정한다.
    // (이름순이 아닐 때 정렬을 건너뛰면 로드 시 섞인 순서가 그대로 남아,
    //  정렬 드롭다운을 바꿔도 목록 순서가 바뀌지 않는 것처럼 보였다.)
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.affiliateCategoryClick,
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
      _load().then((_) => _logSearchSubmit(value));
    });
  }

  void _handleSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = value);
    _load().then((_) => _logSearchSubmit(value));
  }

  /// 확정된 검색어를 결과 수와 함께 남긴다.
  ///
  /// 결과 0건인 검색어 목록이 곧 "학생들이 찾는데 우리에게 없는 매장" —
  /// 제휴 확장의 근거가 된다. 자유 입력이라 앞뒤 공백을 떼고 40자로 자른다.
  void _logSearchSubmit(String rawKeyword) {
    if (!mounted) return;
    final keyword = rawKeyword.trim();
    if (keyword.isEmpty) return;
    final affiliateCount = _filteredAffiliateRestaurants.length;
    final resultCount = affiliateCount + _filteredGeneralRestaurants.length;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantSearchSubmit,
      parameters: {
        AnalyticsEvents.paramKeyword:
            keyword.length > 40 ? keyword.substring(0, 40) : keyword,
        AnalyticsEvents.paramResultCount: resultCount,
        AnalyticsEvents.paramHasResult: resultCount > 0,
        'affiliate_count': affiliateCount,
      },
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // 히스테리시스: 접힘 80px / 펼침 40px — 경계에서 떨리지 않게 한다.
    final shouldCollapse =
        _categoryCollapsed ? position.pixels > 40 : position.pixels > 80;
    if (shouldCollapse != _categoryCollapsed) {
      setState(() => _categoryCollapsed = shouldCollapse);
    }
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
    final index = MasterContent.stripOrder.indexOf(normalized);
    return index == -1 ? MasterContent.stripOrder.length : index;
  }

  String _normalizeCategoryKey(String category) => _categoryKeyOf(category);

  String _normalizedCategoryForState(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return '';
    final key = _normalizeCategoryKey(trimmed);
    if (MasterContent.knownCodes.contains(key)) {
      return key;
    }
    return trimmed;
  }

  _CategoryMeta _resolveCategoryMeta(String category) {
    final key = _normalizeCategoryKey(category);
    if (MasterContent.knownCodes.contains(key)) {
      return _CategoryMeta(
        MasterContent.labelOf(key),
        MasterContent.svgOf(key),
      );
    }
    final trimmed = category.trim();
    final label = trimmed.isEmpty ? '기타' : trimmed;
    return _CategoryMeta(label, MasterContent.svgOf('ALL'));
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
      AnalyticsEvents.affiliateRestaurantClick,
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
            source: 'affiliate_benefits',
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

    final appBar = widget.appBarTitle != null
        ? AppBar(
            backgroundColor: const Color(0xFF172133),
            elevation: 0,
            centerTitle: true,
            foregroundColor: Colors.white,
            title: Text(
              widget.appBarTitle!,
              style: const TextStyle(
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
          )
        : AppBar(
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
          child: CustomScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: _buildRestaurantSlivers(),
          ),
        ),
      ),
    );
  }

  Widget _buildRestaurantSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
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
            hintText: '식당·메뉴 검색',
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14.5,
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
                          onPressed: () => FocusScope.of(context).unfocus(),
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

  /// 필터·정렬 칩 줄.

  /// 식당 목록 슬리버.
  ///
  /// 예전에는 ListView(children: [...])로 카드를 한 번에 만들어서, 화면 밖 카드까지
  /// 곧바로 이미지 요청을 냈다. 목록이 길수록 동시 요청이 늘어 초기 진입이 느려진다.
  /// 카드 부분만 SliverList.builder로 바꿔 보이는 것부터 만든다.
  List<Widget> _buildRestaurantSlivers() {
    final affiliates = _filteredAffiliateRestaurants;
    final generals = _filteredGeneralRestaurants;
    final isEmpty = affiliates.isEmpty && generals.isEmpty;

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.only(top: 16),
        sliver: SliverList(
          delegate: SliverChildListDelegate.fixed([
            _buildRestaurantSearchBar(),
            const SizedBox(height: 14),
            _buildCategoryFilter(),
            const SizedBox(height: 12),
            _buildFilterChips(),
            if (_isLoading)
              _buildSkeletonList()
            else if (isEmpty)
              _buildEmptyState()
            else ...[
              if (_requiresLogin) _buildLoginBanner(),
              if (affiliates.isNotEmpty)
                _buildSectionHeader('내 혜택이 있는 곳', affiliates.length),
            ],
          ]),
        ),
      ),
      if (!_isLoading && affiliates.isNotEmpty)
        SliverList.builder(
          itemCount: affiliates.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _buildAffiliateRestaurantCard(affiliates[i]),
          ),
        ),
      if (!_isLoading && generals.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _buildSectionHeader('그 외 근처 식당', generals.length),
        ),
        // 예전 둥근 카드 묶음을 유지하되, 테두리를 항목마다 그려 지연 빌드가 되게 한다.
        SliverList.builder(
          itemCount: generals.length,
          itemBuilder: (context, i) =>
              _buildGeneralGroupItem(generals[i], i, generals.length),
        ),
      ],
      if (_isAppending)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 140)),
    ];
  }

  /// 둥근 묶음 안의 한 줄. 첫 줄만 위 모서리, 마지막 줄만 아래 모서리를 둥글린다.
  Widget _buildGeneralGroupItem(dynamic restaurant, int index, int total) {
    const line = Color(0xFFEDEFF3);
    final isFirst = index == 0;
    final isLast = index == total - 1;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: const BorderSide(color: line),
          right: const BorderSide(color: line),
          top: const BorderSide(color: line),
          bottom: isLast ? const BorderSide(color: line) : BorderSide.none,
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isFirst ? 16 : 0),
          bottom: Radius.circular(isLast ? 16 : 0),
        ),
      ),
      child: _buildGeneralRestaurantCard(restaurant),
    );
  }

  /// 거리(좌표)와 영업시간 필드가 API에 없어 "가까운 순 / 영업중"은 제외했습니다.
  Widget _buildFilterChips() {
    return SizedBox(
      height: 43,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip(
            label: '쿠폰',
            selected: _couponOnly,
            leading: 'assets/images/coupon.svg',
            onTap: () {
              AnalyticsLogger.logEvent(
                'affiliate_filter_click',
                parameters: {'filter': 'coupon_only', 'enabled': !_couponOnly},
              );
              setState(() => _couponOnly = !_couponOnly);
            },
          ),
          const SizedBox(width: 7),
          _buildFilterChip(
            label: '스탬프',
            selected: _stampOnly,
            leading: 'assets/images/medal.svg',
            onTap: () {
              AnalyticsLogger.logEvent(
                'affiliate_filter_click',
                parameters: {'filter': 'stamp_only', 'enabled': !_stampOnly},
              );
              setState(() => _stampOnly = !_stampOnly);
            },
          ),
          const SizedBox(width: 7),
          _buildSortDropdown(),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
    IconData? icon,
    String? leading,
    IconData? trailingIcon,
  }) {
    final Color foreground =
        selected ? _Theme.primary : const Color(0xFF4B5563);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: ShapeDecoration(
          color: selected ? _Theme.soft : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color: selected ? _Theme.border : const Color(0xFFE5E7EB),
            ),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              SvgPicture.asset(
                leading,
                width: 14,
                height: 14,
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
              ),
              const SizedBox(width: 5),
            ] else if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 2),
              Icon(trailingIcon, size: 16, color: foreground),
            ],
          ],
        ),
      ),
    );
  }

  /// 찜한 식당 수 (제휴 + 일반). 드롭다운 항목 옆 배지에 쓴다.
  int get _favoriteCount =>
      _favoriteAffiliateRestaurantIds.length +
      _favoriteGeneralRestaurantKeys.length;

  /// 정렬 선택. 칩 아래에 붙는 드롭다운 메뉴 (바텀시트 대신).
  /// 맨 위 '찜한 식당만'은 정렬이 아니라 필터라, 값 타입을 Object로 두고 분기한다.
  Widget _buildSortDropdown() {
    const favoriteMenuValue = 'favorite_only';
    return PopupMenuButton<Object>(
      offset: const Offset(0, 36),
      color: Colors.white,
      elevation: 3,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == favoriteMenuValue) {
          if (widget.lockFavoritesOnly) return;
          AnalyticsLogger.logEvent(
            'affiliate_filter_click',
            parameters: {
              'filter': 'favorite_only',
              'enabled': !_favoriteOnly,
            },
          );
          setState(() => _favoriteOnly = !_favoriteOnly);
          return;
        }
        if (value is! _RestaurantSort || value == _sortMode) return;
        AnalyticsLogger.logEvent(
          'affiliate_sort_click',
          parameters: {'sort': value.name},
        );
        setState(() => _sortMode = value);
      },
      itemBuilder: (context) => [
        if (!widget.lockFavoritesOnly) ...[
          PopupMenuItem<Object>(
            value: favoriteMenuValue,
            height: 42,
            child: Row(
              children: [
                Icon(
                  _favoriteOnly ? Icons.favorite_rounded : Icons.favorite_border,
                  size: 17,
                  color: _favoriteOnly
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '찜한 식당만',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          _favoriteOnly ? FontWeight.w700 : FontWeight.w500,
                      color: _favoriteOnly
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFF111827),
                    ),
                  ),
                ),
                if (_favoriteCount > 0)
                  Text(
                    '$_favoriteCount',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                if (_favoriteOnly) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_rounded,
                      size: 18, color: Color(0xFF4F46E5)),
                ],
              ],
            ),
          ),
          const PopupMenuDivider(height: 1),
        ],
        for (final mode in _RestaurantSort.values)
          PopupMenuItem<Object>(
            value: mode,
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          mode == _sortMode ? FontWeight.w700 : FontWeight.w500,
                      color: mode == _sortMode
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFF111827),
                    ),
                  ),
                ),
                if (mode == _sortMode)
                  const Icon(Icons.check_rounded,
                      size: 18, color: Color(0xFF4F46E5)),
              ],
            ),
          ),
      ],
      child: _buildFilterChip(
        label: !widget.lockFavoritesOnly && _favoriteOnly
            ? '찜한 식당만'
            : _sortMode.label,
        selected: (!widget.lockFavoritesOnly && _favoriteOnly) ||
            _sortMode != _RestaurantSort.benefit,
        trailingIcon: Icons.keyboard_arrow_down_rounded,
        onTap: null,
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4F46E5),
            ),
          ),
        ],
      ),
    );
  }

  /// 로딩 중에는 텍스트 대신 카드 골격을 먼저 그려 레이아웃이 튀지 않게 합니다.
  Widget _buildSkeletonList() {
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          padding: const EdgeInsets.all(12),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFEDEFF3)),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSkeletonBox(width: 86, height: 86, radius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSkeletonBox(width: 150, height: 16, radius: 8),
                    const SizedBox(height: 9),
                    _buildSkeletonBox(width: 96, height: 12, radius: 6),
                    const SizedBox(height: 13),
                    _buildSkeletonBox(width: 168, height: 21, radius: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonBox({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  /// 빈 상태는 원인(검색 / 카테고리 / 데이터 없음)에 따라 문구와 행동을 구분합니다.
  Widget _buildEmptyState() {
    final query = _searchQuery.trim();
    final hasQuery = _normalizeForSearch(_searchQuery).isNotEmpty;
    final isFiltered = _selectedCategory != 'ALL';

    final String title;
    final String description;
    if (hasQuery) {
      title = '‘$query’ 검색 결과가 없어요';
      description = '철자를 확인하거나\n다른 카테고리에서 찾아보세요';
    } else if (_favoriteOnly) {
      title = _favoriteCount == 0 ? '아직 찜한 식당이 없어요' : '조건에 맞는 찜한 식당이 없어요';
      description = _favoriteCount == 0
          ? '식당 카드의 하트를 눌러\n자주 가는 곳을 모아보세요'
          : '필터를 끄면 찜한 식당을\n모두 볼 수 있어요';
    } else if (_hasBenefitFilter) {
      title = _couponOnly && !_stampOnly
          ? '쓸 수 있는 쿠폰이 있는 식당이 없어요'
          : (!_couponOnly && _stampOnly
              ? '스탬프를 적립 중인 식당이 없어요'
              : '조건에 맞는 식당이 없어요');
      description = '필터를 끄면 근처 식당을\n모두 볼 수 있어요';
    } else if (isFiltered) {
      title = '${_resolveCategoryMeta(_selectedCategory).label} 식당이 아직 없어요';
      description = '다른 카테고리를 둘러보세요';
    } else {
      title = '표시할 식당이 없어요';
      description = '잠시 후 다시 시도해 주세요';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 40),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: const Color(0xFFEEF0FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 40,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: Color(0xFF6B7280),
            ),
          ),
          if (hasQuery ||
              isFiltered ||
              _hasBenefitFilter ||
              (!widget.lockFavoritesOnly && _favoriteOnly)) ...[
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  if (hasQuery) {
                    _searchController.clear();
                    _handleSearchSubmitted('');
                  }
                  if (_hasBenefitFilter ||
                      (!widget.lockFavoritesOnly && _favoriteOnly)) {
                    setState(() {
                      _couponOnly = false;
                      _stampOnly = false;
                      if (!widget.lockFavoritesOnly) _favoriteOnly = false;
                    });
                  }
                  if (isFiltered) {
                    _selectCategory('ALL');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF172133),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text(
                  '전체 식당 보기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 비로그인 안내는 카드마다 반복하지 않고 목록 상단 배너 하나로 모읍니다.
  Widget _buildLoginBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: const Color(0xFF172133),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '로그인하고 스탬프 모으기',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 5),
          Text(
            '쿠폰 발급과 스탬프 적립은 로그인 후 이용할 수 있어요',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xB3FFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  /// 카테고리 줄: 회색 박스 대신 컬러 일러스트 + 라벨.
  /// 컬러 일러스트는 틴트(colorFilter)가 불가능하므로 선택 상태는 링 + 라벨 볼드로 표시합니다.
  Widget _buildCategoryFilter() {
    if (_categories.isEmpty) {
      return const SizedBox.shrink();
    }
    // 스크롤 시 58 → 40px로 줄여 첫 화면에 카드가 더 들어오게 한다.
    final collapsed = _categoryCollapsed;
    final double circle = collapsed ? 40 : 58;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: collapsed ? 64 : 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          final meta = _resolveCategoryMeta(category);

          return InkWell(
            onTap: () => _selectCategory(category),
            borderRadius: BorderRadius.circular(30),
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: circle,
                    height: circle,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? _Theme.soft : Colors.transparent,
                      border: Border.all(
                        color: selected ? _Theme.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: SvgPicture.asset(
                      meta.assetPath,
                      width: circle - 8,
                      height: circle - 8,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    meta.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? _Theme.deep : const Color(0xFF6B7280),
                      fontSize: 11.5,
                      fontFamily: 'Pretendard',
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
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
        stampStatus != null ? stampStatus.boardLength : restaurant.stampTarget;
    final isFavorite = _isFavoriteAffiliateRestaurant(restaurant.id);
    final categoryLabel = _resolveCategoryMeta(
      _normalizedCategoryForState(restaurant.category),
    ).label;
    final locationLabel = restaurant.zone.trim().isNotEmpty
        ? restaurant.zone.trim()
        : restaurant.address.trim();
    final metaLabel = [categoryLabel, locationLabel]
        .where((value) => value.isNotEmpty)
        .join(' · ');

    // 혜택이 있을 때만 배지를 노출합니다. ("보유 쿠폰 없음" 같은 배지는 노이즈)
    final badges = <Widget>[];
    if (_requiresLogin) {
      badges.add(_buildNeutralTag('로그인하면 쿠폰·스탬프 표시'));
    } else {
      if (couponCounts != null && couponCounts.issued > 0) {
        badges.add(_buildCouponTag(couponCounts.issued));
      }
      // 스탬프는 아래 도트 게이지가 대신 보여준다. 목표가 없을 때만 배지로 표기.
      if (stampTarget <= 0 && stampCurrent > 0) {
        badges.add(_buildStampTag('스탬프 $stampCurrent개'));
      }
    }

    final showStampProgress = !_requiresLogin && stampTarget > 0;
    final remainingStamp = stampStatus != null
        ? stampStatus.remainingToNextReward
        : stampTarget - stampCurrent;
    // 리워드 달성 / 임박(1~2개 남음)은 카드 자체를 테마색으로 띄운다.
    final rewardReady = showStampProgress && remainingStamp <= 0;
    final rewardSoon =
        showStampProgress && remainingStamp > 0 && remainingStamp <= 2;
    final highlighted = rewardReady || rewardSoon;

    return InkWell(
      onTap: () => _openRestaurantDetail(restaurant),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: highlighted ? 1.4 : 1,
              color: highlighted ? _Theme.border : const Color(0xFFEDEFF3),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          shadows: [
            BoxShadow(
              color: highlighted
                  ? const Color(0x2E4F46E5)
                  : const Color(0x0D101828),
              blurRadius: highlighted ? 12 : 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAffiliateThumbnail(thumbnailUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    restaurant.name.isNotEmpty
                                        ? restaurant.name
                                        : '매장 정보를 찾을 수 없어요',
                                    style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                      color: Color(0xFF111827),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (rewardSoon) ...[
                                  const SizedBox(width: 6),
                                  _buildRewardRibbon('$remainingStamp개 남음'),
                                ] else if (rewardReady) ...[
                                  const SizedBox(width: 6),
                                  _buildRewardRibbon('리워드 준비 완료'),
                                ],
                              ],
                            ),
                            if (metaLabel.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                metaLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _buildFavoriteButton(
                        isFavorite: isFavorite,
                        onPressed: () =>
                            _toggleFavoriteAffiliateRestaurant(restaurant.id),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Wrap(spacing: 5, runSpacing: 5, children: badges),
                  ],
                  if (showStampProgress) ...[
                    const SizedBox(height: 9),
                    _buildStampGauge(
                      current: stampCurrent,
                      target: stampTarget,
                    ),
                  ],
                  // 쿠폰 사용은 상세에서만 한다. 카드에는 리워드 수령만 노출.
                  if (rewardReady)
                    _buildCardCta(
                      label: '리워드 받기',
                      filled: true,
                      onTap: () => _openRestaurantDetail(restaurant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 스탬프 게이지. 목표가 12개를 넘으면 도트가 뭉개지므로 진행바로 대체한다.
  Widget _buildStampGauge({required int current, required int target}) {
    final filled = current.clamp(0, target);
    final ready = current >= target;
    final label = ready ? '리워드 준비 완료' : '$filled/$target';

    if (target > 12) {
      return Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (current / target).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: _Theme.track,
                valueColor: const AlwaysStoppedAnimation<Color>(_Theme.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _Theme.deep,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < target; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _StampDot(
            filled: i < filled,
            isGoal: i == target - 1,
            ready: ready,
          ),
        ],
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: _Theme.deep,
          ),
        ),
      ],
    );
  }

  /// 카드 안 행동 버튼. 리워드 수령은 채움, 쿠폰 사용은 외곽선.
  Widget _buildCardCta({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: ShapeDecoration(
            gradient: filled
                ? const LinearGradient(
                    colors: [_Theme.deep, _Theme.light],
                  )
                : null,
            color: filled ? null : Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: filled ? Colors.transparent : _Theme.border,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: filled ? Colors.white : _Theme.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// 리워드 임박·달성 라벨
  Widget _buildRewardRibbon(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _Theme.soft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: _Theme.deep,
        ),
      ),
    );
  }

  Widget _buildAffiliateThumbnail(String? thumbnailUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 86,
        height: 86,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkThumb(
              url: thumbnailUrl,
              width: 86,
              height: 86,
            ),
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: ShapeDecoration(
                  color: const Color(0xE0172133),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: const Text(
                  '제휴',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 찜 버튼: 최소 터치 영역 44×44 확보 (iOS HIG / Material 기준)
  Widget _buildFavoriteButton({
    required bool isFavorite,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 22,
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 21,
          color: isFavorite ? const Color(0xFFE11D48) : const Color(0xFFC9CED8),
        ),
        tooltip: isFavorite ? '찜 해제' : '찜하기',
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

    final categoryIcon =
        _resolveCategoryMeta(_normalizedCategoryForState(restaurant.category))
            .assetPath;

    return InkWell(
      onTap: hasUrl ? () => _openGeneralRestaurantUrl(restaurant.url) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            SvgPicture.asset(categoryIcon, width: 52, height: 52),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    restaurant.name.isNotEmpty
                        ? restaurant.name
                        : '매장 정보를 찾을 수 없어요',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xFFF4F5F7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          categoryLabel,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                    ],
                  ),
                ],
              ),
            ),
            _buildFavoriteButton(
              isFavorite: isLiked,
              onPressed: () => _toggleFavoriteGeneralRestaurant(restaurant),
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

  Widget _buildCouponTag(int issuedCount) {
    return _buildBadge(
      label: '쿠폰 $issuedCount장',
      background: const Color(0xFFEEF0FF),
      foreground: const Color(0xFF3730A3),
      leading: SvgPicture.asset(
        'assets/images/coupon.svg',
        width: 13,
        height: 13,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(Color(0xFF3730A3), BlendMode.srcIn),
      ),
    );
  }

  Widget _buildStampTag(String stampLabel) {
    return _buildBadge(
      label: stampLabel,
      background: _Theme.soft,
      foreground: _Theme.deep,
      leading: SvgPicture.asset(
        'assets/images/medal.svg',
        width: 13,
        height: 13,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(_Theme.deep, BlendMode.srcIn),
      ),
    );
  }

  /// 비로그인 등 "정보 없음" 상태는 경고(빨강)가 아니라 중립 회색으로 표시합니다.
  Widget _buildNeutralTag(String label) {
    return _buildBadge(
      label: label,
      background: const Color(0xFFF4F5F7),
      foreground: const Color(0xFF6B7280),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color background,
    required Color foreground,
    Widget? leading,
  }) {
    return Container(
      height: 23,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: ShapeDecoration(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: foreground,
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
    required this.source,
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
  final String source;
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
  late final DateTime _openedAt;
  late final String _detailSessionId;
  String _exitType = 'unknown';
  bool _isBenefitDetailExpanded = false;
  CouponBenefitsSummary? _couponBenefitsSummary;
  bool _isCouponBenefitsLoading = false;

  bool get _shouldShowBenefitDetailSection {
    if (_isCouponBenefitsLoading) return true;
    return _couponBenefitsSummary?.hasVisibleContent ?? false;
  }

  void _toggleBenefitDetailExpanded() {
    setState(() {
      _isBenefitDetailExpanded = !_isBenefitDetailExpanded;
    });
    _logDetailCta(
      _isBenefitDetailExpanded
          ? 'benefit_detail_expand'
          : 'benefit_detail_collapse',
    );
  }

  void _logDetailCta(
    String cta, {
    Map<String, Object?>? extra,
  }) {
    final params = <String, Object?>{
      AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
      AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
      AnalyticsEvents.paramDetailSessionId: _detailSessionId,
      AnalyticsEvents.paramSource: widget.source,
      AnalyticsEvents.paramCta: cta,
      ...?extra,
    };
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantDetailCtaClick,
      parameters: params,
    );
  }

  /// API rewards 또는 레거시 fallback에서 threshold별 혜택 문구 반환 (THRESHOLD 패턴용)

  /// 화면에 쓸 스탬프 현황. 개인 현황에 판 정보가 없으면 매장 공개 요약으로 채운다.
  StampStatus get _effectiveStampStatus => resolveStampStatus(
        personal: _stampStatus,
        // 목록 API 응답에는 coupon_benefits_summary 가 없어서
        // 상세 진입 시 따로 받아둔 요약(_couponBenefitsSummary)을 쓴다.
        summary:
            (_couponBenefitsSummary ?? widget.restaurant.couponBenefitsSummary)
                ?.stamp,
        fallbackCurrent: widget.restaurant.stampCurrent,
      );

  /// StampReward의 혜택 문구 (coupon_service의 공용 helper 사용)
  String _benefitTextFor(StampReward r) => stampRewardBenefitText(r);

  /// 현재 스탬프 수가 속한 구간의 혜택 (VISIT 패턴: 1~3개일 때 1~4 구간 혜택 표시 등)
  StampReward? _getCurrentReward() {
    final status = _effectiveStampStatus;
    final current = status.current;
    for (final r in status.visitRewards) {
      final min = r.minVisit ?? 0;
      final max = r.maxVisit;
      if (current >= min && (max == null || current <= max)) {
        return r;
      }
    }
    return null;
  }

  /// 앞으로 받을 수 있는 가장 가까운 혜택 (서버 rewards 기준)
  StampReward? _getNextReward() => _effectiveStampStatus.nextReward;

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

  /// 리워드가 걸린 칸 번호. 서버 rewards만 사용하고, 없으면 빈 목록.
  List<int> _stampThresholds() {
    final status = _effectiveStampStatus;
    final list = <int>{
      for (final r in status.thresholdRewards) r.stamps!,
      for (final r in status.visitRewards) r.minVisit!,
    }.toList()
      ..sort();
    return list;
  }

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _detailSessionId = const Uuid().v4();
    final prev = AnalyticsLogger.getRecentLastRestaurantDetail();
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantDetailOpen,
      parameters: {
        AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
        AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
        AnalyticsEvents.paramDetailSessionId: _detailSessionId,
        AnalyticsEvents.paramSource: widget.source,
        if (prev.restaurantId != null)
          AnalyticsEvents.paramPrevRestaurantId: prev.restaurantId,
        if (prev.source != null) AnalyticsEvents.paramPrevSource: prev.source,
      },
    );
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
    final hasEmptyRewards = hasInitialStatus &&
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

    _couponBenefitsSummary = widget.restaurant.couponBenefitsSummary;
    if (_couponBenefitsSummary == null &&
        (widget.restaurant.id > 0 ||
            widget.restaurant.name.trim().isNotEmpty)) {
      _isCouponBenefitsLoading = true;
      _loadCouponBenefitsSummary();
    }
  }

  Future<void> _loadCouponBenefitsSummary() async {
    final name = widget.restaurant.name.trim();
    final id = widget.restaurant.id;
    if (name.isEmpty && id <= 0) return;

    if (!_isCouponBenefitsLoading) {
      setState(() => _isCouponBenefitsLoading = true);
    }
    try {
      final detail = await AffiliateService.fetchRestaurantDetail(
        restaurantId: id > 0 ? id : null,
        name: name.isNotEmpty ? name : null,
      );
      if (!mounted) return;
      setState(() {
        _couponBenefitsSummary = detail?.couponBenefitsSummary;
        _isCouponBenefitsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCouponBenefitsLoading = false);
    }
  }

  void _toggleFavorite() {
    _logDetailCta(
      'favorite_toggle',
      extra: {
        AnalyticsEvents.paramAction: _isFavorite ? 'remove' : 'add',
      },
    );
    setState(() {
      _isFavorite = !_isFavorite;
    });
    widget.onFavoriteChanged(_isFavorite);
  }

  @override
  void dispose() {
    final durationMs = DateTime.now().difference(_openedAt).inMilliseconds;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.restaurantDetailClose,
      parameters: {
        AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
        AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
        AnalyticsEvents.paramDetailSessionId: _detailSessionId,
        AnalyticsEvents.paramSource: widget.source,
        AnalyticsEvents.paramDurationMs: durationMs,
        AnalyticsEvents.paramExitType: _exitType,
      },
    );
    AnalyticsLogger.markRestaurantDetailClosed(
      restaurantId: widget.restaurant.id,
      source: widget.source,
    );
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
    _logDetailCta('stamp_add');
    // 데모 빌드는 서버 PIN 검증이 없으므로 입력 단계를 건너뛴다.
    final request = kDemoWallet
        ? const _StampAddRequest(pin: 'demo', count: 1)
        : await _promptForStampAdd();
    if (request == null) return;

    setState(() {
      _isStampProcessing = true;
      _stampError = null;
    });
    final addResult = await CouponService.addStamp(
      restaurantId: widget.restaurant.id,
      pin: request.pin,
      count: request.count,
    );
    if (!mounted) return;
    if (!addResult.isSuccess) {
      final failureMessage = addResult.errorMessage ?? '요청이 실패했어요.';
      // 성공(stamp_issued)만 남기면 일일 한도·미방문으로 막힌 시도가 보이지 않는다.
      AnalyticsLogger.logEvent(
        AnalyticsEvents.stampAddFailed,
        parameters: {
          AnalyticsEvents.paramRestaurantId: widget.restaurant.id,
          AnalyticsEvents.paramRestaurantName: widget.restaurant.name,
          AnalyticsEvents.paramFailReason: addResult.errorCode ??
              (addResult.statusCode == 429
                  ? 'daily_limit'
                  : 'http_${addResult.statusCode ?? 0}'),
          AnalyticsEvents.paramCount: request.count,
        },
      );
      setState(() {
        _isStampProcessing = false;
        _stampError = failureMessage;
      });
      if (addResult.statusCode == 429 ||
          addResult.errorCode == 'stamp_daily_limit_reached') {
        await _showStampDailyLimitDialog(failureMessage);
      } else {
        // 성공은 팝업인데 실패만 조용하면 결과를 못 알아챈다. 같은 톤으로 맞춘다.
        final retry = await _showStampFailedDialog(failureMessage);
        if (retry == true && mounted) await _handleAddStamp();
      }
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
          AnalyticsEvents.paramStampAddedCount:
              (result.added > 0 ? result.added : request.count),
        },
      );
      await _applyStampAddSuccess(result, request.count);
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

    final now = AppConfigService.now();
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

  Future<void> _applyStampAddSuccess(
    StampActionResult result,
    int requestedCount,
  ) async {
    // result.status는 rewards, notes가 없으므로 재조회하여 전체 정보 갱신
    try {
      final fullStatus = await CouponService.fetchStampStatus(
        restaurantId: widget.restaurant.id,
      );
      if (!mounted) return;
      debugPrint(
        '[stamp] add ok r=${widget.restaurant.id} '
        'added=${result.added} '
        'after=${result.status.current}/${result.status.target} '
        'refetch=${fullStatus.current}/${fullStatus.target} '
        'rewards=${fullStatus.rewards.length}',
      );
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
    final addedCount = result.added > 0 ? result.added : requestedCount;
    final after = _stampStatus;
    final currentAfter = after?.current ?? result.status.current;
    // 최대 스탬프에 도달하면 서버가 리워드를 주고 판을 0으로 되돌린다.
    // 그대로 두면 "적립했는데 도장이 안 찍혔다"로 보이므로 따로 안내한다.
    // 재조회로 확인된 판이 있을 때만 "라운드 리셋"으로 본다.
    // 재조회가 0/0을 주면(비로그인·미운영) 리셋으로 오인해 "리워드 도착"이 뜬다.
    final cycleReset =
        (after?.boardLength ?? 0) > 0 && currentAfter < result.status.current;
    await _showStampStampedDialog(
      added: addedCount,
      current: currentAfter,
      total: after?.boardLength ?? result.status.target,
      cycleReset: cycleReset,
    );
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
          widget.onRewardCouponsIssued(newCoupons.map((c) => c.code).toList());
        }

        // 발급은 스낵바로 흘리지 않는다. 팝업 → 쿠폰함이 기본 동선.
        if (newCoupons.isNotEmpty) {
          await showCouponIssuedDialog(
            context,
            tag: '스탬프 리워드',
            title: newCoupons.length == 1
                ? '리워드 쿠폰 1장'
                : '리워드 쿠폰 ${newCoupons.length}장',
          );
        } else {
          _showSnack('보유 중인 리워드 쿠폰: ${rewardCodes.join(', ')}');
        }
      } catch (e) {
        // 쿠폰 목록을 가져오는 데 실패한 경우, 기존 방식대로 처리
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
                    issueKey: 'STAMP_REWARD:reward',
                  ),
                ),
              );
            _sortCoupons();
          });
          widget.onRewardCouponsIssued(newCodes);
        }
        if (newCodes.isNotEmpty) {
          await showCouponIssuedDialog(
            context,
            tag: '스탬프 리워드',
            title: newCodes.length == 1
                ? '리워드 쿠폰 1장'
                : '리워드 쿠폰 ${newCodes.length}장',
          );
        } else {
          _showSnack('보유 중인 리워드 쿠폰: ${rewardCodes.join(', ')}');
        }
      }
    }
  }

  Future<void> _handleRedeem(UserCoupon coupon) async {
    setState(() => _processingCouponCode = coupon.code);
    try {
      final outcome = await showCouponRedeemPinDialog(
        context: context,
        coupon: coupon,
        restaurantId: widget.restaurant.id,
        restaurantName: widget.restaurant.name,
        notes: coupon.benefit?.notesText,
        fromScreen: 'detail',
      );
      if (!mounted) return;
      if (outcome != null && outcome.redeemed) {
        setState(() {
          _coupons =
              _coupons.where((item) => item.code != coupon.code).toList();
        });
        widget.onCouponRedeemed(coupon.code);
        if (outcome.stampResult != null) {
          await _applyStampAddSuccess(
            outcome.stampResult!,
            outcome.stampCount,
          );
        } else if (outcome.stampError != null) {
          await _showStampFailedDialog(
            '쿠폰은 사용됐어요. 스탬프는 적립하지 못했어요.\n${outcome.stampError}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _processingCouponCode = null);
      }
    }
  }

  Future<_StampAddRequest?> _promptForStampAdd() async {
    final controller = TextEditingController();
    int selectedCount = 1;
    String? error;
    return showDialog<_StampAddRequest>(
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
                      const Text(
                        '스탬프 적립',
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
                        TextSpan(
                          text:
                              '스탬프를 적립하시겠습니까?\n\n적립 개수를 선택하고 관리자 비밀번호를 입력하시면\n\n스탬프 $selectedCount개가 적립됩니다.',
                          style: const TextStyle(
                            color: Color(0xFF39393E),
                            fontSize: 14,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w500,
                            height: 0.70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '적립 개수',
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
                        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedCount,
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(10),
                            dropdownColor: Colors.white,
                            style: const TextStyle(
                              color: Color(0xFF39393E),
                              fontSize: 16,
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                            ),
                            items: List.generate(
                              AppConfigService.stampMaxPerScan,
                              (index) => DropdownMenuItem<int>(
                                value: index + 1,
                                child: Text('${index + 1}개'),
                              ),
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                selectedCount = value;
                              });
                            },
                          ),
                        ),
                      ),
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
                          maxLength: AppConfigService.pinLength,
                          style: const TextStyle(
                            color: Color(0xFF39393E),
                            fontSize: 16,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(
                                AppConfigService.pinLength),
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
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                foregroundColor: const Color(0xFF39393E),
                                side:
                                    const BorderSide(color: Color(0xFFBABAC0)),
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
                                if (value.length != AppConfigService.pinLength) {
                                  setState(() {
                                    error =
                                        'PIN은 ${AppConfigService.pinLength}자리 숫자여야 합니다.';
                                  });
                                  return;
                                }
                                Navigator.of(dialogContext).pop(
                                  _StampAddRequest(
                                    pin: value,
                                    count: selectedCount,
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _Theme.deep,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
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
                              child: const Text('적립하기'),
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
    );
  }

  void _showSnack(String message) {
    // 모달 시트 내 SnackBar → Scaffold 레이아웃 충돌 발생. 스탬프/쿠폰 에러는 _stampError 등으로 표시
    if (message.isEmpty || !mounted) return;
    // SnackBar 호출 제거 (ScaffoldLayout.performLayout 오류 원인)
  }

  /// 적립 실패 팝업. 다시 시도를 고르면 PIN 입력부터 재개한다.
  Future<bool?> _showStampFailedDialog(String message) async {
    if (!mounted) return null;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFEBEF),
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  size: 34,
                  color: Color(0xFFE11D48),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '적립하지 못했어요',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Color(0xFF191F28),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                  color: Color(0xFF8B95A1),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4B5563),
                        side: const BorderSide(color: Color(0xFFE9EBF0)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Theme.deep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('다시 시도'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 적립 성공 연출. 도장이 찍히듯 튀어나오는 팝업으로 결과를 확정해 준다.
  Future<void> _showStampStampedDialog({
    required int added,
    required int current,
    required int total,
    bool cycleReset = false,
  }) async {
    if (!mounted) return;
    final status = _effectiveStampStatus;
    // 남은 개수는 다음 리워드 기준. 판 크기로 세면 중간 단계 보상이 무시된다.
    final remaining = status.remainingToNextReward;
    final nextReward = status.nextReward;
    // 판 정보가 없을 때(total<=0)를 "리워드 도착"으로 오인하지 않는다.
    final celebrate = cycleReset || (total > 0 && remaining == 0);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.elasticOut,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child:
                      Transform.rotate(angle: (1 - value) * 0.5, child: child),
                ),
                child: Image.asset(
                  celebrate
                      ? 'assets/images/stamp/stamp_reward.png'
                      : 'assets/images/stamp/stamp_filled.png',
                  width: 96,
                  height: 96,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                celebrate ? '리워드 도착!' : '스탬프 $added개 적립!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: Color(0xFF191F28),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                cycleReset
                    ? '리워드 쿠폰이 쿠폰함에 도착했어요\n스탬프판은 $current / $total 부터 다시 시작돼요'
                    : (celebrate
                        ? '리워드 쿠폰을 쿠폰함에서 확인하세요'
                        : nextReward != null
                            ? '$current / $total · $remaining개 더 모으면 '
                                '${stampRewardBenefitText(nextReward)}'
                            : '$current / $total 적립했어요'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8B95A1),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Theme.deep,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStampDailyLimitDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('적립 한도 안내'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = widget.restaurant;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    // 아이폰 다이나믹 아일랜드 등을 고려한 최소 상단 여백
    final safeTopPadding = math.max(topPadding, 50.0);
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop) return;
        if (_exitType == 'unknown') {
          _exitType = 'dismiss';
        }
      },
      child: Container(
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
                    padding: const EdgeInsets.only(top: 0, bottom: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroSection(restaurant),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
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
                    _exitType = 'close_button';
                    _logDetailCta('close');
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
      ),
    );
  }

  /// 혜택 / 매장 정보 2탭. (리뷰는 데이터가 없어 넣지 않는다)
  Widget _buildBenefitsTab(AffiliateRestaurantSummary restaurant) {
    return Column(
      key: const ValueKey('benefits'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailTabs(),
        const SizedBox(height: 16),
        if (_detailTab == 0) ...[
          _buildStampSection(),
          const SizedBox(height: 16),
          _buildCouponSection(),
          const SizedBox(height: 16),
          _buildRestaurantBenefitDetailSection(),
        ] else
          _buildStoreInfoTab(restaurant),
      ],
    );
  }

  Widget _buildDetailTabs() {
    const labels = ['혜택', '매장 정보'];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE9EBF0))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => setState(() => _detailTab = i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 20),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2.5,
                      color:
                          _detailTab == i ? _Theme.primary : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _detailTab == i
                        ? const Color(0xFF191F28)
                        : const Color(0xFF8B95A1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStoreInfoTab(AffiliateRestaurantSummary restaurant) {
    final rows = <List<String>>[
      ['주소', restaurant.address.isNotEmpty ? restaurant.address : '정보 없음'],
      [
        '전화',
        restaurant.phoneNumber.isNotEmpty ? restaurant.phoneNumber : '정보 없음'
      ],
      if (restaurant.category.isNotEmpty) ['분류', restaurant.category],
      if (restaurant.zone.isNotEmpty) ['위치', restaurant.zone],
    ];

    return Container(
      key: const ValueKey('info'),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE9EBF0)),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: i == rows.length - 1
                        ? Colors.transparent
                        : const Color(0xFFF2F3F7),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      rows[i][0],
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8B95A1),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i][1],
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(AffiliateRestaurantSummary restaurant) {
    final couponCount = _coupons.length;
    final stampStatus = _stampStatus;
    final stampCurrent = stampStatus?.current ?? restaurant.stampCurrent;
    final stampTarget = stampStatus?.target ?? restaurant.stampTarget;
    final meta = [restaurant.category, restaurant.zone]
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
          child: _buildImageCarousel(restaurant.imageUrls),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.requiresLogin &&
                  (couponCount > 0 || stampTarget > 0)) ...[
                Row(
                  children: [
                    if (couponCount > 0)
                      _buildHeroPill('쿠폰 $couponCount장', highlight: true),
                    if (couponCount > 0 && stampTarget > 0)
                      const SizedBox(width: 5),
                    if (stampTarget > 0)
                      _buildHeroPill('스탬프 $stampCurrent/$stampTarget'),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      restaurant.name.isNotEmpty
                          ? restaurant.name
                          : '매장 정보를 찾을 수 없어요',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: Color(0xFF191F28),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleFavorite,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite
                          ? const Color(0xFFE11D48)
                          : const Color(0xFF9CA3AF),
                    ),
                    tooltip: _isFavorite ? '찜 해제' : '찜하기',
                  ),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  meta,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8B95A1),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildQuickActions(restaurant),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroPill(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? _Theme.soft : const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: highlight ? _Theme.primary : const Color(0xFF4B5563),
        ),
      ),
    );
  }

  /// 전화 · 길찾기 · 매장 페이지. 데이터가 없는 버튼은 흐리게 두고 비활성.
  Widget _buildQuickActions(AffiliateRestaurantSummary restaurant) {
    final phone = restaurant.phoneNumber.trim();
    final address = restaurant.address.trim();
    final url = restaurant.url?.trim() ?? '';

    return Row(
      children: [
        Expanded(
          child: _buildQuickAction(
            icon: Icons.call_outlined,
            label: '전화',
            onTap: phone.isEmpty
                ? null
                : () {
                    _logDetailCta('call');
                    _launchExternal('tel:$phone');
                  },
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _buildQuickAction(
            icon: Icons.explore_outlined,
            label: '길찾기',
            onTap: address.isEmpty
                ? null
                : () {
                    _logDetailCta('directions');
                    _launchExternal(
                      'https://map.kakao.com/link/search/'
                      '${Uri.encodeComponent(address)}',
                    );
                  },
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _buildQuickAction(
            icon: Icons.open_in_new_rounded,
            label: '매장 정보',
            onTap: url.isEmpty
                ? null
                : () {
                    _logDetailCta('store_page');
                    _launchExternal(url);
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final color = enabled ? const Color(0xFF4B5563) : const Color(0xFFC7CCD6);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE9EBF0)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantBenefitDetailSection() {
    if (!_shouldShowBenefitDetailSection) {
      return const SizedBox.shrink();
    }

    final summary = _couponBenefitsSummary;
    final canExpand = summary != null && summary.hasVisibleContent;
    final showLoadingInBody =
        _isCouponBenefitsLoading && _isBenefitDetailExpanded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  '식당 혜택 상세정보',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              if (canExpand || _isCouponBenefitsLoading)
                _buildBenefitDetailToggleButton(
                  enabled: canExpand || _isCouponBenefitsLoading,
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _isBenefitDetailExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: showLoadingInBody
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : canExpand
                            ? RestaurantCouponBenefitsContent(summary: summary!)
                            : const Text(
                                '혜택 정보 준비 중이에요',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF9CA3AF),
                                  height: 1.45,
                                ),
                              ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitDetailToggleButton({bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? _toggleBenefitDetailExpanded : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isBenefitDetailExpanded ? '접기' : '펼쳐보기',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111439),
            ),
          ),
          Icon(
            _isBenefitDetailExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: const Color(0xFF111439),
          ),
        ],
      ),
    );
  }

  /// 스탬프 티켓 (시안 Option C). 흰 티켓 + 절취선 + 원형 스탬프 그리드.
  Widget _buildStampSection() {
    final status = _effectiveStampStatus;
    // 칸 수는 서버 target(cycle_target)과 최상단 리워드에서 나온다.
    // 예전엔 최소 10칸을 강제해 리워드가 3개뿐인 매장도 10칸으로 그려졌다.
    final total = status.boardLength;
    // 스탬프 프로그램 정보가 없으면 0/0 판을 그리지 않고 섹션을 숨긴다.
    if (total <= 0) return const SizedBox.shrink();
    final current = status.current;
    final filled = math.min(current, total);
    // 남은 개수는 "다음 리워드까지"다. 판 끝까지가 아니다.
    final remaining = status.remainingToNextReward;
    final ready = remaining == 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D191F28),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x14191F28),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/stamp/stamp_tag.png',
                      width: 34,
                      height: 34,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${widget.restaurant.name} 스탬프',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: Color(0xFF333D4B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$filled',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.9,
                                    color: _Theme.primary,
                                    height: 1.1,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / $total',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.7,
                                    color: Color(0xFF191F28),
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _stampSubtitle(ready: ready, remaining: remaining),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF8B95A1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildStampActionButton(ready),
                  ],
                ),
              ],
            ),
          ),
          const _DashedDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: _isStampLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _Theme.primary,
                        ),
                      ),
                    ),
                  )
                : _buildStampGrid(filled: filled, total: total),
          ),
          if (_stampError != null || (_stampStatus?.notes?.isNotEmpty ?? false))
            Container(
              width: double.infinity,
              color: const Color(0xFFF7F8FB),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/images/stamp/stamp_info.png',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _stampError ?? _stampStatus?.notes ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                        color: _stampError != null
                            ? const Color(0xFFE11D48)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              color: const Color(0xFFF7F8FB),
              padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/stamp/stamp_info.png',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '하루 최대 ${AppConfigService.stampDailyLimitPerRestaurant}회 적립 · 마지막 칸이 리워드예요',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 티켓 부제. 식당별 리워드 문구가 있으면 그걸 쓰고, 없으면 남은 개수를 안내한다.
  String _stampSubtitle({required bool ready, required int remaining}) {
    if (widget.requiresLogin) return '로그인하면 스탬프를 적립할 수 있어요';
    final reward = _getNextReward() ?? _getCurrentReward();
    if (ready) {
      return reward != null
          ? _formatRewardHeadline(reward)
          : '리워드 쿠폰을 받을 수 있어요';
    }
    if (reward != null) return _formatRewardHeadline(reward);
    return '$remaining개 더 모으면 리워드 쿠폰';
  }

  /// 적립하기 / 리워드 받기 버튼 (시안: 흰 배경 + 인디고 외곽선)
  Widget _buildStampActionButton(bool ready) {
    final disabled = widget.requiresLogin || _isStampProcessing;
    return InkWell(
      onTap: disabled ? null : _handleAddStamp,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: ShapeDecoration(
          color: disabled ? const Color(0xFFF4F5F8) : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: disabled ? const Color(0xFFE5E7EB) : _Theme.border,
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isStampProcessing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _Theme.primary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ready ? '리워드 받기' : '적립하기',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color:
                          disabled ? const Color(0xFF9CA3AF) : _Theme.primary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: disabled ? const Color(0xFF9CA3AF) : _Theme.primary,
                  ),
                ],
              ),
      ),
    );
  }

  /// 5칸씩 줄바꿈되는 원형 스탬프 그리드. 마지막 칸은 리워드(선물) 도장.
  Widget _buildStampGrid({required int filled, required int total}) {
    return StampAssetGrid(
      current: filled,
      target: total,
      rewardSteps: _stampThresholds().toSet(),
    );
  }

  /// 스탬프 비고(유의사항) 표시. 오버플로우 방지를 위해 maxHeight + 스크롤 적용

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

  Widget _buildCouponSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '지금 쓸 수 있는 쿠폰',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Color(0xFF191F28),
              ),
            ),
            if (_coupons.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '${_coupons.length}장',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _Theme.primary,
                ),
              ),
            ],
            const Spacer(),
            if (!widget.requiresLogin)
              IconButton(
                icon: const Icon(Icons.refresh, size: 19),
                tooltip: '쿠폰 목록 새로고침',
                color: const Color(0xFF8B95A1),
                onPressed: _refreshCoupons,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.requiresLogin)
          const Text(
            '로그인하면 제휴 쿠폰을 확인할 수 있어요.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF8B95A1)),
          )
        else if (_coupons.isEmpty)
          const Text(
            '사용 가능한 쿠폰이 없어요.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF8B95A1)),
          )
        else
          Column(
            children: _coupons.map(_buildCouponTile).toList(),
          ),
      ],
    );
  }

  /// 0 = 혜택, 1 = 매장 정보
  int _detailTab = 0;
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
    final benefit = coupon.benefit;
    final expiresAt = coupon.expiresAt;
    final categoryKey = _categoryKeyOf(
      benefit?.restaurantCategory ?? widget.restaurant.category,
    );
    final meta = _CategoryMeta(
      MasterContent.labelOf(categoryKey),
      MasterContent.svgOf(categoryKey),
    );
    final storeLabel = benefit?.allStores == true
        ? '전 매장 사용 가능'
        : (benefit?.restaurantNameText ?? widget.restaurant.name);

    return CouponTicketCard(
      // 지갑 쿠폰함과 같은 티켓 카드를 그대로 쓴다 (디자인 일원화).
      iconPath: meta.assetPath,
      storeLabel: storeLabel,
      title: benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle,
      subtitle: benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle,
      notes: benefit?.notesText,
      expiryText: _formatExpiryDate(expiresAt),
      expiryUrgent: isCouponExpiringSoon(coupon),
      isProcessing: _processingCouponCode == coupon.code,
      onAction: widget.requiresLogin
          ? null
          : () {
              _logDetailCta('coupon_use');
              _handleRedeem(coupon);
            },
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

  /// 전화·지도·매장 링크 공용 실행기.
  Future<void> _launchExternal(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      _showSnack('유효한 링크가 아니에요.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('열 수 없어요.');
    }
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

/// 스탬프 1칸. 마지막 칸은 목표 지점이라 점선 테두리로 구분한다.
class _StampDot extends StatelessWidget {
  const _StampDot({
    required this.filled,
    required this.isGoal,
    required this.ready,
  });

  final bool filled;
  final bool isGoal;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled
            ? LinearGradient(
                colors: ready
                    ? const [_Theme.deep, _Theme.primary]
                    : const [_Theme.primary, _Theme.light],
              )
            : null,
        color: filled ? null : Colors.white,
        border: Border.all(
          color: filled
              ? Colors.transparent
              : (isGoal ? _Theme.border : _Theme.track),
          width: 1.5,
        ),
      ),
      child: filled
          ? Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x8CFFFFFF),
                ),
              ),
            )
          : null,
    );
  }
}

/// 티켓 절취선. 노치 사이를 잇는 점선 한 줄.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      child: CustomPaint(painter: _DashedLinePainter(), size: Size.infinite),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE3E6EF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.75), Offset(x + dash, 0.75), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
