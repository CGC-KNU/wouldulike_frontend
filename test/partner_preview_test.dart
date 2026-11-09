import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:new1/partner/partner_access_controller.dart';
import 'package:new1/partner/partner_pages.dart';
import 'package:new1/widgets/liquid_glass_bottom_bar.dart';
import 'castor/harness.dart';

void main() {
  setUpAll(loadCastorFonts);
  testWidgets('사장님 홈과 전환 손잡이는 작은 화면·큰 글자에서 overflow 없이 렌더링된다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final access = PartnerAccessController()..state = PartnerAccess.owner;
    addTearDown(access.dispose);
    final home = {
      'store': {
        'name': '우주식당',
        'tier': 'BOOST',
        'pin': '1234',
        'stamp_enabled': true,
        'contract_started_on': '2026-10-01',
        'contract_ends_on': '2027-02-28'
      },
      'month': '2026-11',
      'stats': {
        'this': {'coupon_used': 12, 'stamp': 36, 'revisit': 8},
        'prev': {'coupon_used': 10, 'stamp': 30, 'revisit': 7},
        'loyal_total': 15
      },
      'feed': [
        {
          'kind': 'post',
          'title': '우리 동네 따뜻한 한 끼',
          'date': '2026-11-06',
          'state': 'published'
        }
      ],
      'billing': {
        'monthly_fee': 30000,
        'pay_cycle': 'MONTHLY',
        'invoice': null
      },
      'report_status': {'state': 'available', 'available_count': 1},
      'manager': {'name': '담당자'},
    };
    Widget app(Widget child, {double scale = 1}) => RepaintBoundary(
        key: castorBoundaryKey,
        child: MaterialApp(
            theme: ThemeData(
                fontFamily: 'Pretendard',
                colorSchemeSeed: const Color(0xFF312E81)),
            builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: w!),
            home: child));
    await tester.pumpWidget(app(Scaffold(
        appBar: AppBar(title: const Text('우주식당 · 사장님 모드')),
        body: PartnerPage(
            tab: 0,
            scope: '1:1',
            access: access,
            request: (_,
                    {String method = 'GET',
                    Map<String, dynamic>? body}) async =>
                home))));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'partner.home');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(
        Scaffold(
            body: const Center(child: Text('일반 모드')),
            bottomNavigationBar: LiquidGlassBottomBar(
              tabs: const [
                LiquidGlassTab(label: '홈', assetPath: 'assets/images/home.svg'),
                LiquidGlassTab(
                    label: '식당', assetPath: 'assets/images/fork.svg'),
                LiquidGlassTab(
                    label: '내 지갑', assetPath: 'assets/images/coupon.svg'),
                LiquidGlassTab(
                    label: '마이페이지', assetPath: 'assets/images/my.svg')
              ],
              selectedIndex: 0,
              onTap: (_) {},
              onOwnerMode: () {},
              iconBuilder: (p, c) => SvgPicture.asset(p,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(c, BlendMode.srcIn)),
              selectedColor: const Color(0xFF312E81),
              unselectedColor: Colors.grey,
              selectedLabelStyle: const TextStyle(fontSize: 11.5),
              unselectedLabelStyle: const TextStyle(fontSize: 11.5),
            )),
        scale: 1.5));
    await tester.pumpAndSettle();
    await captureScreen(tester, 'partner.handle');
    expect(tester.takeException(), isNull);
  });
}
