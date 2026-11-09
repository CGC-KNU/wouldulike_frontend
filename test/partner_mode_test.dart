import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/widgets/liquid_glass_bottom_bar.dart';
import 'package:new1/partner/widgets/partner_mode_handle.dart';
import 'package:new1/partner/partner_report_launcher.dart';
import 'package:new1/partner/partner_api_client.dart';

Widget bar({VoidCallback? owner, ValueChanged<int>? tap}) => MaterialApp(
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
      onOwnerMode: owner,
      iconBuilder: (_, __) => const Icon(Icons.circle),
      selectedColor: Colors.indigo,
      unselectedColor: Colors.grey,
      selectedLabelStyle: const TextStyle(),
      unselectedLabelStyle: const TextStyle(),
    )));
void main() {
  testWidgets('비점주에게 위젯·제스처·접근성 트리거를 생성하지 않는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bar());
    expect(find.byType(PartnerModeSwipe), findsNothing);
    expect(find.bySemanticsLabel('사장님 모드로 전환'), findsNothing);
    semantics.dispose();
  });
  testWidgets('마이페이지 단일 탭과 유효 세로 스와이프를 구분한다', (tester) async {
    var entries = 0, tab = -1;
    await tester.pumpWidget(bar(owner: () => entries++, tap: (v) => tab = v));
    await tester.tap(find.text('마이페이지').last);
    await tester.pumpAndSettle();
    expect(tab, 3);
    expect(entries, 0);
    tab = -1;
    await tester.drag(find.text('마이페이지').last, const Offset(0, -65));
    await tester.pumpAndSettle();
    expect(entries, 1);
    expect(tab, -1);
  });
  testWidgets('짧은 세로·다른 탭 세로·가로 드래그는 점주로 전환하지 않는다', (tester) async {
    var entries = 0;
    await tester.pumpWidget(bar(owner: () => entries++));
    await tester.drag(find.text('마이페이지').last, const Offset(0, -30));
    await tester.pumpAndSettle();
    await tester.drag(find.text('홈').last, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.drag(find.text('마이페이지').last, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(entries, 0);
  });
  testWidgets('권한 해제 시 전환 버튼과 hit target을 제거한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bar(owner: () {}));
    expect(find.bySemanticsLabel('사장님 모드로 전환'), findsOneWidget);
    await tester.pumpWidget(bar());
    expect(find.byType(PartnerModeSwipe), findsNothing);
    expect(find.bySemanticsLabel('사장님 모드로 전환'), findsNothing);
    semantics.dispose();
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
