import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:new1/mileage/mileage_shop_screen.dart';
import 'package:new1/mileage/my_raffle_entries_screen.dart';
import 'package:new1/mileage/raffle_terms_screen.dart';
import 'package:new1/mileage/raffle_winners_screen.dart';

/// 2열 티켓 카드는 폭이 좁아 오버플로가 나기 쉬워서 실제 화면 크기로 렌더만 확인한다.
/// (네트워크는 실패하고 디버그 샘플로 그려진다)
void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    // 서비스 타임아웃(8초)까지 흘려 보내 로딩 이후 상태까지 그린다.
    await tester.pump(const Duration(seconds: 10));
    // 로딩 후 생성되는 등장 애니메이션 지연 타이머까지 소진한다.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('마일리지 상점이 오버플로 없이 그려진다', (tester) async {
    await pumpScreen(tester, const MileageShopScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('식사권 응모'), findsOneWidget);
    expect(find.text('당첨자 발표'), findsOneWidget);
    expect(find.text('응모 유의사항'), findsOneWidget);
  });

  testWidgets('당첨자 발표가 오버플로 없이 그려진다', (tester) async {
    await pumpScreen(tester, const RaffleWinnersScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('지난 추첨'), findsOneWidget);
  });

  testWidgets('당첨자는 결과 확인하기를 눌러야 공개된다', (tester) async {
    await pumpScreen(tester, const RaffleWinnersScreen());

    // 열기 전에는 닉네임이 보이지 않는다.
    expect(find.textContaining('김**', findRichText: true), findsNothing);
    expect(find.text('결과 확인하기'), findsWidgets);

    await tester.tap(find.text('결과 확인하기').first);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('김**', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('응모 유의사항이 오버플로 없이 그려진다', (tester) async {
    await pumpScreen(tester, const RaffleTermsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('응모 방법'), findsOneWidget);
  });

  testWidgets('내 응모: 당첨 건을 열면 축하 팝업이 뜬다', (tester) async {
    await pumpScreen(tester, const MyRaffleEntriesScreen());

    expect(find.text('결과 확인하기'), findsWidgets);
    await tester.tap(find.text('결과 확인하기').first);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('당첨됐어요!'), findsOneWidget);
    expect(find.text('내 지갑에서 쿠폰 보기'), findsOneWidget);

    // 팝업을 닫아야 폭죽 오버레이가 정리된다.
    await tester.tap(find.text('닫기'));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
