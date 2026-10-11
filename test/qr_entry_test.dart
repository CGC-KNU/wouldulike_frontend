import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/qr_entry_sheet.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/mileage_service.dart';

QrEntry _entry(QrEntryBranch b, {QrEntryStamp stamp = const QrEntryStamp()}) =>
    QrEntry(branch: b, restaurantId: 7, couponCode: 'C1', stamp: stamp);

Future<QrEntryAction?> _open(
  WidgetTester tester,
  QrEntry entry, {
  UserCoupon? coupon,
  String? tap,
}) async {
  QrEntryAction? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => result = await showQrEntrySheet(
            context,
            entry: entry,
            restaurantName: '라라더',
            coupon: coupon,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (tap != null) {
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  group('QrEntry.fromJson', () {
    test('서버 분기와 스탬프 진행을 읽는다', () {
      final e = QrEntry.fromJson({
        'branch': 'stamp_progress',
        'restaurant_id': 7,
        'coupon_code': 'C9',
        'coupon_is_reward': true,
        'stamp': {
          'enabled': true,
          'current': 2,
          'target': 3,
          'remaining': 1,
          'next_reward': '에이드 1잔',
          'stamped_today': false,
          'last_visit_at': '2026-09-30T12:00:00+09:00',
        },
      });
      expect(e.branch, QrEntryBranch.stampProgress);
      expect(e.couponCode, 'C9');
      expect(e.couponIsReward, isTrue);
      expect(e.stamp.current, 2);
      expect(e.stamp.nextReward, '에이드 1잔');
      expect(e.stamp.lastVisitAt, isNotNull);
    });

    test('모르는 분기는 none (막다른 화면 대신 매장만)', () {
      expect(QrEntryBranch.parse('weird'), QrEntryBranch.none);
      expect(QrEntryBranch.parse(null), QrEntryBranch.none);
    });
  });

  test('만료 문구: 오늘이면 시각, 아니면 날짜', () {
    final now = DateTime(2026, 10, 10, 12);
    expect(QrEntrySheet.expiryText(DateTime(2026, 10, 10, 23, 59), now),
        '오늘 23:59까지');
    expect(QrEntrySheet.expiryText(DateTime(2026, 10, 14), now), '10월 14일까지');
  });

  testWidgets('쿠폰 도착: 혜택·"지금 쓰기"·스탬프 안내, 누르면 useCoupon', (tester) async {
    final coupon = UserCoupon(
      code: 'C1',
      status: CouponStatus.issued,
      restaurantId: 7,
      expiresAt: DateTime.now().add(const Duration(hours: 3)),
      benefit: const CouponBenefitInfo(title: '음료 1잔 무료'),
    );
    final result = await _open(
      tester,
      _entry(QrEntryBranch.couponArrived,
          stamp: const QrEntryStamp(enabled: true, current: 0, target: 3)),
      coupon: coupon,
      tap: '지금 쓰기',
    );
    expect(result, QrEntryAction.useCoupon);
  });

  testWidgets('쿠폰 도착 화면 문구', (tester) async {
    await _open(
      tester,
      _entry(QrEntryBranch.couponArrived,
          stamp: const QrEntryStamp(enabled: true, current: 0, target: 3)),
      coupon: UserCoupon(
        code: 'C1',
        status: CouponStatus.issued,
        expiresAt: DateTime.now().add(const Duration(hours: 3)),
        benefit: const CouponBenefitInfo(title: '음료 1잔 무료'),
      ),
    );
    expect(find.text('쿠폰이 도착했어요'), findsOneWidget);
    expect(find.text('음료 1잔 무료'), findsOneWidget);
    expect(find.text('나중에 쓸게요'), findsOneWidget);
    expect(find.text('스탬프 0/3 · 계산하고 바로 적립'), findsOneWidget);
  });

  UserCoupon heldCoupon() => UserCoupon(
        code: 'C1',
        status: CouponStatus.issued,
        restaurantId: 7,
        expiresAt: DateTime.now().add(const Duration(hours: 3)),
        benefit: const CouponBenefitInfo(title: '음료 1잔 무료'),
      );

  const progress = QrEntryStamp(
    enabled: true,
    current: 2,
    target: 3,
    remaining: 1,
    nextReward: '에이드 1잔',
  );

  testWidgets('재방문(쿠폰 없음): 스탬프 적립 시트', (tester) async {
    final result = await _open(
      tester,
      _entry(QrEntryBranch.stampProgress, stamp: progress),
      tap: '스탬프 찍기',
    );
    expect(result, QrEntryAction.addStamp);
  });

  testWidgets('재방문(쿠폰 보유): 스탬프 시트에서 쿠폰을 함께 쓰도록 유도', (tester) async {
    await _open(
      tester,
      _entry(QrEntryBranch.stampProgress, stamp: progress),
      coupon: heldCoupon(),
    );
    expect(find.textContaining('오늘 찍으면'), findsOneWidget);
    expect(find.text('갖고 계신 쿠폰'), findsOneWidget);
    expect(find.text('음료 1잔 무료'), findsOneWidget);
    expect(find.text('쿠폰 쓰고 스탬프도 찍기'), findsOneWidget);
    expect(find.text('스탬프만 찍기'), findsOneWidget);
    // 첫 방문 시트의 문구는 나오지 않는다
    expect(find.text('쿠폰이 도착했어요'), findsNothing);
  });

  testWidgets('"쿠폰 쓰고 스탬프도 찍기"는 함께 처리 행동을 돌려준다', (tester) async {
    final result = await _open(
      tester,
      _entry(QrEntryBranch.stampProgress, stamp: progress),
      coupon: heldCoupon(),
      tap: '쿠폰 쓰고 스탬프도 찍기',
    );
    expect(result, QrEntryAction.useCouponWithStamp);
  });

  testWidgets('"스탬프만 찍기"는 스탬프만 처리한다', (tester) async {
    final result = await _open(
      tester,
      _entry(QrEntryBranch.stampProgress, stamp: progress),
      coupon: heldCoupon(),
      tap: '스탬프만 찍기',
    );
    expect(result, QrEntryAction.addStamp);
  });

  testWidgets('보상 쿠폰이면 문구가 달라진다', (tester) async {
    await _open(
      tester,
      QrEntry(
        branch: QrEntryBranch.stampProgress,
        restaurantId: 7,
        couponCode: 'C1',
        couponIsReward: true,
        stamp: progress,
      ),
      coupon: heldCoupon(),
    );
    expect(find.text('스탬프 보상 쿠폰이 도착해 있어요'), findsOneWidget);
  });

  testWidgets('오늘 적립 완료 + 쿠폰 보유: 쿠폰만 쓰도록', (tester) async {
    final result = await _open(
      tester,
      _entry(QrEntryBranch.stampDoneToday,
          stamp: const QrEntryStamp(
              enabled: true, current: 3, target: 3, stampedToday: true)),
      coupon: heldCoupon(),
      tap: '쿠폰 쓰기',
    );
    expect(result, QrEntryAction.useCoupon);
  });

  testWidgets('오늘 적립 완료(쿠폰 없음): 매장 보기만 있다', (tester) async {
    await _open(
      tester,
      _entry(QrEntryBranch.stampDoneToday,
          stamp: const QrEntryStamp(
              enabled: true, current: 3, target: 3, stampedToday: true)),
    );
    expect(find.text('오늘 적립 완료!'), findsOneWidget);
    expect(find.text('매장 보기'), findsOneWidget);
    expect(find.text('스탬프 찍기'), findsNothing);
  });
}
