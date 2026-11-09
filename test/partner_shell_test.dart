import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/partner/partner_shell.dart';
import 'package:new1/partner/partner_access_controller.dart';
import 'package:new1/services/app_session.dart';

void main() {
  late PartnerAccessController access;
  setUp(() {
    AppSession.changing = false;
    SharedPreferences.setMockInitialValues({});
    access = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () async => {
              'is_partner': true,
              'stores': [
                {'restaurant_id': 1, 'name': '매장 A'},
                {'restaurant_id': 2, 'name': '매장 B'}
              ]
            },
        loadEnabled: () async => true)
      ..state = PartnerAccess.owner
      ..userId = 1
      ..stores = const [PartnerStore(1, '매장 A'), PartnerStore(2, '매장 B')];
  });
  Widget app({double scale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => PartnerShell(access: access))),
                  child: const Text('일반 화면')))));
  testWidgets('뒤로가기는 매장 선택을 닫은 뒤 사장님 모드를 닫는다', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('일반 화면'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('매장 A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('매장 변경'));
    await tester.pumpAndSettle();
    expect(find.text('내 매장 선택'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('내 매장 선택'), findsNothing);
    expect(find.text('매장 A'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('일반 화면'), findsOneWidget);
    access.dispose();
  });
  testWidgets('로그아웃 신호는 점주 라우트를 강제로 정리한다', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('일반 화면'));
    await tester.pumpAndSettle();
    expect(find.text('내 매장 선택'), findsOneWidget);
    access.clear(PartnerAccess.signedOut);
    await tester.pumpAndSettle();
    expect(find.text('일반 화면'), findsOneWidget);
    expect(find.byType(PartnerShell), findsNothing);
    access.dispose();
  });
  testWidgets('작은 화면·글자 2배에서도 매장 선택과 파트너 헤더가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(scale: 2));
    await tester.tap(find.text('일반 화면'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('매장 A'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('매장 변경'));
    await tester.pumpAndSettle();
    expect(find.text('내 매장 선택'), findsOneWidget);
    expect(tester.takeException(), isNull);
    access.dispose();
  });
}
