import 'dart:convert';

import 'package:new1/models/coupon_benefits_summary.dart';

import 'api_client.dart';

class AffiliateRestaurantSummary {
  const AffiliateRestaurantSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.category,
    required this.zone,
    required this.phoneNumber,
    required this.url,
    required this.imageUrls,
    required this.stampCurrent,
    required this.stampTarget,
    this.couponBenefitsSummary,
  });

  factory AffiliateRestaurantSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) {
        return int.tryParse(value) ?? 0;
      }
      return 0;
    }

    int parseStampCurrent() {
      if (json['stamp_current'] != null) {
        return parseInt(json['stamp_current']);
      }
      final dynamic status = json['stamp_status'];
      if (status is Map<String, dynamic>) {
        return parseInt(status['current']);
      }
      return 0;
    }

    int parseStampTarget() {
      if (json['stamp_target'] != null) {
        return parseInt(json['stamp_target']);
      }
      final dynamic status = json['stamp_status'];
      if (status is Map<String, dynamic>) {
        return parseInt(status['target']);
      }
      return 0;
    }

    List<String> parseImages(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item?.toString() ?? '')
            .where((item) => item.isNotEmpty)
            .toList();
      }
      return const [];
    }

    CouponBenefitsSummary? parseCouponBenefitsSummary() {
      return CouponBenefitsSummary.tryParse(json['coupon_benefits_summary']);
    }

    return AffiliateRestaurantSummary(
      id: json['restaurant_id'] is int
          ? json['restaurant_id'] as int
          : int.tryParse(json['restaurant_id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      url: json['url']?.toString(),
      imageUrls: parseImages(json['s3_image_urls']),
      stampCurrent: parseStampCurrent(),
      stampTarget: parseStampTarget(),
      couponBenefitsSummary: parseCouponBenefitsSummary(),
    );
  }

  final int id;
  final String name;
  final String description;
  final String address;
  final String category;
  final String zone;
  final String phoneNumber;
  final String? url;
  final List<String> imageUrls;
  final int stampCurrent;
  final int stampTarget;
  final CouponBenefitsSummary? couponBenefitsSummary;
}

class GeneralRestaurantSummary {
  const GeneralRestaurantSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.category,
    required this.zone,
    required this.phoneNumber,
    required this.url,
  });

  factory GeneralRestaurantSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    String firstNonEmpty(List<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    return GeneralRestaurantSummary(
      id: parseInt(json['restaurant_id'] ?? json['id']),
      name: firstNonEmpty([json['name']]),
      description: firstNonEmpty([json['description']]),
      address: firstNonEmpty([json['address'], json['road_address']]),
      category: firstNonEmpty(
        [json['category'], json['category_1'], json['category_2']],
      ),
      zone: firstNonEmpty([json['zone']]),
      phoneNumber: firstNonEmpty([json['phone_number']]),
      url: firstNonEmpty([json['url'], json['link_url'], json['external_url']]),
    );
  }

  final int id;
  final String name;
  final String description;
  final String address;
  final String category;
  final String zone;
  final String phoneNumber;
  final String url;
}

class GeneralPagination {
  const GeneralPagination({
    required this.limit,
    required this.offset,
    required this.nextOffset,
    required this.returnedCount,
    required this.totalCount,
    required this.hasMore,
  });

  factory GeneralPagination.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return GeneralPagination(
      limit: parseInt(json['limit']),
      offset: parseInt(json['offset']),
      nextOffset:
          json['next_offset'] == null ? null : parseInt(json['next_offset']),
      returnedCount: parseInt(json['returned_count']),
      totalCount: parseInt(json['total_count']),
      hasMore: json['has_more'] == true,
    );
  }

  final int limit;
  final int offset;
  final int? nextOffset;
  final int returnedCount;
  final int totalCount;
  final bool hasMore;
}

class TabRestaurantsResponse {
  const TabRestaurantsResponse({
    required this.affiliateRestaurants,
    required this.generalRestaurants,
    required this.generalPagination,
    required this.searchQuery,
  });

  final List<AffiliateRestaurantSummary> affiliateRestaurants;
  final List<GeneralRestaurantSummary> generalRestaurants;
  final GeneralPagination generalPagination;
  final String searchQuery;
}

class ActiveAffiliateRestaurantsResponse {
  const ActiveAffiliateRestaurantsResponse({
    required this.source,
    required this.restaurants,
  });

  final String source;
  final List<AffiliateRestaurantSummary> restaurants;
}

class AffiliateService {
  /// GET /api/coupons/signup/restaurants/ — 온보딩 식당 선택 화면 전용 목록.
  /// 웰컴 미션 보상 쿠폰이 설정된 식당으로만 서버가 필터링해 내려준다(운영팀
  /// 설정 전에는 필터링이 걸리지 않을 수 있음). **JWT 인증 필수** — 로그인 전
  /// (preLogin 온보딩 픽 단계)에는 애초에 호출하지 않고, 호출부가 기존
  /// active/전체 제휴 식당 목록으로 폴백한다. 실패해도 마찬가지로 폴백한다.
  static Future<List<AffiliateRestaurantSummary>> fetchSignupRestaurants() async {
    if (!await ApiClient.hasAccessToken()) return const [];
    final response = await ApiClient.get('/api/coupons/signup/restaurants/');
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> list =
        data['restaurants'] as List<dynamic>? ?? const [];
    return list
        .map(
          (item) => AffiliateRestaurantSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  static Future<List<AffiliateRestaurantSummary>> fetchRestaurants() async {
    final response = await ApiClient.get('/restaurants/affiliate-restaurants/',
        authenticated: false);
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> list =
        data['restaurants'] as List<dynamic>? ?? const [];
    return list
        .map(
          (item) => AffiliateRestaurantSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  static Future<AffiliateRestaurantSummary?> fetchRestaurantByName(
      String name) {
    return fetchRestaurantDetail(name: name);
  }

  static Future<AffiliateRestaurantSummary?> fetchRestaurantDetail({
    String? name,
    int? restaurantId,
  }) async {
    final queryParameters = <String, String>{};
    if (restaurantId != null && restaurantId > 0) {
      queryParameters['restaurant_id'] = restaurantId.toString();
    }
    final trimmedName = name?.trim() ?? '';
    if (trimmedName.isNotEmpty) {
      queryParameters['name'] = trimmedName;
    }
    if (queryParameters.isEmpty) return null;

    final response = await ApiClient.get(
      '/restaurants/affiliate-restaurants/detail/',
      authenticated: false,
      queryParameters: queryParameters,
    );
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final restaurant = data['restaurant'];
    if (restaurant is Map<String, dynamic>) {
      return AffiliateRestaurantSummary.fromJson(restaurant);
    }
    if (restaurant is Map) {
      return AffiliateRestaurantSummary.fromJson(
        Map<String, dynamic>.from(restaurant),
      );
    }
    return null;
  }

  static Future<ActiveAffiliateRestaurantsResponse> fetchActiveRestaurants()
  async {
    if (!await ApiClient.hasAccessToken()) {
      final restaurants = await fetchRestaurants();
      return ActiveAffiliateRestaurantsResponse(
        source: 'all',
        restaurants: restaurants,
      );
    }
    final response = await ApiClient.get(
      '/restaurants/affiliate-restaurants/active/',
      authenticated: true,
    );
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> list =
        data['restaurants'] as List<dynamic>? ?? const [];
    final restaurants = list
        .map(
          (item) => AffiliateRestaurantSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    return ActiveAffiliateRestaurantsResponse(
      source: data['source']?.toString() ?? 'all',
      restaurants: restaurants,
    );
  }

  static Future<TabRestaurantsResponse> fetchTabRestaurants({
    String? query,
    int limit = 20,
    int offset = 0,
    bool includeAffiliates = true,
  }) async {
    final q = query?.trim() ?? '';
    final queryParameters = <String, dynamic>{
      if (q.isNotEmpty) 'q': q,
      'limit': limit,
      'offset': offset,
      // 백엔드 기본값이 true이므로 false일 때만 전달한다.
      if (!includeAffiliates) 'include_affiliates': false,
    };
    const candidatePaths = <String>[
      '/restaurants/tab-restaurants/',
      '/restaurants/tab-restaurants',
      '/api/restaurants/tab-restaurants/',
      '/api/restaurants/tab-restaurants',
    ];

    Map<String, dynamic>? data;
    ApiHttpException? lastHttpError;

    Future<Map<String, dynamic>> parseFromPath(
      String path, {
      required bool authenticated,
    }) async {
      final response = await ApiClient.get(
        path,
        authenticated: authenticated,
        queryParameters: queryParameters,
      );
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }

    for (final path in candidatePaths) {
      try {
        data = await parseFromPath(path, authenticated: false);
        break;
      } on ApiHttpException catch (e) {
        lastHttpError = e;
        // 일부 배포 환경에서는 인증이 필요한 경우가 있어 한 번 더 시도
        if (e.statusCode == 401 || e.statusCode == 403) {
          try {
            data = await parseFromPath(path, authenticated: true);
            break;
          } on ApiHttpException catch (authErr) {
            lastHttpError = authErr;
            continue;
          }
        }
        // 경로가 다른 환경일 수 있으므로 다음 후보 경로로 진행
        if (e.statusCode == 404 || e.statusCode == 405) {
          continue;
        }
        rethrow;
      }
    }

    // 신규 탭 API가 아직 미배포된 환경에서는 기존 제휴 API로 안전하게 폴백
    if (data == null) {
      if (lastHttpError != null &&
          (lastHttpError.statusCode == 404 ||
              lastHttpError.statusCode == 405)) {
        final fallbackAffiliates = await fetchRestaurants();
        return TabRestaurantsResponse(
          affiliateRestaurants: fallbackAffiliates,
          generalRestaurants: const <GeneralRestaurantSummary>[],
          generalPagination: const GeneralPagination(
            limit: 20,
            offset: 0,
            nextOffset: null,
            returnedCount: 0,
            totalCount: 0,
            hasMore: false,
          ),
          searchQuery: q,
        );
      }
      throw lastHttpError ??
          ApiHttpException(500, 'Failed to load tab restaurants');
    }

    final affiliateList = ((data['affiliate_restaurants'] ??
                data['affiliateRestaurants'] ??
                data['affiliates']) as List<dynamic>? ??
            const <dynamic>[])
        .map(
          (item) => AffiliateRestaurantSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    final generalList = ((data['general_restaurants'] ??
                data['generalRestaurants'] ??
                data['restaurants']) as List<dynamic>? ??
            const <dynamic>[])
        .map(
          (item) => GeneralRestaurantSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    final paginationRaw = data['general_pagination'] ??
        data['generalPagination'] ??
        data['pagination'];
    final pagination = paginationRaw is Map<String, dynamic>
        ? GeneralPagination.fromJson(paginationRaw)
        : const GeneralPagination(
            limit: 20,
            offset: 0,
            nextOffset: null,
            returnedCount: 0,
            totalCount: 0,
            hasMore: false,
          );

    return TabRestaurantsResponse(
      affiliateRestaurants: affiliateList,
      generalRestaurants: generalList,
      generalPagination: pagination,
      searchQuery:
          (data['search_query'] ?? data['searchQuery'])?.toString() ?? q,
    );
  }
}
