import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/coupon_service.dart';

void main() {
  test('LimitedCouponOffer needsSelection only when unclaimed with restaurants', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'SPECIAL_APRIL',
      'coupon_type_title': '4월 한정쿠폰',
      'valid_days': 8,
      'claimed': false,
      'redeem_bonus': true,
      'restaurants': [
        {
          'restaurant_id': 12,
          'name': '한끼갈비',
          'category': '한식',
          'zone': '신촌',
          'title': '음료 한 잔',
          'subtitle': '메인 주문 시',
        },
      ],
    });
    expect(offer.needsSelection, isTrue);
    expect(offer.redeemBonus, isTrue);
    expect(offer.validDays, 8);
    expect(offer.restaurants.single.name, '한끼갈비');
    expect(offer.restaurants.single.benefitLine, '음료 한 잔 · 메인 주문 시');
  });

  test('claimed offer does not need selection', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'SPECIAL_APRIL',
      'claimed': true,
      'redeem_bonus': false,
      'restaurants': [
        {'restaurant_id': 1, 'name': 'A'},
      ],
      'issued_coupons': [
        {
          'code': 'ABC',
          'restaurant_id': 1,
          'coupon_type_code': 'SPECIAL_APRIL',
        },
      ],
    });
    expect(offer.needsSelection, isFalse);
    expect(offer.issuedCoupons.single.code, 'ABC');
  });

  test('empty restaurants skips selection UI', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'SPECIAL_APRIL',
      'claimed': false,
      'restaurants': [],
    });
    expect(offer.needsSelection, isFalse);
  });

  test('CouponRedeemResult parses bonus_coupon', () {
    final result = CouponRedeemResult.fromJson({
      'ok': true,
      'coupon_code': 'USED-1',
      'bonus_coupon': {
        'code': 'BONUS-2',
        'status': 'ISSUED',
        'restaurant_id': 456,
        'restaurant_name': '고니식탁',
        'issue_key': 'LIMITED_BONUS:SPECIAL_APRIL',
        'coupon_type_code': 'SPECIAL_APRIL',
        'benefit': {
          'is_bonus': true,
          'bonus_source_coupon_code': 'USED-1',
          'subtitle': '🎁 한정쿠폰 사용 보너스',
          'title': '음료 한 잔',
          'restaurant_name': '고니식탁',
        },
      },
    });
    expect(result.bonusCoupon, isNotNull);
    expect(result.bonusCoupon!.isLimitedBonus, isTrue);
    expect(result.bonusCoupon!.benefit?.isBonus, isTrue);
    expect(result.bonusCoupon!.benefit?.restaurantNameText, '고니식탁');
    expect(result.bonusCoupon!.benefit?.resolvedSubtitle, '🎁 한정쿠폰 사용 보너스');
  });

  test('CouponRedeemResult without bonus_coupon stays empty', () {
    final result = CouponRedeemResult.fromJson({
      'ok': true,
      'coupon_code': 'USED-1',
    });
    expect(result.bonusCoupon, isNull);
  });

  test('app-open offer without pick fields stays single pick', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'SPECIAL_APRIL',
      'claimed': false,
      'restaurants': [
        {'restaurant_id': 1, 'name': 'A'},
        {'restaurant_id': 2, 'name': 'B'},
      ],
    });
    expect(offer.picksNeeded, 1);
    expect(offer.isMultiPick, isFalse);
    expect(offer.tagLabel, '한정쿠폰');
  });

  test('student council code offer asks for remaining picks', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'KNUSCSEPT',
      'coupon_type_title': '[학생회 전용 쿠폰 ✨]',
      'claimed': false,
      'source': 'CODE',
      'event_kind': 'student_council',
      'pick_count': 3,
      'remaining_count': 2,
      'restaurants': [
        {'restaurant_id': 1, 'name': 'A'},
        {'restaurant_id': 2, 'name': 'B'},
        {'restaurant_id': 3, 'name': 'C'},
      ],
    });
    expect(offer.needsSelection, isTrue);
    expect(offer.picksNeeded, 2);
    expect(offer.isMultiPick, isTrue);
    expect(offer.tagLabel, '학생회 쿠폰');
  });

  test('picks are capped by available restaurants', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'KNUSCSEPT',
      'claimed': false,
      'source': 'CODE',
      'pick_count': 3,
      'remaining_count': 3,
      'restaurants': [
        {'restaurant_id': 1, 'name': 'A'},
      ],
    });
    expect(offer.picksNeeded, 1);
    expect(offer.isMultiPick, isFalse);
  });

  test('referral accept parses select_offer', () {
    final res = ReferralAcceptResponse.fromJson({
      'ok': true,
      'code_kind': 'event',
      'event_kind': 'student_council',
      'select_offer': {
        'coupon_type_code': 'KNUSCSEPT',
        'claimed': false,
        'pick_count': 3,
        'remaining_count': 3,
        'restaurants': [
          {'restaurant_id': 1, 'name': 'A'},
        ],
      },
    });
    expect(res.issuedCouponCodes, isEmpty);
    expect(res.selectOffer?.couponTypeCode, 'KNUSCSEPT');
    expect(res.selectOffer?.pickCount, 3);
  });

  test('limitedClaimErrorMessage prefers detail', () {
    expect(
      limitedClaimErrorMessage('invalid_restaurant', '목록에 없는 식당이에요'),
      '목록에 없는 식당이에요',
    );
    expect(limitedClaimErrorMessage('not_in_window', null), '기획전 기간이 아니에요.');
  });

  test('limitedClaimErrorMessage covers campus_required and in_progress', () {
    expect(
      limitedClaimErrorMessage('campus_required', null),
      '대학가를 먼저 등록하면 쿠폰을 받을 수 있어요.',
    );
    expect(
      limitedClaimErrorMessage('in_progress', null),
      '쿠폰을 받는 중이에요. 잠시 후 다시 시도해 주세요.',
    );
  });

  test('TUE_THU_GENERAL_SELECT offer parses daily-only fields and tag', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'TUE_THU_GENERAL_SELECT',
      'coupon_type_title': '화·목 골라받기 쿠폰',
      'valid_days': 1,
      'valid_hours': 24,
      'period': 'DAILY',
      'restaurant_kind': 'GENERAL',
      'claim_ends_at': '2026-10-06T23:59:59+09:00',
      'claimed': false,
      'redeem_bonus': false,
      'user_campus': '경북대',
      'campus_required': false,
      'restaurants': [
        {'restaurant_id': 12, 'name': '식당이름', 'title': '3,000원 할인'},
      ],
      'issued_coupons': [],
    });
    expect(offer.isTueThuGeneralSelect, isTrue);
    expect(offer.tagLabel, '화·목 골라받기 쿠폰');
    expect(offer.validHours, 24);
    expect(offer.period, 'DAILY');
    expect(offer.userCampus, '경북대');
    expect(offer.campusRequired, isFalse);
    expect(offer.claimEndsAt, isNotNull);
    expect(offer.needsSelection, isTrue);
    expect(offer.needsCampusRegistration, isFalse);
  });

  test('campus_required offer with empty restaurants skips picker but needs campus prompt', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'TUE_THU_GENERAL_SELECT',
      'claimed': false,
      'user_campus': null,
      'campus_required': true,
      'restaurants': [],
    });
    expect(offer.needsSelection, isFalse);
    expect(offer.needsCampusRegistration, isTrue);
  });

  test('claimed TUE_THU offer never needs campus prompt or selection again', () {
    final offer = LimitedCouponOffer.fromJson({
      'coupon_type_code': 'TUE_THU_GENERAL_SELECT',
      'claimed': true,
      'campus_required': false,
      'restaurants': [
        {'restaurant_id': 12, 'name': '식당이름'},
      ],
      'issued_coupons': [
        {'code': 'ABC', 'restaurant_id': 12, 'coupon_type_code': 'TUE_THU_GENERAL_SELECT'},
      ],
    });
    expect(offer.needsSelection, isFalse);
    expect(offer.needsCampusRegistration, isFalse);
    expect(offer.issuedCoupons.single.restaurantId, 12);
  });
}
