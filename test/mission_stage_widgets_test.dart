import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/mission/invite_friend.dart';
import 'package:new1/mission/promo_block.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';
import 'package:new1/mission/welcome_missions.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/mission_service.dart';

/// 작은 화면(iPhone SE급)에서도 미션 UI가 오버플로 없이 들어가야 한다.
Future<void> _pumpSmall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    ),
  ));
  await tester.pump();
}

WelcomeMissions _welcome(
        {String stampStatus = 'OPEN', int stampProgress = 1}) =>
    WelcomeMissions.fromJson({
      'ends_at': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      'missions': [
        {
          'code': 'WELCOME_COUPON_USE',
          'title': '우주라이크 쿠폰 사용하기',
          'reward_text': '가입 축하 쿠폰·기획전 쿠폰 모두 인정돼요',
          'status': 'CLAIMED',
          'progress': 1,
          'target': 1,
        },
        {
          'code': 'WELCOME_STAMP_2',
          'title': '스탬프 2회 적립하기',
          'reward_text': '어느 매장이든 상관없어요',
          'status': stampStatus,
          'progress': stampProgress,
          'target': 2,
        },
      ],
    });

void main() {
  testWidgets('환영 미션 배너·섹션이 작은 화면에서도 안 깨진다', (tester) async {
    await _pumpSmall(
      tester,
      Column(children: [
        WelcomeMissionBanner(
          welcome: _welcome(),
          serverOffset: Duration.zero,
          onTap: () {},
        ),
        WelcomeMissionSection(
          welcome: _welcome(),
          serverOffset: Duration.zero,
          onClaim: () {},
        ),
      ]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('우주라이크 쿠폰 사용하기'), findsWidgets);
  });

  testWidgets('미완주면 리워드 버튼이 잠겨 있다', (tester) async {
    await _pumpSmall(
      tester,
      WelcomeMissionSection(
        welcome: _welcome(),
        serverOffset: Duration.zero,
        onClaim: () {},
      ),
    );
    expect(find.text('미션을 완료하면 받을 수 있어요'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('완주하면 리워드 받기가 열린다', (tester) async {
    var tapped = false;
    await _pumpSmall(
      tester,
      WelcomeMissionSection(
        welcome: _welcome(stampStatus: 'CLAIMED', stampProgress: 2),
        serverOffset: Duration.zero,
        onClaim: () => tapped = true,
      ),
    );
    await tester.ensureVisible(find.text('쿠폰 받기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('쿠폰 받기'));
    expect(tapped, isTrue);
  });

  testWidgets('프로모 블록 텍스트형이 렌더링되고 링크가 없으면 탭이 죽는다', (tester) async {
    final block = PromoBlock.fromJson({
      'active': true,
      'title': '쿠폰 1종 무료 지급 중',
      'subtitle': '오늘까지만',
      'link_url': 'https://evil.com/x', // 허용 도메인이 아니라 버려진다
    });
    expect(block.link, isNull);
    await _pumpSmall(tester, PromoBlockCard(block: block, onTap: null));
    expect(tester.takeException(), isNull);
    expect(find.text('쿠폰 1종 무료 지급 중'), findsOneWidget);
  });

  testWidgets('쿠폰 발급 팝업이 실제 쿠폰 카드와 지갑 버튼으로 뜬다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCouponIssuedDialog(
                context,
                tag: '환영 미션 완주',
                title: '제휴 매장 쿠폰 1장',
                // 쿠폰을 넘기면 서버 조회를 건너뛴다.
                coupon: const UserCoupon(
                  code: 'WUL-TEST',
                  status: CouponStatus.issued,
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('제휴 매장 쿠폰 1장'), findsOneWidget);
    // 발급 팝업은 항상 쿠폰함으로 갈 수 있어야 한다.
    expect(find.text('내 지갑 바로가기'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('제휴 매장 쿠폰 1장'), findsNothing);
  });

  testWidgets('환영 미션이 끝나면 친구 초대 배너가 자리를 잇는다', (tester) async {
    var tapped = false;
    await _pumpSmall(tester, InviteFriendBanner(onTap: () => tapped = true));
    expect(tester.takeException(), isNull);
    expect(find.text('친구와 함께 시작해요'), findsOneWidget);
    await tester.tap(find.byType(InviteFriendBanner));
    expect(tapped, isTrue);
  });

  testWidgets('친구 초대 화면에 내 코드·초대·코드 입력이 모두 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: InviteFriendScreen()));
    await tester.pump();

    expect(find.text('MY INVITE CODE'), findsOneWidget);
    expect(find.text('친구에게 코드 보내기'), findsOneWidget);
    expect(find.text('코드 입력'), findsOneWidget);
    // 코드를 못 불러온 동안에는 공유 버튼이 잠겨 있어야 한다.
    final share = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('친구에게 코드 보내기'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(share.onPressed, isNull);
  });
}
