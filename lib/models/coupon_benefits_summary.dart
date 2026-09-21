import 'dart:convert';

import 'package:new1/services/coupon_service.dart';

class CouponBenefitItem {
  const CouponBenefitItem({
    required this.title,
    required this.subtitle,
    required this.notes,
    required this.benefit,
    required this.sortOrder,
  });

  factory CouponBenefitItem.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> benefit = const {};
    final rawBenefit = json['benefit'];
    if (rawBenefit is Map<String, dynamic>) {
      benefit = rawBenefit;
    } else if (rawBenefit is Map) {
      benefit = Map<String, dynamic>.from(rawBenefit);
    }

    return CouponBenefitItem(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      benefit: benefit,
      sortOrder: _parseInt(json['sort_order']),
    );
  }

  final String title;
  final String subtitle;
  final String notes;
  final Map<String, dynamic> benefit;
  final int sortOrder;
}

class CouponTypeSection {
  const CouponTypeSection({
    required this.couponTypeCode,
    required this.eligible,
    required this.excluded,
    required this.items,
  });

  factory CouponTypeSection.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CouponTypeSection(
        couponTypeCode: '',
        eligible: false,
        excluded: false,
        items: [],
      );
    }

    final rawItems = json['items'];
    final items = <CouponBenefitItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(CouponBenefitItem.fromJson(item));
        } else if (item is Map) {
          items.add(
            CouponBenefitItem.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return CouponTypeSection(
      couponTypeCode: json['coupon_type_code']?.toString() ?? '',
      eligible: json['eligible'] == true,
      excluded: json['excluded'] == true,
      items: items,
    );
  }

  final String couponTypeCode;
  final bool eligible;
  final bool excluded;
  final List<CouponBenefitItem> items;

  bool get shouldDisplay => !excluded && items.isNotEmpty;
}

class ReferralBenefits {
  const ReferralBenefits({
    required this.referrer,
    required this.referee,
  });

  factory ReferralBenefits.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ReferralBenefits(
        referrer: CouponTypeSection(
          couponTypeCode: '',
          eligible: false,
          excluded: false,
          items: [],
        ),
        referee: CouponTypeSection(
          couponTypeCode: '',
          eligible: false,
          excluded: false,
          items: [],
        ),
      );
    }

    return ReferralBenefits(
      referrer: CouponTypeSection.fromJson(
        json['referrer'] is Map<String, dynamic>
            ? json['referrer'] as Map<String, dynamic>
            : json['referrer'] is Map
                ? Map<String, dynamic>.from(json['referrer'] as Map)
                : null,
      ),
      referee: CouponTypeSection.fromJson(
        json['referee'] is Map<String, dynamic>
            ? json['referee'] as Map<String, dynamic>
            : json['referee'] is Map
                ? Map<String, dynamic>.from(json['referee'] as Map)
                : null,
      ),
    );
  }

  final CouponTypeSection referrer;
  final CouponTypeSection referee;
}

class CouponBenefitsStampSection {
  const CouponBenefitsStampSection({
    required this.enabled,
    required this.ruleType,
    required this.notes,
    required this.cycleTarget,
    required this.rewards,
  });

  factory CouponBenefitsStampSection.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CouponBenefitsStampSection(
        enabled: false,
        ruleType: null,
        notes: '',
        cycleTarget: null,
        rewards: [],
      );
    }

    final rawRewards = json['rewards'];
    final rewards = <StampReward>[];
    if (rawRewards is List) {
      for (final reward in rawRewards) {
        if (reward is Map<String, dynamic>) {
          rewards.add(StampReward.fromJson(reward));
        } else if (reward is Map) {
          rewards.add(
            StampReward.fromJson(Map<String, dynamic>.from(reward)),
          );
        }
      }
    }

    return CouponBenefitsStampSection(
      enabled: json['enabled'] == true,
      ruleType: json['rule_type']?.toString(),
      notes: json['notes']?.toString() ?? '',
      cycleTarget: _parseOptionalInt(json['cycle_target']),
      rewards: rewards,
    );
  }

  final bool enabled;
  final String? ruleType;
  final String notes;
  final int? cycleTarget;
  final List<StampReward> rewards;

  bool get hasRewardList => enabled && rewards.isNotEmpty;

  bool get hasNotesOnly => !enabled && notes.trim().isNotEmpty;
}

/// 개인 스탬프 현황(GET /api/coupons/stamps/my/)에 판 정보가 없을 때
/// 매장 공개 혜택 요약(coupon_benefits_summary.stamp)으로 판을 채운다.
/// 비로그인·미적립 상태에서도 "몇 개 모으면 무슨 리워드"를 서버 값대로 보여주기 위함.
StampStatus resolveStampStatus({
  required StampStatus? personal,
  required CouponBenefitsStampSection? summary,
  int fallbackCurrent = 0,
}) {
  if (personal != null && personal.boardLength > 0) return personal;

  final enabled = summary?.enabled == true;
  final rewards = (personal != null && personal.rewards.isNotEmpty)
      ? personal.rewards
      : (enabled ? summary!.rewards : const <StampReward>[]);
  final target = (personal?.target ?? 0) > 0
      ? personal!.target
      : (enabled ? (summary!.cycleTarget ?? 0) : 0);
  final summaryNotes = summary?.notes.trim() ?? '';
  return StampStatus(
    current: personal?.current ?? fallbackCurrent,
    target: target,
    updatedAt: personal?.updatedAt,
    rewardCoupons: personal?.rewardCoupons ?? const [],
    rewards: rewards,
    notes: personal?.notes ?? (summaryNotes.isNotEmpty ? summaryNotes : null),
  );
}

class CouponBenefitsSummary {
  const CouponBenefitsSummary({
    required this.restaurantId,
    required this.generatedAt,
    required this.signup,
    required this.referral,
    required this.stamp,
  });

  /// API가 Map 또는 JSON 문자열로 내려줄 수 있음
  static CouponBenefitsSummary? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is CouponBenefitsSummary) return raw;
    if (raw is Map<String, dynamic>) {
      return CouponBenefitsSummary.fromJson(raw);
    }
    if (raw is Map) {
      return CouponBenefitsSummary.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        return tryParse(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  factory CouponBenefitsSummary.fromJson(Map<String, dynamic> json) {
    return CouponBenefitsSummary(
      restaurantId: _parseInt(json['restaurant_id']),
      generatedAt: json['generated_at']?.toString() ?? '',
      signup: CouponTypeSection.fromJson(
        json['signup'] is Map<String, dynamic>
            ? json['signup'] as Map<String, dynamic>
            : json['signup'] is Map
                ? Map<String, dynamic>.from(json['signup'] as Map)
                : null,
      ),
      referral: ReferralBenefits.fromJson(
        json['referral'] is Map<String, dynamic>
            ? json['referral'] as Map<String, dynamic>
            : json['referral'] is Map
                ? Map<String, dynamic>.from(json['referral'] as Map)
                : null,
      ),
      stamp: CouponBenefitsStampSection.fromJson(
        json['stamp'] is Map<String, dynamic>
            ? json['stamp'] as Map<String, dynamic>
            : json['stamp'] is Map
                ? Map<String, dynamic>.from(json['stamp'] as Map)
                : null,
      ),
    );
  }

  final int restaurantId;
  final String generatedAt;
  final CouponTypeSection signup;
  final ReferralBenefits referral;
  final CouponBenefitsStampSection stamp;

  bool get hasVisibleContent {
    if (signup.shouldDisplay) return true;
    if (referral.referrer.shouldDisplay || referral.referee.shouldDisplay) {
      return true;
    }
    if (stamp.hasRewardList || stamp.hasNotesOnly) return true;
    return false;
  }

  static bool itemsEqual(List<CouponBenefitItem> a, List<CouponBenefitItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.title != right.title ||
          left.subtitle != right.subtitle ||
          left.notes != right.notes ||
          left.sortOrder != right.sortOrder) {
        return false;
      }
    }
    return true;
  }
}

class CouponBenefitsSummaryFormat {
  static String formatBenefitValue(Map<String, dynamic> benefit) {
    final type = benefit['type']?.toString();
    if (type == 'fixed') {
      final value = benefit['value'];
      final amount = _parseInt(value);
      if (amount <= 0) return '매장 안내';
      return '${_formatThousands(amount)}원';
    }

    final description = benefit['description']?.toString().trim() ?? '';
    if (description.isNotEmpty) return description;

    return '';
  }

  static String stampRewardStepLabel(StampReward reward, String? ruleType) {
    final isVisit = ruleType == 'VISIT' || reward.isVisitPattern;
    if (isVisit) {
      final min = reward.minVisit;
      final max = reward.maxVisit;
      if (min != null && max != null) {
        if (min == max) return '$min회 방문 시';
        return '$min~$max회 방문 시';
      }
      if (min != null) return '$min회 방문 시';
      if (reward.visitRange != null && reward.visitRange!.isNotEmpty) {
        return '${reward.visitRange!.replaceAll('_', '~')}회 방문 시';
      }
    }

    if (reward.stamps != null && reward.stamps! > 0) {
      return '${reward.stamps}개 적립 시';
    }
    return '';
  }

  static String rewardDisplayTitle(StampReward reward) {
    final title = reward.title?.trim() ?? '';
    final subtitle = reward.subtitle?.trim() ?? '';
    if (title.isNotEmpty && subtitle.isNotEmpty) {
      return '$title · $subtitle';
    }
    if (title.isNotEmpty) return title;
    if (subtitle.isNotEmpty) return subtitle;
    return '리워드 혜택';
  }

  static String _formatThousands(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final positionFromEnd = text.length - i;
      if (i > 0 && positionFromEnd % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(text[i]);
    }
    return buffer.toString();
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _parseOptionalInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
