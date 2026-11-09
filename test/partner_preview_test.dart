import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:new1/partner/partner_access_controller.dart';
import 'package:new1/partner/partner_pages.dart';
import 'package:new1/partner/partner_design.dart';
import 'package:new1/widgets/liquid_glass_bottom_bar.dart';
import 'castor/harness.dart';

void main() {
  setUpAll(loadCastorFonts);
  testWidgets('파트너 6개 화면은 웹 스타일과 작은 화면·큰 글자 레이아웃을 유지한다', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final access = PartnerAccessController()..state = PartnerAccess.owner;
    addTearDown(access.dispose);
    final home = <String, dynamic>{
      'store': {
        'name': '우주식당 경북대학교 정문점',
        'tier': 'BOOST',
        'pin': '1234',
        'campus': '경북대학교',
        'stamp_enabled': true,
        'contract_started_on': '2026-10-15',
        'contract_ends_on': '2027-02-28',
        'category': '한식',
        'main_menu': '정성 가득한 한 끼',
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
          'title': '우리 동네 따뜻한 한 끼, 우주식당을 소개합니다',
          'date': '2026-11-06',
          'state': 'published'
        },
        {
          'kind': 'campaign',
          'title': '대학가 점심 한정 쿠폰 캠페인',
          'date': '2026-11-10',
          'state': 'scheduled'
        },
      ],
      'billing': {
        'monthly_fee': 30000,
        'pay_cycle': 'MONTHLY',
        'invoice': {'total': 33000, 'paid_at': null}
      },
      'report_status': {'state': 'collecting', 'days_until_first': 5},
      'manager': {'name': '김우주', 'title': '파트너 매니저'},
    };
    Future<Map<String, dynamic>> request(String route,
            {String method = 'GET', Map<String, dynamic>? body}) async =>
        switch (route) {
          'restaurant' => {
              'name': '우주식당',
              'category': '한식',
              'description': '든든한 한 끼가 있는 곳',
              'has_pin': true,
              'pin': '1234',
              's3_image_urls': []
            },
          'categories' => {
              'categories': [
                {'label': '한식', 'code': 'KOREAN'}
              ]
            },
          'benefits' => {
              'choices': [
                {'id': 1, 'label': '든든한 한 끼 1,000원 할인', 'active': true}
              ]
            },
          'benefit-requests' => {
              'pending': 1,
              'requests': [
                {
                  'status': 'PENDING',
                  'created_at': '2026-11-08',
                  'action_label': '문구 수정',
                  'benefit_label': '기본 쿠폰',
                  'before': '식사 500원 할인',
                  'after': '식사 1,000원 할인'
                }
              ]
            },
          'stamp-rule' => {
              'exists': true,
              'active': true,
              'config_json': {
                'stamp_enabled': true,
                'cycle_target': 10,
                'thresholds': [
                  {'stamps': 5, 'reward_text': '음료 한 잔'},
                  {'stamps': 10, 'reward_text': '식사 1,000원 할인'}
                ]
              }
            },
          'reports' => {
              'reports': [
                {
                  'id': '1',
                  'title': '10월 우리 매장 월간 리포트',
                  'sent_at': '2026-11-01',
                  'summary': '쿠폰·스탬프와 콘텐츠 활동을 정리했어요.'
                }
              ]
            },
          'plan' => {
              ...home,
              'plans': [
                {
                  'id': 'FREE',
                  'displayName': 'Free',
                  'price': '0원',
                  'priceSub': '/ 월',
                  'features': [
                    {'text': '쿠폰·스탬프 기본 운영', 'bold': false}
                  ]
                },
                {
                  'id': 'BOOST',
                  'displayName': 'Boost',
                  'price': '30,000원',
                  'priceSub': '/ 월',
                  'features': [
                    {'text': '테마 기획전 보장 편입', 'bold': true},
                    {'text': '홍보물 제작·비치 (포스터·QR 스티커)', 'bold': true}
                  ]
                },
                {
                  'id': 'CONTENT',
                  'displayName': 'Premium',
                  'price': '80,000원~',
                  'priceSub': '/ 월',
                  'features': [
                    {'text': '인스타 단독 콘텐츠 월 1건', 'bold': true}
                  ]
                },
              ]
            },
          _ => home,
        };
    for (final size in [
      const Size(390, 844),
      const Size(320, 740),
      const Size(1024, 900)
    ]) {
      tester.view.physicalSize = size;
      final scale = size.width == 320 ? 2.0 : 1.0;
      for (var tab = 0; tab < 6; tab++) {
        await tester.pumpWidget(RepaintBoundary(
            key: castorBoundaryKey,
            child: MaterialApp(
              key: ValueKey('preview:$size:$tab'),
              debugShowCheckedModeBanner: false,
              theme: PartnerDesign.theme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                appBar: AppBar(title: const Text('우주라이크 파트너')),
                body: PartnerPage(
                    tab: tab,
                    scope: 'preview:$size:$tab',
                    request: request,
                    access: access),
                bottomNavigationBar:
                    PartnerNavigation(selected: tab, onSelected: (_) {}),
              ),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'tab $tab / $size / $scale');
        if (size.width == 390) {
          await captureScreen(tester, 'partner.design.$tab');
        }
        final scrollable = tester.state<ScrollableState>(find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
        // Scroll through every section, including fields and plan cards below the fold.
        while (
            scrollable.position.pixels < scrollable.position.maxScrollExtent) {
          scrollable.position.jumpTo((scrollable.position.pixels + 400)
              .clamp(0, scrollable.position.maxScrollExtent));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'scrolled tab $tab / $size / $scale');
        }
        if (size.width == 390 && (tab == 2 || tab == 5)) {
          await captureScreen(tester, 'partner.design.$tab.bottom');
        }
      }
    }
  });
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
