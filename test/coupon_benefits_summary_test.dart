import 'package:flutter_test/flutter_test.dart';
import 'package:new1/models/coupon_benefits_summary.dart';

const burritoSummaryFixture = r'''
{"stamp": {"notes": "", "enabled": true, "rewards": [{"notes": "", "title": "치킨 부리또 1개", "stamps": 7, "benefit": {"type": "fixed", "value": 3000}, "subtitle": "", "coupon_type_code": "STAMP_REWARD_7"}], "rule_type": "THRESHOLD", "cycle_target": 7}, "signup": {"items": [{"notes": "부리또 1개 주문시", "title": "음료수", "benefit": {"description": "신규가입 시 음료수 제공"}, "subtitle": "신규가입 고객 전용", "sort_order": 0}], "eligible": true, "excluded": false, "coupon_type_code": "WELCOME_3000"}, "referral": {"referee": {"items": [{"notes": "부리또 1개 주문시", "title": "음료수", "benefit": {"description": "피추천인"}, "subtitle": "친구초대(피추천인) 보상", "sort_order": 0}], "eligible": true, "excluded": false, "coupon_type_code": "REFERRAL_BONUS_REFEREE"}, "referrer": {"items": [{"notes": "부리또 1개 주문시", "title": "음료수", "benefit": {"description": "추천인"}, "subtitle": "친구초대(추천인) 보상", "sort_order": 0}], "eligible": true, "excluded": false, "coupon_type_code": "REFERRAL_BONUS_REFERRER"}}, "generated_at": "2026-05-19T03:29:00.683099+00:00", "restaurant_id": 41}
''';

void main() {
  test('tryParse keeps signup and referral sections', () {
    final summary = CouponBenefitsSummary.tryParse(burritoSummaryFixture);
    expect(summary, isNotNull);
    expect(summary!.signup.shouldDisplay, isTrue);
    expect(summary.referral.referrer.shouldDisplay, isTrue);
    expect(summary.referral.referee.shouldDisplay, isTrue);
    expect(summary.stamp.hasRewardList, isTrue);
  });
}
