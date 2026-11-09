import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/widgets/liquid_glass_bottom_bar.dart';
import 'package:new1/partner/widgets/partner_mode_toggle.dart';
import 'package:new1/partner/partner_report_launcher.dart';
import 'package:new1/partner/partner_api_client.dart';

Widget bar({ValueChanged<int>? tap}) => MaterialApp(
        home: Scaffold(
            bottomNavigationBar: LiquidGlassBottomBar(
      tabs: const [
        LiquidGlassTab(label: '홈', assetPath: ''),
        LiquidGlassTab(label: '식당', assetPath: ''),
        LiquidGlassTab(label: '지갑', assetPath: ''),
        LiquidGlassTab(label: '마이페이지', assetPath: '')
      ],
      selectedIndex: 0,
      onTap: tap ?? (_) {},
      iconBuilder: (_, __) => const Icon(Icons.circle),
      selectedColor: Colors.indigo,
      unselectedColor: Colors.grey,
      selectedLabelStyle: const TextStyle(),
      unselectedLabelStyle: const TextStyle(),
    )));
void main() {
  testWidgets('하단 바에는 사장님 전환 트리거가 없다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bar());
    expect(find.byType(PartnerModeToggle), findsNothing);
    expect(find.bySemanticsLabel('사장님 모드로 전환'), findsNothing);
    semantics.dispose();
  });
  testWidgets('마이페이지는 탭으로 열리고 위로 밀어도 모드를 전환하지 않는다', (tester) async {
    var tab = -1;
    await tester.pumpWidget(bar(tap: (v) => tab = v));
    await tester.tap(find.text('마이페이지').last);
    await tester.pumpAndSettle();
    expect(tab, 3);
    tab = -1;
    await tester.drag(find.text('마이페이지').last, const Offset(0, -65));
    await tester.pumpAndSettle();
    expect(tab, 3);
    expect(find.byType(PartnerModeToggle), findsNothing);
  });
  testWidgets('하단 바의 가로 드래그는 기존 탭을 선택한다', (tester) async {
    var tab = -1;
    await tester.pumpWidget(bar(tap: (v) => tab = v));
    await tester.drag(find.text('마이페이지').last, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(tab, inInclusiveRange(0, 3));
  });
  testWidgets('홈 토글은 양쪽 전환을 알리고 비활성일 때 동작하지 않는다', (tester) async {
    bool? selected;
    Widget toggle(bool partner, {bool enabled = true}) => MaterialApp(
        home: Scaffold(
            body: PartnerModeToggle(
                partnerMode: partner,
                onChanged: enabled ? (value) => selected = value : null)));
    await tester.pumpWidget(toggle(false));
    await tester.tap(find.byTooltip('사장님 모드로 전환'));
    expect(selected, true);
    await tester.pumpWidget(toggle(true));
    await tester.tap(find.byTooltip('일반 모드로 전환'));
    expect(selected, false);
    selected = null;
    await tester.pumpWidget(toggle(true, enabled: false));
    await tester.tap(find.byType(Switch));
    expect(selected, isNull);
  });
  test('JWT 목적지와 리포트 URL은 허용한 HTTPS 출처·경로로 제한한다', () {
    expect(
        PartnerApiClient.canonicalOrigin(
                'https://wouldulike-dashboard.vercel.app/')
            .host,
        'app.wouldulike.kr');
    for (final origin in [
      'http://app.wouldulike.kr',
      'https://evil.test',
      'https://app.wouldulike.kr.evil.test'
    ]) {
      expect(() => PartnerApiClient.canonicalOrigin(origin),
          throwsFormatException);
    }
    final token = 'a' * 40;
    expect(
        PartnerReportLauncher.validate('https://app.wouldulike.kr/r/$token')
            .path,
        '/r/$token');
    for (final url in [
      'https://evil.test/r/$token',
      'https://app.wouldulike.kr/r/$token?token=jwt',
      'https://app.wouldulike.kr/dashboard',
      'http://app.wouldulike.kr/r/$token'
    ]) {
      expect(() => PartnerReportLauncher.validate(url), throwsFormatException);
    }
  });
}
