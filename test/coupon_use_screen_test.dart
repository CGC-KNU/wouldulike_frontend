import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/redeem_pin_dialog.dart';
import 'package:new1/services/coupon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openScreen(WidgetTester tester, {bool withStamp = false}) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCouponRedeemPinDialog(
                context: context,
                coupon: UserCoupon(
                  code: 'ABCD1234',
                  status: CouponStatus.issued,
                  expiresAt: DateTime.now().add(const Duration(days: 2)),
                ),
                restaurantId: 7,
                restaurantName: '라라더',
                fromScreen: 'test',
                initialAddStamp: withStamp,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('전체 화면으로 열리고 직원 안내·매장 PIN·도움말을 보여준다', (tester) async {
    await openScreen(tester);

    expect(find.text('쿠폰 사용'), findsOneWidget);
    expect(find.text('라라더'), findsOneWidget);
    expect(find.text('직원에게 이 화면을 보여주세요'), findsOneWidget);
    expect(find.text('매장 PIN'), findsOneWidget);
    expect(find.text('PIN은 계산대 안내문에 있어요'), findsOneWidget);
    expect(find.textContaining('관리자'), findsNothing);
  });

  testWidgets('스탬프 동시 적립은 기본 꺼짐이고, 켜면 인원 버튼이 나온다', (tester) async {
    await openScreen(tester);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse);
    expect(find.text('몇 명이 함께 결제했나요?'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('몇 명이 함께 결제했나요?'), findsOneWidget);
    expect(find.text('스탬프 1개가 함께 적립돼요.'), findsOneWidget);
    await tester.tap(find.text('3명'));
    await tester.pumpAndSettle();
    expect(find.text('스탬프 3개가 함께 적립돼요.'), findsOneWidget);
  });

  testWidgets('숫자 패드를 누르면 PIN 칸이 채워지고 지우면 줄어든다', (tester) async {
    await openScreen(tester);

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(find.text('•'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('QR 재방문 "쿠폰 쓰고 스탬프도 찍기"로 열면 스탬프 적립이 미리 켜져 있다', (tester) async {
    await openScreen(tester, withStamp: true);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('몇 명이 함께 결제했나요?'), findsOneWidget);
  });
}
