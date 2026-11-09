import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/home.dart';
import 'package:new1/main2.dart';
import 'package:new1/partner/partner_access_controller.dart';
import 'package:new1/partner/partner_shell.dart';
import 'package:new1/partner/widgets/partner_mode_toggle.dart';
import 'package:new1/services/app_session.dart';
import 'package:new1/services/deep_link_service.dart';

import 'castor/harness.dart';

const ownerMe = {
  'is_partner': true,
  'stores': [
    {'restaurant_id': 1, 'name': '매장 A'},
    {'restaurant_id': 2, 'name': '매장 B'},
  ],
};

class _EntryTransitionObserver extends NavigatorObserver {
  _EntryTransitionObserver(this.mainRoute);
  final MaterialPageRoute<void> mainRoute;
  AnimationStatus? statusAtPartnerPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == mainRoute) {
      statusAtPartnerPush = mainRoute.animation!.status;
    }
  }
}

void main() {
  final previousOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = CastorHttpOverrides());
  tearDownAll(() => HttpOverrides.global = previousOverrides);
  setUp(() {
    AppSession.changing = false;
    DeepLinkService.instance.consumePendingTarget();
    SharedPreferences.setMockInitialValues({
      'welcome_coupon_dialog_dismissed': true,
    });
    FakeBackend.reset();
  });

  Future<void> open(WidgetTester tester, PartnerAccessController access) async {
    await tester
        .pumpWidget(MaterialApp(home: MainAppScreen(partnerAccess: access)));
  }

  testWidgets('점주는 권한 확인 후 자동 진입하며 홈 토글로 왕복한다', (tester) async {
    final me = Completer<Map<String, dynamic>>();
    var enabled = true;
    final access = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () => me.future,
        loadEnabled: () async => enabled);
    await open(tester, access);
    await tester.pump();
    expect(find.byType(HomeContent), findsNothing);
    expect(find.byType(PartnerShell), findsNothing);

    me.complete(ownerMe);
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsOneWidget);
    expect(find.byType(HomeContent), findsNothing);
    expect(find.byTooltip('일반 모드로 전환'), findsOneWidget);

    await tester.tap(find.byTooltip('일반 모드로 전환'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeContent), findsOneWidget);
    expect(find.byType(PartnerShell), findsNothing);
    expect(find.byTooltip('사장님 모드로 전환'), findsOneWidget);

    // A periodic permission refresh must preserve the user's general-mode choice.
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsNothing);
    await tester.tap(find.byTooltip('사장님 모드로 전환'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsOneWidget);

    await tester.tap(find.byTooltip('일반 모드로 전환'));
    await tester.pumpAndSettle();
    enabled = false;
    await tester.tap(find.byTooltip('사장님 모드로 전환'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsNothing);
    expect(find.byType(PartnerModeToggle), findsNothing);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });

  testWidgets('비로그인·비점주·서버 비활성·권한 오류는 일반 홈만 연다', (tester) async {
    for (final scenario in ['signedOut', 'nonOwner', 'disabled', 'error']) {
      final access = PartnerAccessController(
          loadUser: () async => scenario == 'signedOut' ? null : 1,
          loadMe: () async {
            if (scenario == 'error') throw StateError('offline');
            return scenario == 'nonOwner'
                ? {'is_partner': false, 'stores': []}
                : ownerMe;
          },
          loadEnabled: () async => scenario != 'disabled');
      await open(tester, access);
      await tester.pumpAndSettle();
      expect(find.byType(HomeContent), findsOneWidget, reason: scenario);
      expect(find.byType(PartnerShell), findsNothing, reason: scenario);
      expect(find.byType(PartnerModeToggle), findsNothing, reason: scenario);
      await tester.pumpWidget(const SizedBox());
      access.dispose();
    }
  });

  testWidgets('앱 재진입 시에는 점주 모드를 기본으로 연다', (tester) async {
    for (var launch = 0; launch < 2; launch++) {
      final access = PartnerAccessController(
          loadUser: () async => 1,
          loadMe: () async => ownerMe,
          loadEnabled: () async => true);
      await open(tester, access);
      await tester.pumpAndSettle();
      expect(find.byType(PartnerShell), findsOneWidget);
      await tester.tap(find.byTooltip('일반 모드로 전환'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeContent), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      access.dispose();
    }
  });

  testWidgets('스플래시 교체 전환이 끝난 뒤에 점주 화면을 연다', (tester) async {
    final access = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () async => ownerMe,
        loadEnabled: () async => true);
    final mainRoute = MaterialPageRoute<void>(
        builder: (_) => MainAppScreen(partnerAccess: access));
    final observer = _EntryTransitionObserver(mainRoute);
    await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacement(mainRoute),
                    child: const Text('스플래시 완료'))))));
    await tester.tap(find.text('스플래시 완료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(mainRoute.animation!.status, AnimationStatus.forward);
    expect(find.byType(PartnerShell), findsNothing);
    await tester.pumpAndSettle();
    expect(observer.statusAtPartnerPush, AnimationStatus.completed);
    expect(find.byType(PartnerShell), findsOneWidget);
    expect(find.byTooltip('일반 모드로 전환'), findsOneWidget);
    await tester.tap(find.byTooltip('일반 모드로 전환'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeContent), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });

  testWidgets('권한 확인 중 받은 딥링크가 자동 진입보다 우선한다', (tester) async {
    final me = Completer<Map<String, dynamic>>();
    final access = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () => me.future,
        loadEnabled: () async => true);
    await open(tester, access);
    DeepLinkService.instance.tryHandle(Uri.parse('wouldulike://home'));
    await tester.pumpAndSettle();
    me.complete(ownerMe);
    await tester.pumpAndSettle();
    expect(find.byType(HomeContent), findsOneWidget);
    expect(find.byType(PartnerShell), findsNothing);
    expect(find.byType(PartnerModeToggle), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });
}
