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
}
