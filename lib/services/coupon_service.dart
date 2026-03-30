import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'dart:async'; // Added for TimeoutException
import 'package:shared_preferences/shared_preferences.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';

import 'api_client.dart';

const String _kSeenCouponCodesKey = 'coupon_analytics_seen_codes';

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
    this.restaurantCategory,
    this.benefit,
    this.expiresAt,
    this.issuedAt,
    this.updatedAt,
    this.issueKey,
    this.campaignCode,
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
    final rawIssueKey = json['issue_key'];
    final issueKey = (rawIssueKey is String && rawIssueKey.trim().isNotEmpty)
        ? rawIssueKey.trim()
        : null;
    final campaignCode = _normalizeString(json['campaign_code']);

    return UserCoupon(
      code: json['code']?.toString() ?? '',
      status: CouponStatusName.from(json['status']?.toString()),
      restaurantId: resolvedRestaurantId,
      restaurantCategory: _normalizeString(json['restaurant_category']) ??
          benefit?.restaurantCategory,
      benefit: benefit,
      expiresAt: _parseDate(json['expires_at']),
      issuedAt: _parseDate(json['issued_at'] ?? json['created_at']),
      updatedAt: _parseDate(json['updated_at'] ?? json['redeemed_at']),
      issueKey: issueKey,
      campaignCode: campaignCode,
    );
  }

  final String code;
  final CouponStatus status;
  final int? restaurantId;
  final String? restaurantCategory;
  final CouponBenefitInfo? benefit;
  final DateTime? expiresAt;

  /// 쿠폰 발급 시각 (최신순 정렬용)
  final DateTime? issuedAt;

  /// 사용/갱신 시각 (사용 완료 쿠폰 최신순 정렬용)
  final DateTime? updatedAt;

  /// 쿠폰 발급 경로 식별 (APP_OPEN:, STAMP_REWARD:, FLASH:, FINAL_EXAM: 등)
  final String? issueKey;

  /// 캠페인 코드 (기획전·발급 경로 구분, Firebase coupon_issue_source 우선 사용)
  final String? campaignCode;

  /// Firebase coupon_issue_source: campaign_code 우선, 없으면 issue_key 기반
  String get couponIssueSource =>
      campaignCode ?? resolveCouponIssueSource(issueKey);
}

/// issue_key prefix로 쿠폰 발급 경로 반환 (레거시)
/// @see wouldulike_backend/docs/쿠폰_issue_key_프론트엔드_가이드.md
String getCouponIssuanceSource(String? issueKey) {
  if (issueKey == null || issueKey.isEmpty) return 'unknown';
  if (issueKey.startsWith('APP_OPEN:')) return 'app_open';
  if (issueKey.startsWith('AMBASSADOR:')) return 'bulk';
  if (issueKey.startsWith('REFERRAL_REFERRER:')) return 'referrer';
  if (issueKey.startsWith('REFERRAL_REFEREE:')) return 'referee';
  if (issueKey.startsWith('EVENT_REWARD:')) return 'event_referral';
  if (issueKey.startsWith('SIGNUP:')) return 'signup';
  if (issueKey.startsWith('STAMP_REWARD:')) return 'stamp';
  if (issueKey.startsWith('FLASH:')) return 'flash';
  if (issueKey.startsWith('FINAL_EXAM:')) return 'final_exam';
  return 'other';
}

/// Firebase coupon_issue_source: campaign_code 스타일 값 반환
/// campaign_code 없을 때 issue_key를 campaign_code 값으로 매핑
String resolveCouponIssueSource(String? issueKey) {
  if (issueKey == null || issueKey.isEmpty) return 'unknown';
  if (issueKey.startsWith('APP_OPEN:') || issueKey.startsWith('SIGNUP:')) {
    return 'SIGNUP_WELCOME';
  }
  if (issueKey.startsWith('AMBASSADOR:')) return 'BULK_EVENT';
  if (issueKey.startsWith('REFERRAL_REFERRER:') ||
      issueKey.startsWith('REFERRAL_REFEREE:')) {
    return 'REFERRAL';
  }
  if (issueKey.startsWith('EVENT_REWARD:')) return 'EVENT_REWARD_SIGNUP';
  if (issueKey.startsWith('STAMP_REWARD:')) return 'STAMP_REWARD';
  if (issueKey.startsWith('FLASH:')) return 'FLASH_8PM';
  if (issueKey.startsWith('FINAL_EXAM:')) return 'FINAL_EXAM_EVENT';
  return 'other';
}

class CouponBenefitInfo {
  const CouponBenefitInfo({
    this.title,
    this.subtitle,
    this.description,
    this.notes,
    this.restaurantId,
    this.restaurantName,
    this.restaurantCategory,
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
      notes: _normalizeString(json['notes']),
      restaurantId: _parseOptionalInt(json['restaurant_id']),
      restaurantName: _normalizeString(json['restaurant_name']),
      restaurantCategory: _normalizeString(json['restaurant_category']),
    );
  }

  final String? title;
  final String? subtitle;
  final String? description;
  final String? notes;
  final int? restaurantId;
  final String? restaurantName;
  final String? restaurantCategory;

  String get resolvedTitle => (title != null && title!.isNotEmpty)
      ? title!
      : kCouponBenefitFallbackTitle;

  String get resolvedSubtitle => (subtitle != null && subtitle!.isNotEmpty)
      ? subtitle!
      : kCouponBenefitFallbackSubtitle;

  String? get descriptionText =>
      (description != null && description!.isNotEmpty) ? description : null;

  /// 쿠폰 사용 조건 (예: "최소 주문 1만원", "음료만 사용 가능", "1인 1회 한정")
  String? get notesText => (notes != null && notes!.isNotEmpty) ? notes : null;

  String? get restaurantNameText =>
      (restaurantName != null && restaurantName!.isNotEmpty)
          ? restaurantName
          : null;
}

CouponBenefitInfo? _parseCouponBenefit(Map<String, dynamic> json) {
  final dynamic raw = json['benefit'] ?? json['benefit_snapshot'];
  if (raw == null) {
    // benefit/benefit_snapshot 없을 때 쿠폰 JSON 최상위에 title 등이 있는지 확인
    if (_normalizeString(json['title']) != null ||
        _normalizeString(json['subtitle']) != null ||
        _normalizeString(json['restaurant_name']) != null) {
      return CouponBenefitInfo.fromJson(json);
    }
    return null;
  }

  Map<String, dynamic> toParse;
  if (raw is Map<String, dynamic>) {
    toParse = raw;
  } else if (raw is Map) {
    toParse = Map<String, dynamic>.from(raw);
  } else {
    return null;
  }

  // 사용 완료 쿠폰: benefit_snapshot이 { benefit: { title, subtitle, ... } } 형태일 수 있음.
  // 상위에 title/subtitle/restaurant_name이 없고 중첩 benefit이 있으면 그걸 사용.
  final hasTopLevelInfo = _normalizeString(toParse['title']) != null ||
      _normalizeString(toParse['subtitle']) != null ||
      _normalizeString(toParse['restaurant_name']) != null;

  if (!hasTopLevelInfo) {
    final nested = toParse['benefit'];
    if (nested is Map<String, dynamic>) {
      toParse = nested;
    } else if (nested is Map) {
      toParse = Map<String, dynamic>.from(nested);
    }
  }

  return CouponBenefitInfo.fromJson(toParse);
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

/// GET 스탬프 현황 API의 rewards 배열 항목 (N개 적립 시 ~ 혜택 표시용)
class StampReward {
  const StampReward({
    this.stamps,
    this.visitRange,
    this.minVisit,
    this.maxVisit,
    this.title,
    this.subtitle,
    this.notes,
    this.benefit,
    this.couponTypeCode,
  });

  factory StampReward.fromJson(Map<String, dynamic> json) {
    final visitRange = _normalizeString(json['visit_range']);
    int? minVisit = _parseOptionalInt(json['min_visit']);
    int? maxVisit = _parseOptionalInt(json['max_visit']);

    // visit_range만 있으면 "1_4" 또는 "1-4" 형식으로 파싱
    if ((minVisit == null || maxVisit == null) &&
        visitRange != null &&
        visitRange.isNotEmpty) {
      final parsed = _parseVisitRange(visitRange);
      minVisit ??= parsed.$1;
      maxVisit ??= parsed.$2;
    }

    return StampReward(
      stamps: _parseOptionalInt(json['stamps']),
      visitRange: visitRange,
      minVisit: minVisit,
      maxVisit: maxVisit,
      title: _normalizeString(json['title']),
      subtitle: _normalizeString(json['subtitle']),
      notes: _normalizeString(json['notes']),
      benefit: json['benefit'],
      couponTypeCode: json['coupon_type_code']?.toString(),
    );
  }

  /// THRESHOLD 패턴: stamps 개수 도달 시 발급
  final int? stamps;

  /// VISIT 패턴: visit_range (예: "1_4")
  final String? visitRange;
  final int? minVisit;
  final int? maxVisit;
  final String? title;
  final String? subtitle;
  final String? notes;
  final dynamic benefit;
  final String? couponTypeCode;

  /// THRESHOLD 패턴: stamps 값. VISIT 패턴이면 null
  int? get threshold => stamps;
  bool get isVisitPattern => visitRange != null && visitRange!.isNotEmpty;
}

class StampStatus {
  const StampStatus({
    required this.current,
    required this.target,
    this.updatedAt,
    this.rewardCoupons = const [],
    this.rewards = const [],
    this.notes,
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

    List<StampReward> parseRewards() {
      final dynamic value = json['rewards'];
      if (value is List) {
        return value
            .map((item) {
              if (item is Map<String, dynamic>) {
                return StampReward.fromJson(item);
              }
              if (item is Map) {
                return StampReward.fromJson(Map<String, dynamic>.from(item));
              }
              return null;
            })
            .whereType<StampReward>()
            .toList();
      }
      return const [];
    }

    final notesRaw = json['notes'];
    final notesStr = notesRaw is String ? notesRaw.trim() : null;
    final notes = (notesStr != null && notesStr.isNotEmpty) ? notesStr : null;

    return StampStatus(
      current: _parseInt(json['current']),
      target: _parseInt(json['target']),
      updatedAt: _parseDate(json['updated_at']),
      rewardCoupons: parseRewardCoupons(),
      rewards: parseRewards(),
      notes: notes,
    );
  }

  final int current;
  final int target;
  final DateTime? updatedAt;
  final List<StampRewardCoupon> rewardCoupons;

  /// 해당 식당 스탬프 프로그램 전체에 대한 유의사항 (인원 제한, 최소 주문 금액 등)
  final String? notes;

  /// GET 스탬프 현황 API의 rewards 배열 (식당별 N개 적립 시 ~ 혜택 목록)
  final List<StampReward> rewards;
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

/// 스탬프 적립 API 결과 (throw 대신 반환으로 스택 트레이스 방지)
class StampAddResult {
  const StampAddResult._({
    this.result,
    this.errorMessage,
    this.errorCode,
    this.statusCode,
  }) : assert(result != null || errorMessage != null);

  factory StampAddResult.success(StampActionResult r) =>
      StampAddResult._(result: r);

  factory StampAddResult.failure(
    String msg, {
    String? errorCode,
    int? statusCode,
  }) =>
      StampAddResult._(
        errorMessage: msg,
        errorCode: errorCode,
        statusCode: statusCode,
      );

  final StampActionResult? result;
  final String? errorMessage;
  final String? errorCode;
  final int? statusCode;
  bool get isSuccess => result != null;
}

class StampActionResult {
  const StampActionResult({
    required this.ok,
    required this.added,
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
      added: _parseInt(json['added']),
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
  final int added;
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

/// 쿠폰 사용 시도 결과 (throw 없이 반환)
class CouponRedeemAttemptResult {
  const CouponRedeemAttemptResult._({this.result, this.errorMessage});

  factory CouponRedeemAttemptResult.success(CouponRedeemResult r) =>
      CouponRedeemAttemptResult._(result: r);

  factory CouponRedeemAttemptResult.failure(String msg) =>
      CouponRedeemAttemptResult._(errorMessage: msg);

  final CouponRedeemResult? result;
  final String? errorMessage;

  bool get isSuccess => result != null;
}

/// 백엔드 응답의 issued_coupons 항목 (쿠폰 발급 시 반환)
class IssuedCouponInfo {
  const IssuedCouponInfo({
    required this.code,
    this.restaurantId,
    this.issueKey,
    this.campaignCode,
    this.couponTypeCode,
  });

  factory IssuedCouponInfo.fromJson(Map<String, dynamic> json) {
    return IssuedCouponInfo(
      code: json['code']?.toString() ?? '',
      restaurantId: _parseOptionalInt(json['restaurant_id']),
      issueKey: _normalizeString(json['issue_key']),
      campaignCode: _normalizeString(json['campaign_code']),
      couponTypeCode: _normalizeString(json['coupon_type_code']),
    );
  }

  final String code;
  final int? restaurantId;
  final String? issueKey;

  /// 캠페인 코드 (기획전·발급 경로 구분, coupon_issue_source 우선 사용)
  final String? campaignCode;
  final String? couponTypeCode;

  /// coupon_issue_source 값: campaign_code 우선, 없으면 issue_key 기반
  String get couponIssueSource =>
      campaignCode ?? resolveCouponIssueSource(issueKey);
}

class ReferralAcceptResponse {
  const ReferralAcceptResponse({
    required this.ok,
    this.referralId,
    this.issuedCoupons = const [],
  });

  factory ReferralAcceptResponse.fromJson(Map<String, dynamic> json) {
    List<IssuedCouponInfo> parseIssuedCoupons() {
      final value = json['issued_coupons'];
      if (value is! List) return const [];
      return value
          .map((item) {
            if (item is Map<String, dynamic>) {
              return IssuedCouponInfo.fromJson(item);
            }
            if (item is Map) {
              return IssuedCouponInfo.fromJson(Map<String, dynamic>.from(item));
            }
            return null;
          })
          .whereType<IssuedCouponInfo>()
          .where((c) => c.code.isNotEmpty)
          .toList();
    }

    return ReferralAcceptResponse(
      ok: json['ok'] is bool ? json['ok'] as bool : true,
      referralId: _parseOptionalInt(json['referral_id']),
      issuedCoupons: parseIssuedCoupons(),
    );
  }

  final bool ok;
  final int? referralId;

  /// 백엔드가 발급된 쿠폰 목록을 반환할 때
  final List<IssuedCouponInfo> issuedCoupons;
}

/// issued_coupons 파싱·로깅. 로깅한 코드 집합 반환 (diff 중복 방지용)
Set<String> _logIssuedCouponsFromResponse(Map<String, dynamic> json) {
  final value = json['issued_coupons'];
  if (value is! List) return {};
  final logged = <String>{};
  for (final item in value) {
    final map = item is Map<String, dynamic>
        ? item
        : (item is Map ? Map<String, dynamic>.from(item) : null);
    if (map == null) continue;
    final c = IssuedCouponInfo.fromJson(map);
    if (c.code.isEmpty) continue;
    final params = <String, Object>{
      AnalyticsEvents.paramRestaurantId: c.restaurantId ?? 0,
      AnalyticsEvents.paramCouponIssueSource: c.couponIssueSource,
      AnalyticsEvents.paramCouponCode: c.code,
    };
    if (c.couponTypeCode != null && c.couponTypeCode!.isNotEmpty) {
      params[AnalyticsEvents.paramCouponTypeCode] = c.couponTypeCode!;
    }
    AnalyticsLogger.logEvent(AnalyticsEvents.couponIssued, parameters: params);
    logged.add(c.code);
  }
  return logged;
}

/// 조건 충족 시 자동 발급되는 쿠폰(플래시 등): fetch 시 이전 목록과 diff하여
/// 새로 추가된 쿠폰에 대해 coupon_issued 로깅
Future<void> _logNewCouponsFromDiff(
  List<UserCoupon> coupons, {
  Set<String> alreadyLogged = const {},
}) async {
  if (coupons.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final seenJson = prefs.getString(_kSeenCouponCodesKey);
    final seen = seenJson != null
        ? (jsonDecode(seenJson) as List<dynamic>?)
                ?.map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toSet() ??
            <String>{}
        : <String>{};

    final excluded = seen.union(alreadyLogged);
    final newCoupons =
        coupons.where((c) => c.code.isNotEmpty && !excluded.contains(c.code));

    for (final c in newCoupons) {
      final params = <String, Object>{
        AnalyticsEvents.paramRestaurantId: c.restaurantId ?? 0,
        AnalyticsEvents.paramCouponIssueSource: c.couponIssueSource,
        AnalyticsEvents.paramCouponCode: c.code,
      };
      AnalyticsLogger.logEvent(AnalyticsEvents.couponIssued,
          parameters: params);
    }

    final currentCodes =
        coupons.map((c) => c.code).where((s) => s.isNotEmpty).toSet();
    final updated = excluded.union(currentCodes);
    await prefs.setString(_kSeenCouponCodesKey, jsonEncode(updated.toList()));
  } catch (_) {
    // 로깅 실패는 쿠폰 조회를 막지 않음
  }
}

class CouponService {
  static Future<List<UserCoupon>> fetchMyCoupons({CouponStatus? status}) async {
    final Map<String, dynamic>? params;
    if (status != null && status != CouponStatus.unknown) {
      params = {'status': status.apiValue};
    } else {
      params = null;
    }

    try {
      // 최대 10초까지 응답을 기다리고, 그 이상 걸리면
      // 명시적으로 네트워크 타임아웃 에러를 발생시킨다.
      final http.Response response = await ApiClient.get(
        '/api/coupons/my/',
        queryParameters: params,
      ).timeout(
        const Duration(seconds: 10),
      );

      final decoded = _decodeResponseBody(response);
      List<UserCoupon> coupons;
      Set<String> alreadyLogged = {};
      if (decoded is List) {
        coupons = decoded
            .map((item) => UserCoupon.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      } else if (decoded is Map<String, dynamic>) {
        alreadyLogged = _logIssuedCouponsFromResponse(decoded);
        if (decoded['results'] is List) {
          coupons = (decoded['results'] as List)
              .map((item) =>
                  UserCoupon.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        } else {
          coupons = const [];
        }
      } else {
        coupons = const [];
      }
      await _logNewCouponsFromDiff(coupons, alreadyLogged: alreadyLogged);
      return coupons;
    } on TimeoutException catch (e) {
      // 쿠폰 전용 타임아웃은 10초로 제한하고, UI에서 새로고침을 안내하기 위해
      // 네트워크 예외로 변환해 상위에서 처리하도록 전달한다.
      throw ApiNetworkException('쿠폰 조회 요청 시간 초과: $e');
    } catch (e) {
      // 실제 사용자 쿠폰 리스트에서는 더 이상 테스트용 목업 쿠폰을 노출하지 않기 위해
      // 네트워크/인증 오류를 상위 호출자로 전달한다.
      print('CouponService: Fetch failed ($e)');
      rethrow;
    }
  }

  static List<UserCoupon> _getMockCoupons() {
    return [
      UserCoupon(
        code: 'TEST-COUPON-1234',
        status: CouponStatus.issued,
        restaurantId: 999,
        benefit: const CouponBenefitInfo(
          title: 'Test Coupon',
          subtitle: 'Welcome!',
          description: 'A mock coupon for testing purposes',
          restaurantName: 'Test Restaurant',
        ),
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      ),
    ];
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

  /// 스탬프 적립 결과. 성공 시 result, 실패 시 errorMessage (throw 없이 반환)
  static Future<StampAddResult> addStamp({
    required int restaurantId,
    required String pin,
    int count = 1,
    String? idemKey,
  }) async {
    final safeCount = count.clamp(1, 4).toInt();
    final resolvedIdemKey = (idemKey != null && idemKey.trim().isNotEmpty)
        ? idemKey.trim()
        : _generateIdempotencyKey();
    final body = <String, dynamic>{
      'restaurant_id': restaurantId,
      'pin': pin,
      'count': safeCount,
    };

    try {
      final response = await ApiClient.postWithoutThrow(
        '/api/coupons/stamps/add/',
        body: body,
        headers: {'Idempotency-Key': resolvedIdemKey},
      );
      if (response.statusCode >= 400) {
        final error = _extractApiErrorFromBody(response.body);
        final msg = error?.detail ??
            (response.statusCode == 403 || error?.code == 'invalid_pin'
                ? 'PIN 번호가 올바르지 않아요. 다시 확인해 주세요.'
                : response.statusCode == 429
                    ? '이 식당은 하루 최대 5회까지 스탬프를 적립할 수 있어요.'
                    : response.statusCode == 400 &&
                            error?.code == 'invalid_stamp_count'
                        ? '스탬프 적립 개수는 1개 이상 4개 이하만 가능해요.'
                        : '요청이 실패했어요 (HTTP ${response.statusCode})');
        return StampAddResult.failure(
          msg,
          errorCode: error?.code,
          statusCode: response.statusCode,
        );
      }
      final decoded = _decodeResponseBody(response);
      if (decoded is Map<String, dynamic>) {
        return StampAddResult.success(StampActionResult.fromJson(decoded));
      }
      return StampAddResult.success(
          const StampActionResult(ok: true, added: 0, current: 0, target: 0));
    } on ApiAuthException catch (e) {
      return StampAddResult.failure(e.message);
    } on ApiNetworkException catch (e) {
      return StampAddResult.failure('네트워크 오류: ${e.cause}');
    } catch (e) {
      return StampAddResult.failure(e.toString());
    }
  }

  /// POST /api/coupons/check/ - 쿠폰 조회/검증 (사용 직전 benefit.notes 등 최신 정보 조회)
  static Future<UserCoupon> checkCoupon({required String couponCode}) async {
    final response = await ApiClient.post(
      '/api/coupons/check/',
      body: {'coupon_code': couponCode},
    );
    final decoded = _decodeResponseBody(response);
    if (decoded is Map<String, dynamic>) {
      return UserCoupon.fromJson(decoded);
    }
    throw ApiHttpException(response.statusCode, response.body);
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

  /// 쿠폰 사용 시도. throw 없이 성공/실패 반환 (PIN 오류 등 입력창 내 에러 표시용)
  static Future<CouponRedeemAttemptResult> redeemCouponWithoutThrow({
    required String couponCode,
    required int restaurantId,
    required String pin,
  }) async {
    try {
      final response = await ApiClient.postWithoutThrow(
        '/api/coupons/redeem/',
        body: {
          'coupon_code': couponCode,
          'restaurant_id': restaurantId,
          'pin': pin,
        },
      );
      if (response.statusCode >= 400) {
        final msg = _extractDetailFromBody(response.body) ??
            (response.statusCode == 400 || response.statusCode == 401
                ? '비밀번호가 올바르지 않아요. 다시 확인해 주세요.'
                : '요청이 실패했어요 (HTTP ${response.statusCode})');
        return CouponRedeemAttemptResult.failure(msg);
      }
      final decoded = _decodeResponseBody(response);
      if (decoded is Map<String, dynamic>) {
        return CouponRedeemAttemptResult.success(
            CouponRedeemResult.fromJson(decoded));
      }
      return CouponRedeemAttemptResult.success(
          CouponRedeemResult(ok: true, couponCode: couponCode));
    } on ApiAuthException catch (e) {
      return CouponRedeemAttemptResult.failure(e.message);
    } on ApiNetworkException catch (e) {
      return CouponRedeemAttemptResult.failure('네트워크 오류: ${e.cause}');
    } catch (e) {
      return CouponRedeemAttemptResult.failure(e.toString());
    }
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

  /// POST /api/coupons/signup/complete/ - 회원가입 완료 시 쿠폰 발급
  static Future<Map<String, dynamic>> signupComplete() async {
    final response = await ApiClient.post(
      '/api/coupons/signup/complete/',
      body: <String, dynamic>{},
    );
    final decoded = _decodeResponseBody(response);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final logged = _logIssuedCouponsFromResponse(map);
    await markCouponsAsSeen(logged);
    return map;
  }

  /// POST /api/coupons/referrals/qualify/ - 친구초대 자격 확인 시 쿠폰 발급
  static Future<Map<String, dynamic>> referralsQualify() async {
    final response = await ApiClient.post(
      '/api/coupons/referrals/qualify/',
      body: <String, dynamic>{},
    );
    final decoded = _decodeResponseBody(response);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final logged = _logIssuedCouponsFromResponse(map);
    await markCouponsAsSeen(logged);
    return map;
  }

  /// POST /api/coupons/flash/claim/ - 플래시 쿠폰 수령
  static Future<Map<String, dynamic>> flashClaim() async {
    final response = await ApiClient.post(
      '/api/coupons/flash/claim/',
      body: <String, dynamic>{},
    );
    final decoded = _decodeResponseBody(response);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final logged = _logIssuedCouponsFromResponse(map);
    await markCouponsAsSeen(logged);
    return map;
  }

  /// POST /api/coupons/final-exam/claim/ - 기말고사 쿠폰 수령
  static Future<Map<String, dynamic>> finalExamClaim() async {
    final response = await ApiClient.post(
      '/api/coupons/final-exam/claim/',
      body: <String, dynamic>{},
    );
    final decoded = _decodeResponseBody(response);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final logged = _logIssuedCouponsFromResponse(map);
    await markCouponsAsSeen(logged);
    return map;
  }

  /// 다른 경로(추천인 입력 등)에서 coupon_issued 로깅한 코드를 등록.
  /// 이후 fetchMyCoupons diff 시 중복 로깅 방지.
  static Future<void> markCouponsAsSeen(Iterable<String> codes) async {
    if (codes.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenJson = prefs.getString(_kSeenCouponCodesKey);
      final seen = seenJson != null
          ? (jsonDecode(seenJson) as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .where((s) => s.isNotEmpty)
                  .toSet() ??
              <String>{}
          : <String>{};
      final updated = seen.union(codes.where((s) => s.isNotEmpty).toSet());
      await prefs.setString(_kSeenCouponCodesKey, jsonEncode(updated.toList()));
    } catch (_) {}
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

String _generateIdempotencyKey() {
  final random = Random.secure();
  String part(int len) {
    const chars = '0123456789abcdef';
    return List.generate(len, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  // UUID v4 형태(8-4-4-4-12)로 생성해 중복 요청 방지 키로 사용.
  return '${part(8)}-${part(4)}-${part(4)}-${part(4)}-${part(12)}';
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

String? _extractDetailFromBody(String body) {
  if (body.isEmpty) return null;
  final trimmed = body.trim();
  // JSON이 아니면 (ValidationError 등) 기술 문구를 사용자 친화 문구로 변환
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    final friendly = _toUserFriendlyMessage(trimmed);
    return friendly != trimmed ? friendly : null;
  }
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      for (final key in ['detail', 'message', 'error']) {
        final value = decoded[key];
        if (value is String && value.isNotEmpty) {
          return _toUserFriendlyMessage(value);
        }
        if (value is List && value.isNotEmpty) {
          final first = value.first;
          if (first is String && first.isNotEmpty) {
            return _toUserFriendlyMessage(first);
          }
        }
      }
    }
  } catch (_) {}
  return null;
}

class _ApiErrorPayload {
  const _ApiErrorPayload({
    this.detail,
    this.code,
  });

  final String? detail;
  final String? code;
}

_ApiErrorPayload? _extractApiErrorFromBody(String body) {
  if (body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final detail = _extractDetailFromBody(body);
    final rawCode = decoded['code'];
    final code = rawCode is String && rawCode.isNotEmpty ? rawCode : null;
    return _ApiErrorPayload(detail: detail, code: code);
  } catch (_) {
    return null;
  }
}

/// 기술적 에러 문구를 사용자 친화 문구로 변환 (식당 상세 진입 후이므로 PIN 관련 문구만)
String _toUserFriendlyMessage(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('invalid merchant code') ||
      (lower.contains('invalid') &&
          (lower.contains('pin') || lower.contains('password'))) ||
      lower.contains('validationerror') ||
      lower.contains('request method') ||
      lower.contains('/api/')) {
    return '비밀번호가 올바르지 않아요. 다시 확인해 주세요.';
  }
  return raw;
}

/// visit_range "1_4" 또는 "1-4" 형식 파싱 → (minVisit, maxVisit)
(int?, int?) _parseVisitRange(String s) {
  final parts = s.split(RegExp(r'[_\-\s]+'));
  if (parts.length >= 2) {
    final min = int.tryParse(parts[0].trim());
    final max = int.tryParse(parts[1].trim());
    if (min != null && max != null) return (min, max);
  }
  if (parts.length == 1) {
    final single = int.tryParse(parts[0].trim());
    if (single != null) return (single, single);
  }
  return (null, null);
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
