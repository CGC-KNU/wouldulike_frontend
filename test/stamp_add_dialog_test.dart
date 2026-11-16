import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/pin_entry_widgets.dart';
import 'package:new1/coupon/stamp_add_dialog.dart';
import 'package:new1/services/app_config_service.dart';

void main() {
  StampAddRequest? result;
  var closed = false;

  Future<void> open(WidgetTester tester) async {
    result = null;
    closed = false;
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showStampAddDialog(context, restaurantName: '라라더');
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('쿠폰 사용 화면과 같은 전체 화면: 매장명·직원 안내·매장 PIN·숫자 패드', (tester) async {
    await open(tester);

    expect(find.text('스탬프 적립'), findsOneWidget); // 상단 제목
    expect(find.text('라라더'), findsOneWidget);
    expect(find.text('직원에게 이 화면을 보여주세요'), findsOneWidget);
    expect(find.text('매장 PIN'), findsOneWidget);
    expect(find.byType(PinBoxes), findsOneWidget);
    expect(find.byType(PinKeypad), findsOneWidget);
    // 예전 작은 팝업의 요소는 더 이상 없다
    expect(find.text('적립하기'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('PIN을 모두 누르면 PIN과 개수를 돌려주고 닫힌다', (tester) async {
    await open(tester);

    final n = AppConfigService.pinLength;
    for (var i = 0; i < n; i++) {
      await tester.tap(find.text('${(i % 9) + 1}'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNotNull);
    expect(result!.pin.length, n);
    expect(result!.count, 1);
  });

  testWidgets('인원 버튼으로 고른 개수가 함께 돌아온다', (tester) async {
    await open(tester);
    if (AppConfigService.stampMaxPerScan < 2) return;

    expect(find.text('몇 명이 함께 결제했나요?'), findsOneWidget);
    await tester.tap(find.text('2명'));
    await tester.pump();
    expect(find.text('스탬프 2개 적립'), findsOneWidget);

    final n = AppConfigService.pinLength;
    for (var i = 0; i < n; i++) {
      await tester.tap(find.text('${(i % 9) + 1}'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(result!.count, 2);
  });

  testWidgets('X로 닫으면 null', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
