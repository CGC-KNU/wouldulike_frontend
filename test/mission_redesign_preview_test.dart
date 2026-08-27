import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/mission/invite_friend.dart';
import 'package:new1/mission/welcome_missions.dart';
import 'package:new1/services/mission_service.dart';

WelcomeMissions _welcome({bool cleared = false}) => WelcomeMissions.fromJson({
      'ends_at': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      'missions': [
        {
          'code': 'WELCOME_COUPON_USE',
          'title': '우주라이크 쿠폰 사용하기',
          'reward_text': '보유한 쿠폰은 모두 인정돼요',
          'status': 'CLAIMED',
          'progress': 1,
          'target': 1,
        },
        {
          'code': 'WELCOME_STAMP_2',
          'title': '스탬프 2회 적립하기',
          'reward_text': '어느 매장이든 상관없어요',
          'status': cleared ? 'CLAIMED' : 'OPEN',
          'progress': cleared ? 2 : 1,
          'target': 2,
        },
      ],
      'reward': {
        'code': 'WELCOME_ALL',
        'title': '환영 미션 완주 리워드',
        'reward_text': '제휴 매장 쿠폰 1장',
        'status': cleared ? 'READY' : 'LOCKED',
        'progress': 0,
        'target': 1,
      },
    });

void main() {
  setUpAll(() async {
    final pretendard = File('assets/fonts/Pretendard-Regular.ttf');
    await (FontLoader('Pretendard')
          ..addFont(Future.value(
            pretendard.readAsBytesSync().buffer.asByteData(),
          )))
        .load();

    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        '/Users/tlsalsrn/development/flutter';
    final materialIcons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(
            materialIcons.readAsBytesSync().buffer.asByteData(),
          )))
        .load();
  });

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('welcome redesign preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F7F8),
        appBar: AppBar(
          title: const Text('환영 미션'),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
          children: [
            WelcomeMissionSection(
              welcome: _welcome(),
              serverOffset: Duration.zero,
              onClaim: () {},
              countdownOverride: '47:59:59',
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/mission-redesign-welcome.png'),
    );
  });

  testWidgets('invite redesign preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const InviteFriendScreen(initialCode: 'SPACE24'),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/mission-redesign-invite.png'),
    );
  });

  testWidgets('home banner redesign preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F4F6),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                WelcomeMissionBanner(
                  welcome: _welcome(),
                  serverOffset: Duration.zero,
                  onTap: () {},
                ),
                InviteFriendBanner(onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/mission-redesign-home-banners.png'),
    );
  });
}
