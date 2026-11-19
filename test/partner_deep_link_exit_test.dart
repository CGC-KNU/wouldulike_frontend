import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:new1/main2.dart';
import 'package:new1/partner/partner_access_controller.dart';
import 'package:new1/partner/partner_shell.dart';
import 'package:new1/services/app_session.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/widgets/liquid_glass_bottom_bar.dart';

import 'castor/harness.dart';

void main() {
  final previous = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = CastorHttpOverrides());
  tearDownAll(() => HttpOverrides.global = previous);
  late PartnerAccessController access;
  final links = DeepLinkService.instance;
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    FakeBackend.reset();
    AppSession.changing = false;
    links.consumePendingTarget();
    links.pendingRestaurantId.value = null;
    links.pendingWalletTab.value = null;
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'account-a',
      'user_id': 1,
      'access_expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'welcome_coupon_dialog_dismissed': true,
    });
    access = PartnerAccessController(
        loadUser: () async => 1,
        loadEnabled: () async => true,
        loadMe: () async => {
              'is_partner': true,
              'stores': [
                {'restaurant_id': 1, 'name': '검증 식당'}
              ]
            });
    FakeBackend.routes['/api/app/owner/home'] = (_) => {
          'store': {'name': '검증 식당'},
          'month': '2026-11'
        };
    FakeBackend.routes['/api/app/owner/restaurant'] =
        (_) => {'name': '검증 식당', 'description': '원래 소개', 's3_image_urls': []};
    FakeBackend.routes['/api/app/owner/categories'] = (_) => {'categories': []};
  });
  tearDown(() {
    links.consumePendingTarget();
    links.pendingRestaurantId.value = null;
    links.pendingWalletTab.value = null;
  });

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  }

  Future<void> edit(WidgetTester tester) async {
    await tester
        .pumpWidget(MaterialApp(home: MainAppScreen(partnerAccess: access)));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsOneWidget);
    await tester.tap(find.text('매장'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, '매장 소개');
    await tester.ensureVisible(field);
    await tester.enterText(field, '저장하지 않은 소개');
  }

  testWidgets('딥링크를 취소하면 편집과 파트너 화면을 보존하고 목적지를 버린다', (tester) async {
    await edit(tester);
    links.tryHandle(Uri.parse('wouldulike://restaurant/56'));
    await tester.pumpAndSettle();
    expect(find.text('편집을 끝낼까요?'), findsOneWidget);
    expect(links.pendingRestaurantId.value, isNull);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsOneWidget);
    expect(find.text('저장하지 않은 소개'), findsOneWidget);
    expect(links.consumePendingTarget(), isNull);
    expect(links.pendingRestaurantId.value, isNull);
    await close(tester);
  });

  testWidgets('폐기를 승인한 뒤에만 파트너를 닫고 링크 탭으로 이동한다', (tester) async {
    await edit(tester);
    links.tryHandle(Uri.parse('wouldulike://home'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsOneWidget);
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsNothing);
    expect(
        tester
            .widget<LiquidGlassBottomBar>(find.byType(LiquidGlassBottomBar))
            .selectedIndex,
        0);
    expect(links.consumePendingTarget(), isNull);
    await close(tester);
  });

  testWidgets('확인창 중 여러 링크는 확인 한 번으로 마지막 목적지에 이동한다', (tester) async {
    await edit(tester);
    links.tryHandle(Uri.parse('wouldulike://home'));
    await tester.pumpAndSettle();
    links.tryHandle(Uri.parse('wouldulike://wallet/coupons'));
    await tester.pump();
    // A tab-only request supersedes the older full destination as well.
    links.openTab(3);
    await tester.pumpAndSettle();
    expect(find.text('편집을 끝낼까요?'), findsOneWidget);
    expect(links.pendingWalletTab.value, isNull);
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsNothing);
    expect(
        tester
            .widget<LiquidGlassBottomBar>(find.byType(LiquidGlassBottomBar))
            .selectedIndex,
        3);
    expect(links.consumePendingTarget(), isNull);
    await close(tester);
  });

  testWidgets('일반 탭 열기 요청도 편집 폐기 확인을 거친다', (tester) async {
    await edit(tester);
    links.openTab(2);
    await tester.pumpAndSettle();
    expect(find.text('편집을 끝낼까요?'), findsOneWidget);
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsOneWidget);
    expect(find.text('저장하지 않은 소개'), findsOneWidget);
    expect(links.consumePendingTabIndex(), isNull);
    await close(tester);
  });

  testWidgets('확인창이 열린 중 권한이 회수되면 즉시 닫고 오래된 링크를 남기지 않는다', (tester) async {
    await edit(tester);
    links.tryHandle(Uri.parse('wouldulike://wallet/coupons'));
    await tester.pumpAndSettle();
    access.clear(PartnerAccess.signedOut);
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsNothing);
    expect(find.text('편집을 끝낼까요?'), findsNothing);
    expect(links.consumePendingTarget(), isNull);
    expect(links.pendingWalletTab.value, isNull);
    await close(tester);
  });

  testWidgets('링크를 취소한 뒤 시스템 뒤로가기로 나가도 일반 홈 초기화를 마친다', (tester) async {
    await edit(tester);
    links.tryHandle(Uri.parse('wouldulike://home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계속 편집'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();
    expect(find.byType(PartnerShell), findsNothing);
    expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
    await close(tester);
  });
}
