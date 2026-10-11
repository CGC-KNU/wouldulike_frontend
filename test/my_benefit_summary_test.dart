import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/widgets/my_benefit_summary_card.dart';

UserCoupon _coupon(String code, int rid, DateTime exp,
        {CouponStatus status = CouponStatus.issued}) =>
    UserCoupon(code: code, status: status, restaurantId: rid, expiresAt: exp);

StampStatus _stamp(int current, int target) => StampStatus(
      current: current,
      target: target,
      rewards: const [],
    );

void main() {
  final now = DateTime(2026, 10, 10, 12);
  String nameOf(int id) => {1: '라라더', 2: '핵밥', 3: '정든밤'}[id] ?? '매장 $id';

  test('쿠폰 수·오늘 만료·매장 이름을 센다 (사용 가능 쿠폰만)', () {
    final s = MyBenefitSummary.from(
      coupons: [
        _coupon('a', 1, DateTime(2026, 10, 10, 23, 59)),
        _coupon('b', 2, DateTime(2026, 10, 13)),
        _coupon('c', 2, DateTime(2026, 10, 14)),
        _coupon('d', 3, DateTime(2026, 10, 10, 23, 59),
            status: CouponStatus.redeemed),
      ],
      stampStatuses: const {},
      restaurantName: nameOf,
      now: now,
    );
    expect(s.couponCount, 3);
    expect(s.expiringTodayCount, 1);
    expect(s.couponStoreNames, ['라라더', '핵밥']);
  });

  test('이미 지난 시각은 오늘 만료로 세지 않는다', () {
    final s = MyBenefitSummary.from(
      coupons: [_coupon('a', 1, DateTime(2026, 10, 10, 9))],
      stampStatuses: const {},
      restaurantName: nameOf,
      now: now,
    );
    expect(s.expiringTodayCount, 0);
  });

  test('스탬프는 진행도 높은 순으로 최대 2개, 0개 매장은 제외', () {
    final s = MyBenefitSummary.from(
      coupons: const [],
      stampStatuses: {1: _stamp(2, 3), 2: _stamp(0, 5), 3: _stamp(3, 10)},
      restaurantName: nameOf,
      now: now,
    );
    expect(s.stamps.map((e) => e.name), ['정든밤', '라라더']);
    expect(s.stamps.first.total, 10);
    expect(s.isEmpty, isFalse);
  });

  test('아무것도 없으면 isEmpty', () {
    final s = MyBenefitSummary.from(
      coupons: const [],
      stampStatuses: const {},
      restaurantName: nameOf,
      now: now,
    );
    expect(s.isEmpty, isTrue);
  });

  testWidgets('카드가 쿠폰 수·오늘 만료 배지·스탬프를 보여준다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyBenefitSummaryCard(
          summary: MyBenefitSummary(
            couponCount: 3,
            couponStoreNames: const ['라라더', '핵밥'],
            expiringTodayCount: 1,
            stamps: const [(name: '라라더', current: 2, total: 3)],
          ),
        ),
      ),
    ));
    expect(find.text('내 쿠폰 3장', findRichText: true), findsOneWidget);
    expect(find.text('라라더 · 핵밥'), findsOneWidget);
    expect(find.text('오늘 만료 1'), findsOneWidget);
    expect(find.text('라라더 2/3'), findsOneWidget);
  });
}
