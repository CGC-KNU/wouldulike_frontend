import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:new1/mileage/mileage_shop_screen.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/wallet/mileage_tab.dart';
import 'package:new1/wallet/wallet_screen.dart';

/// 네트워크는 실패하고 디버그 샘플로 그려진다.
Future<void> _settle(WidgetTester tester) async {
  // 서비스 타임아웃(8초)과 등장 애니메이션 지연까지 흘려 보낸다.
  await tester.pump(const Duration(seconds: 10));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpMileageTab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  DeepLinkService.instance.pendingWalletTab.value = 2;
  await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
  await _settle(tester);
}

void main() {
  testWidgets('마일리지 탭: 응모 일정 → 상점 → 내 응모 현황 → 내역 순서로 보인다',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpMileageTab(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('마일리지'), findsOneWidget);
    final schedule = tester.getTopLeft(find.text('마일리지 응모 일정')).dy;
    final balance = tester.getTopLeft(find.text('보유 마일리지')).dy;
    final raffles = tester.getTopLeft(find.text('식사권 응모')).dy;
    expect(schedule, lessThan(balance));
    expect(balance, lessThan(raffles));

    await tester.scrollUntilVisible(
      find.text('마일리지 내역'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(MileageShopScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final myEntries = tester.getTopLeft(find.text('내 응모 현황')).dy;
    final history = tester.getTopLeft(find.text('마일리지 내역')).dy;
    expect(myEntries, lessThan(history));
    expect(tester.takeException(), isNull);
  });

  testWidgets('응모 일정은 기본으로 접혀 있고, 펼치면 그 상태가 저장된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpMileageTab(tester);

    expect(find.text('마일리지 응모 일정'), findsOneWidget);
    expect(find.text('추첨일 하루 전 오전 11시부터'), findsNothing);
    await tester.tap(find.text('펼치기'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('추첨일 하루 전 오전 11시부터'), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('wallet_raffle_schedule_collapsed'), isFalse);
  });

  testWidgets('펼쳐 둔 응모 일정은 다시 열어도 펼쳐져 있다', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'wallet_raffle_schedule_collapsed': false});
    await _pumpMileageTab(tester);

    expect(find.text('추첨일 하루 전 오전 11시부터'), findsOneWidget);
  });

  testWidgets('내역은 maxItems 건까지만 보여준다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: MileageHistorySection(maxItems: 2)),
      ),
    ));
    await _settle(tester);

    expect(find.textContaining(RegExp(r'^[+-][\d,]+ M$')), findsNWidgets(2));
  });
}
