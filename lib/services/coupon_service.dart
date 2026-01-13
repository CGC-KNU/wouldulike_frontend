import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

const String kCouponBenefitFallbackTitle = '혜택 정보가 준비 중이에요';
const String kCouponBenefitFallbackSubtitle = '쿠폰 상세 정보를 확인하려면 매장에 문의해 주세요.';

enum CouponStatus { issued, redeemed, expired, canceled, unknown }

extension CouponStatusName on CouponStatus {
  String get apiValue {
    switch (this) {
      case CouponStatus.issued:
        return 'ISSUED';
      case CouponStatus.redeemed:
        return 'REDEEMED';
      case CouponStatus.expired:
        return 'EXPIRED';
      case CouponStatus.canceled:
        return 'CANCELED';
      case CouponStatus.unknown:
        return 'UNKNOWN';
    }
  }

  static CouponStatus from(String? raw) {
    switch (raw) {
      case 'ISSUED':
        return CouponStatus.issued;
      case 'REDEEMED':
        return CouponStatus.redeemed;
      case 'EXPIRED':
        return CouponStatus.expired;
      case 'CANCELED':
        return CouponStatus.canceled;
      default:
        return CouponStatus.unknown;
    }
  }
}

class UserCoupon {
  const UserCoupon({
    required this.code,
    required this.status,
    this.restaurantId,
    this.benefit,
  });

  factory UserCoupon.fromJson(Map<String, dynamic> json) {
    int? parseRestaurant(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        return int.tryParse(trimmed);
      }
      return null;
    }

    final benefit = _parseCouponBenefit(json);
    final resolvedRestaurantId =
        parseRestaurant(json['restaurant_id']) ?? benefit?.restaurantId;

    return UserCoupon(
      code: json['code']?.toString() ?? '',
      status: CouponStatusName.from(json['status']?.toString()),
      restaurantId: resolvedRestaurantId,
      benefit: benefit,
    );
  }

  final String code;
  final CouponStatus status;
  final int? restaurantId;
  final CouponBenefitInfo? benefit;
}

class CouponBenefitInfo {
  const CouponBenefitInfo({
    this.title,
    this.subtitle,
    this.description,
    this.restaurantId,
    this.restaurantName,
  });

  factory CouponBenefitInfo.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? details;
    final rawDetails = json['benefit'];
    if (rawDetails is Map<String, dynamic>) {
      details = rawDetails;
    } else if (rawDetails is Map) {
      details = Map<String, dynamic>.from(rawDetails);
    }

    return CouponBenefitInfo(
      title: _normalizeString(json['title']),
      subtitle: _normalizeString(json['subtitle']),
      description: details != null
          ? _normalizeString(details['description'])
          : _normalizeString(json['description']),
      restaurantId: _parseOptionalInt(json['restaurant_id']),
      restaurantName: _normalizeString(json['restaurant_name']),
    );
  }

  final String? title;
  final String? subtitle;
  final String? description;
  final int? restaurantId;
  final String? restaurantName;

  String get resolvedTitle =>
      (title != null && title!.isNotEmpty) ? title! : kCouponBenefitFallbackTitle;

  String get resolvedSubtitle =>
      (subtitle != null && subtitle!.isNotEmpty)
          ? subtitle!
          : kCouponBenefitFallbackSubtitle;

  String? get descriptionText =>
      (description != null && description!.isNotEmpty) ? description : null;

  String? get restaurantNameText =>
      (restaurantName != null && restaurantName!.isNotEmpty)
          ? restaurantName
          : null;
}

CouponBenefitInfo? _parseCouponBenefit(Map<String, dynamic> json) {
  final dynamic raw = json['benefit'] ?? json['benefit_snapshot'];
  if (raw is Map<String, dynamic>) {
    return CouponBenefitInfo.fromJson(raw);
  }
  if (raw is Map) {
    return CouponBenefitInfo.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }
  return null;
}

class StampRewardCoupon {
  const StampRewardCoupon({
    required this.threshold,
    required this.couponCode,
    required this.couponType,
  });

  factory StampRewardCoupon.fromJson(Map<String, dynamic> json) {
    return StampRewardCoupon(
      threshold: _parseInt(json['threshold']),
      couponCode: json['coupon_code']?.toString() ?? '',
      couponType: json['coupon_type']?.toString() ?? '',
    );
  }

  final int threshold;
  final String couponCode;
  final String couponType;
}

class StampStatus {
  const StampStatus({
    required this.current,
    required this.target,
    this.updatedAt,
    this.rewardCoupons = const [],
  });

  factory StampStatus.fromJson(Map<String, dynamic> json) {
    List<StampRewardCoupon> parseRewardCoupons() {
      final dynamic value = json['reward_coupons'];
      if (value is List) {
        return value
            .map((item) {
              if (item is Map<String, dynamic>) {
                return StampRewardCoupon.fromJson(item);
              }
              if (item is Map) {
                return StampRewardCoupon.fromJson(
                    Map<String, dynamic>.from(item));
              }
              return null;
            })
            .whereType<StampRewardCoupon>()
            .toList();
      }
      return const [];
    }

    return StampStatus(
      current: _parseInt(json['current']),
      target: _parseInt(json['target']),
      updatedAt: _parseDate(json['updated_at']),
      rewardCoupons: parseRewardCoupons(),
    );
  }

  final int current;
  final int target;
  final DateTime? updatedAt;
  final List<StampRewardCoupon> rewardCoupons;
}

class StampStatusCollection {
  const StampStatusCollection({
    required this.statuses,
    this.defaultTarget,
    required this.hasResults,
  });

  final Map<int, StampStatus> statuses;
  final int? defaultTarget;
  final bool hasResults;
}

class StampActionResult {
  const StampActionResult({
    required this.ok,
    required this.current,
    required this.target,
    this.rewardCouponCode,
    this.rewardCouponCodes = const [],
    this.rewardCoupons = const [],
  });

  factory StampActionResult.fromJson(Map<String, dynamic> json) {
    List<String> parseRewardCouponCodes() {
      final dynamic value = json['reward_coupon_codes'];
      if (value is List) {
        return value
            .map((item) => item?.toString() ?? '')
            .where((code) => code.isNotEmpty)
            .toList();
      }
      return const [];
    }

    List<StampRewardCoupon> parseRewardCoupons() {
      final dynamic value = json['reward_coupons'];
      if (value is List) {
        return value
            .map((item) {
              if (item is Map<String, dynamic>) {
                return StampRewardCoupon.fromJson(item);
              }
              if (item is Map) {
                return StampRewardCoupon.fromJson(
                    Map<String, dynamic>.from(item));
              }
              return null;
            })
            .whereType<StampRewardCoupon>()
            .toList();
      }
      return const [];
    }

    return StampActionResult(
      ok: json['ok'] is bool ? json['ok'] as bool : true,
      current: _parseInt(json['current']),
      target: _parseInt(json['target']),
      rewardCouponCode: json['reward_coupon_code']?.toString(),
      rewardCouponCodes: parseRewardCouponCodes(),
      rewardCoupons: parseRewardCoupons(),
    );
  }

  StampStatus get status => StampStatus(
        current: current,
        target: target,
        updatedAt: null,
        rewardCoupons: rewardCoupons,
      );

  final bool ok;
  final int current;
  final int target;
  final String? rewardCouponCode;
  final List<String> rewardCouponCodes;
  final List<StampRewardCoupon> rewardCoupons;
}

class CouponRedeemResult {
  const CouponRedeemResult({
    required this.ok,
    required this.couponCode,
  });

  factory CouponRedeemResult.fromJson(Map<String, dynamic> json) {
    return CouponRedeemResult(
      ok: json['ok'] is bool ? json['ok'] as bool : true,
      couponCode: json['coupon_code']?.toString() ?? '',
    );
  }

  final bool ok;
  final String couponCode;
}

class ReferralAcceptResponse {
  const ReferralAcceptResponse({
    required this.ok,
    this.referralId,
  });

  factory ReferralAcceptResponse.fromJson(Map<String, dynamic> json) {
    return ReferralAcceptResponse(
      ok: json['ok'] is bool ? json['ok'] as bool : true,
      referralId: _parseOptionalInt(json['referral_id']),
    );
  }

  final bool ok;
  final int? referralId;
}

class CouponService {
  static Future<List<UserCoupon>> fetchMyCoupons({CouponStatus? status}) async {
    final Map<String, dynamic>? params;
    if (status != null && status != CouponStatus.unknown) {
      params = {'status': status.apiValue};
    } else {
      params = null;
    }

    final http.Response response = await ApiClient.get(
      '/api/coupons/my/',
      queryParameters: params,
    );

    final decoded = _decodeResponseBody(response);
    if (decoded is List) {
      return decoded
          .map((item) => UserCoupon.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    if (decoded is Map<String, dynamic> && decoded['results'] is List) {
      return (decoded['results'] as List)
          .map((item) => UserCoupon.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    return const [];
  }

  static Future<StampStatus> fetchStampStatus(
      {required int restaurantId}) async {
    final response = await ApiClient.get(
      '/api/coupons/stamps/my/',
      queryParameters: {'restaurant_id': restaurantId},
    );
    final decoded = _decodeResponseBody(response);
    if (decoded is Map<String, dynamic>) {
      return StampStatus.fromJson(decoded);
    }
    return const StampStatus(current: 0, target: 0);
  }

  static Future<StampStatusCollection> fetchAllStampStatuses() async {
    final response = await ApiClient.get(
      '/api/coupons/stamps/my/all/',
    );
    final decoded = _decodeResponseBody(response);
    Map<int, StampStatus> parseStatuses(dynamic value) {
      if (value is! List) return const <int, StampStatus>{};
      final result = <int, StampStatus>{};
      for (final item in value) {
        if (item is! Map) continue;
        final mapItem = Map<String, dynamic>.from(item);
        final restaurantId = _parseInt(mapItem['restaurant_id']);
        if (restaurantId == 0) continue;
        Map<String, dynamic> statusJson;
        final statusValue = mapItem['status'];
        if (statusValue is Map<String, dynamic>) {
          statusJson = statusValue;
        } else if (statusValue is Map) {
          statusJson = Map<String, dynamic>.from(statusValue);
        } else {
          statusJson = Map<String, dynamic>.from(mapItem)
            ..remove('restaurant_id');
        }
        result[restaurantId] = StampStatus.fromJson(statusJson);
      }
      return result;
    }

    if (decoded is Map<String, dynamic>) {
      final resultsRaw = decoded['results'];
      final statuses = parseStatuses(resultsRaw);
      final defaultTarget = _parseInt(decoded['default_target']);
      final hasResults =
          resultsRaw is List && resultsRaw.isNotEmpty && statuses.isNotEmpty;
      return StampStatusCollection(
        statuses: statuses,
        defaultTarget: defaultTarget > 0 ? defaultTarget : null,
        hasResults: hasResults,
      );
    }
    return const StampStatusCollection(
      statuses: <int, StampStatus>{},
      defaultTarget: null,
      hasResults: false,
    );
  }

  static Future<StampActionResult> addStamp({
    required int restaurantId,
    required String pin,
    String? idemKey,
  }) async {
    final body = <String, dynamic>{
      'restaurant_id': restaurantId,
      'pin': pin,
    };
    if (idemKey != null && idemKey.isNotEmpty) {
      body['idem_key'] = idemKey;
    }

    final response = await ApiClient.post(
      '/api/coupons/stamps/add/',
      body: body,
    );

    final decoded = _decodeResponseBody(response);
    if (decoded is Map<String, dynamic>) {
      return StampActionResult.fromJson(decoded);
    }
    return const StampActionResult(ok: true, current: 0, target: 0);
  }

  static Future<CouponRedeemResult> redeemCoupon({
    required String couponCode,
    required int restaurantId,
    required String pin,
  }) async {
    final response = await ApiClient.post(
      '/api/coupons/redeem/',
      body: {
        'coupon_code': couponCode,
        'restaurant_id': restaurantId,
        'pin': pin,
      },
    );
    final decoded = _decodeResponseBody(response);
    if (decoded is Map<String, dynamic>) {
      return CouponRedeemResult.fromJson(decoded);
    }
    return CouponRedeemResult(ok: true, couponCode: couponCode);
  }

  static Future<Map<String, dynamic>> fetchInviteCode() async {
    Future<Map<String, dynamic>> request(String path) async {
      final response = await ApiClient.get(
        path,
        authenticated: true,
      );
      final decoded = _decodeResponseBody(response);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw ApiHttpException(response.statusCode, response.body);
    }

    try {
      return await request('/api/coupons/invite/my/');
    } on ApiHttpException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        return request('/api/coupons/invite-code/');
      }
      rethrow;
    }
  }

  static Future<ReferralAcceptResponse> acceptReferralCode({
    required String refCode,
  }) async {
    final response = await ApiClient.post(
      '/api/coupons/referrals/accept/',
      body: {'ref_code': refCode},
    );
    final decoded = _decodeResponseBody(response);
    if (decoded is Map<String, dynamic>) {
      return ReferralAcceptResponse.fromJson(decoded);
    }
    return const ReferralAcceptResponse(ok: true);
  }

  static dynamic _decodeResponseBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }
}

int? _parseOptionalInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
  return null;
}

String? _normalizeString(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
  return null;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _parseDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
