import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/qr_entry_sheet.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/services/mileage_service.dart';

/// QR 진입 시나리오 (앱 쪽).
///
/// 서버 `coupons/test_qr_scenarios.py` 가 내려주는 `entry` 모양 그대로의 JSON 을 받아,
/// 링크 해석 → 분기 → 시트 문구·버튼이 시나리오대로 나오는지 본다.
void main() {
  // ── 링크 해석: 매장 QR 스티커 ─────────────────────────────────────
  group('QR 링크 해석', () {
    final qr = Uri.parse(
        'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=7&src=qr');

    test('QR 링크는 그 매장 상세로 가고 src=qr 이 서버로 전달된다', () {
      final target = resolveWouldUlikeDeepLink(qr);
      expect(target?.screen, DeepLinkScreen.restaurantDetail);
      expect(target?.restaurantId, 7);
      final src = resolveDeepLinkSource(qr);
      expect(src, 'qr');
      expect(qrVisitServerSource(src), 'qr');
    });

    test('src 없는 옛 스티커는 매장으로는 가지만 출처는 보내지 않는다', () {
      final old = Uri.parse(
          'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=7');
      expect(resolveWouldUlikeDeepLink(old)?.restaurantId, 7);
      expect(qrVisitServerSource(resolveDeepLinkSource(old)), isNull);
    });
  });

  // ── 시나리오: 서버 entry JSON → 시트 ──────────────────────────────
  Map<String, dynamic> entryJson(
    String branch, {
    String? coupon,
    bool reward = false,
    Map<String, dynamic>? stamp,
  }) =>
      {
        'branch': branch,
        'restaurant_id': 7,
        'coupon_code': coupon,
        'coupon_is_reward': reward,
        'stamp': {
          'enabled': true,
          'current': 0,
          'target': 3,
          'remaining': 3,
          'next_reward': '에이드 1잔',
          'stamped_today': false,
          'last_visit_at': null,
          ...?stamp,
        },
      };

  UserCoupon coupon({String code = 'C1'}) => UserCoupon(
        code: code,
        status: CouponStatus.issued,
        restaurantId: 7,
        expiresAt: DateTime.now().add(const Duration(hours: 5)),
        benefit: const CouponBenefitInfo(title: '음료 1잔 무료'),
      );

  Future<QrEntryAction?> scan(
    WidgetTester tester,
    Map<String, dynamic> json, {
    UserCoupon? held,
    String? tap,
  }) async {
    QrEntryAction? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showQrEntrySheet(
              context,
              entry: QrEntry.fromJson(json),
              restaurantName: '라라더',
              coupon: held,
            ),
            child: const Text('QR 찍기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('QR 찍기'));
    await tester.pumpAndSettle();
    if (tap != null) {
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
    }
    return result;
  }

  testWidgets('F2 첫 방문: 쿠폰이 도착했어요 → 지금 쓰기', (tester) async {
    final action = await scan(
      tester,
      entryJson('coupon_arrived', coupon: 'C1'),
      held: coupon(),
      tap: '지금 쓰기',
    );
    expect(action, QrEntryAction.useCoupon);
  });

  testWidgets('F2 첫 방문 화면 문구', (tester) async {
    await scan(tester, entryJson('coupon_arrived', coupon: 'C1'), held: coupon());
    expect(find.text('쿠폰이 도착했어요'), findsOneWidget);
    expect(find.text('음료 1잔 무료'), findsOneWidget);
    expect(find.textContaining('라라더에서만'), findsOneWidget);
    expect(find.text('나중에 쓸게요'), findsOneWidget);
    // 첫 방문에는 "쿠폰 쓰고 스탬프도 찍기"(재방문용)가 나오지 않는다
    expect(find.text('쿠폰 쓰고 스탬프도 찍기'), findsNothing);
  });

  testWidgets('두 번째 QR(쿠폰 안 씀): 스탬프 시트 + 쿠폰 함께 쓰기 유도', (tester) async {
    final action = await scan(
      tester,
      entryJson('stamp_progress',
          coupon: 'C1', stamp: {'current': 0, 'remaining': 3}),
      held: coupon(),
      tap: '쿠폰 쓰고 스탬프도 찍기',
    );
    expect(action, QrEntryAction.useCouponWithStamp);
  });

  testWidgets('두 번째 QR 화면: "쿠폰이 도착했어요"가 다시 나오지 않는다', (tester) async {
    await scan(
      tester,
      entryJson('stamp_progress', coupon: 'C1'),
      held: coupon(),
    );
    expect(find.text('쿠폰이 도착했어요'), findsNothing);
    expect(find.text('갖고 계신 쿠폰'), findsOneWidget);
    expect(find.text('스탬프만 찍기'), findsOneWidget);
    expect(find.text('매장 보기'), findsOneWidget);
  });

  testWidgets('F3 쿠폰은 이미 씀: 스탬프만 — 2/3 · 오늘 찍으면 에이드 1잔', (tester) async {
    final action = await scan(
      tester,
      entryJson('stamp_progress', stamp: {
        'current': 2,
        'remaining': 1,
        'last_visit_at': '2026-09-30T12:00:00+09:00',
      }),
      tap: '스탬프 찍기',
    );
    expect(action, QrEntryAction.addStamp);
  });

  testWidgets('F3 화면 문구', (tester) async {
    await scan(
      tester,
      entryJson('stamp_progress', stamp: {
        'current': 2,
        'remaining': 1,
        'last_visit_at': '2026-09-30T12:00:00+09:00',
      }),
    );
    expect(find.textContaining('오늘 찍으면'), findsOneWidget);
    expect(find.text('스탬프 2/3 · 지난 방문 9월 30일'), findsOneWidget);
    expect(find.text('갖고 계신 쿠폰'), findsNothing);
    expect(find.text('쿠폰 쓰고 스탬프도 찍기'), findsNothing);
  });

  testWidgets('오늘 이미 적립: 오늘 적립 완료, 쿠폰 있으면 쿠폰만 쓰도록', (tester) async {
    final action = await scan(
      tester,
      entryJson('stamp_done_today', coupon: 'C1', stamp: {
        'current': 1,
        'stamped_today': true,
      }),
      held: coupon(),
      tap: '쿠폰 쓰기',
    );
    expect(action, QrEntryAction.useCoupon);
  });

  testWidgets('스탬프도 쿠폰도 없는 매장: 막다른 화면 없이 매장 보기', (tester) async {
    final action = await scan(
      tester,
      entryJson('none', stamp: {'enabled': false}),
      tap: '매장 보기',
    );
    expect(action, QrEntryAction.viewStore);
  });

  testWidgets('"나중에"·"매장 보기"로 언제든 닫을 수 있다', (tester) async {
    final later = await scan(
      tester,
      entryJson('coupon_arrived', coupon: 'C1'),
      held: coupon(),
      tap: '나중에 쓸게요',
    );
    expect(later, QrEntryAction.later);
  });

  // ── 진입 대기열 ───────────────────────────────────────────────────
  test('QR 진입 분기는 오래되면 버린다 (상세가 한참 뒤 열려도 낡은 시트 방지)', () {
    final now = DateTime(2026, 10, 11, 12);
    final entry = QrEntry.fromJson(entryJson('stamp_progress'));
    expect(
        PendingQrEntry(entry: entry, at: now.subtract(const Duration(seconds: 10)))
            .isFresh(now),
        isTrue);
    expect(
        PendingQrEntry(entry: entry, at: now.subtract(const Duration(minutes: 2)))
            .isFresh(now),
        isFalse);
  });

  test('서버가 모르는 분기를 보내도 앱은 매장 화면(none)으로 처리한다', () {
    expect(QrEntry.fromJson(entryJson('brand_new_branch')).branch,
        QrEntryBranch.none);
  });
}
