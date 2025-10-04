import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

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
  });

  factory UserCoupon.fromJson(Map<String, dynamic> json) {
    int? parseRestaurant(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '');
    }

    return UserCoupon(
      code: json['code']?.toString() ?? '',
      status: CouponStatusName.from(json['status']?.toString()),
      restaurantId: parseRestaurant(json['restaurant_id']),
    );
  }

  final String code;
  final CouponStatus status;
  final int? restaurantId;
}

class StampStatus {
  const StampStatus({
    required this.current,
    required this.target,
    this.updatedAt,
  });

  factory StampStatus.fromJson(Map<String, dynamic> json) {
    return StampStatus(
      current: _parseInt(json['current']),
      target: _parseInt(json['target']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  final int current;
  final int target;
  final DateTime? updatedAt;
}

class StampActionResult {
  const StampActionResult({
    required this.ok,
    required this.current,
    required this.target,
    this.rewardCouponCode,
  });

  factory StampActionResult.fromJson(Map<String, dynamic> json) {
    return StampActionResult(
      ok: json['ok'] is bool ? json['ok'] as bool : true,
      current: _parseInt(json['current']),
      target: _parseInt(json['target']),
      rewardCouponCode: json['reward_coupon_code']?.toString(),
    );
  }

  StampStatus get status =>
      StampStatus(current: current, target: target, updatedAt: null);

  final bool ok;
  final int current;
  final int target;
  final String? rewardCouponCode;
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

  static dynamic _decodeResponseBody(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }
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
