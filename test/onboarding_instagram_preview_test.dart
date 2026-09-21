import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/onboarding/onboarding_style.dart';
import 'package:new1/onboarding/widgets/restaurant_pick_list.dart';
import 'package:new1/onboarding/widgets/roulette_wheel.dart';
import 'package:new1/services/affiliate_service.dart';
import 'package:new1/widgets/category_strip.dart';
import 'package:new1/widgets/coupon_ticket_card.dart';

AffiliateRestaurantSummary _r(
  int id,
  String name,
  String category,
  String zone,
) {
  return AffiliateRestaurantSummary(
    id: id,
    name: name,
    description: '',
    address: '',
    category: category,
    zone: zone,
    phoneNumber: '',
    url: '',
    imageUrls: const [],
    stampCurrent: 0,
    stampTarget: 7,
  );
}

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
    if (materialIcons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
              materialIcons.readAsBytesSync().buffer.asByteData(),
            )))
          .load();
    }
  });

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('intro preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const _IntroPreview(
        title: '대학가 맛집,\n우주라이크와 함께 하세요!',
        subtitle: '대학가 인근 제휴 식당의 쿠폰과 스탬프 등\n모든 혜택을 한 곳에 모았어요.',
        button: '시작하기',
        step: 0,
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/onboarding-intro.png'),
    );
  });

  testWidgets('intro coupon preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const _IntroPreview(
        title: '지금 시작하면,\n바로 쓸 쿠폰을 드려요',
        subtitle: '원하는 식당 하나를 고르면\n바로 사용 가능한 쿠폰을 드려요!',
        button: '쿠폰 즉시 발급 받기',
        step: 1,
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/onboarding-intro-coupon.png'),
    );
  });

  testWidgets('restaurant pick preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const _PickPreview(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/onboarding-pick.png'),
    );
  });

  testWidgets('roulette spinning preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const _SpinPreview(revealed: false),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/onboarding-spin.png'),
    );
  });

  testWidgets('roulette win preview', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const _SpinPreview(revealed: true),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/onboarding-win.png'),
    );
  });
}

const TextStyle _introHeadline = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 28,
  fontWeight: FontWeight.w800,
  height: 1.35,
  letterSpacing: -0.6,
  color: OnboardingStyle.ink,
);

class _IntroPreview extends StatelessWidget {
  const _IntroPreview({
    required this.title,
    required this.subtitle,
    required this.button,
    required this.step,
  });

  final String title;
  final String subtitle;
  final String button;
  final int step;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '건너뛰기',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: OnboardingStyle.muted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(title, style: _introHeadline),
                    ),
                    const SizedBox(height: 12),
                    Text(subtitle, style: OnboardingStyle.subtitle),
                    Expanded(
                      child: Center(
                        child: step == 0
                            ? Image.asset(
                                'assets/images/onboarding_hero_plate.png',
                                width: 170,
                                fit: BoxFit.contain,
                              )
                            : Transform.rotate(
                                angle: -1.5 * 3.141592 / 180,
                                child: const SizedBox(
                                  width: 320,
                                  child: CouponTicketCard(
                                    iconPath: 'assets/icons/category/korean.svg',
                                    storeLabel: '정든밤',
                                    title: '2,000원 할인',
                                    subtitle: '1만원 이상 주문 시 사용 가능',
                                    expiryText: '받은 날부터 7일간',
                                    onAction: null,
                                    margin: EdgeInsets.zero,
                                    borderColor: Color(0xFFE1E5EA),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: step == 0 ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: step == 0
                          ? OnboardingStyle.primary
                          : OnboardingStyle.line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: step == 1 ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: step == 1
                          ? OnboardingStyle.primary
                          : OnboardingStyle.line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: OnboardingStyle.primaryButton(),
                onPressed: () {},
                child: Text(button),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickPreview extends StatelessWidget {
  const _PickPreview();

  @override
  Widget build(BuildContext context) {
    final restaurants = [
      _r(1, '정든밤', '한식', '북문'),
      _r(2, '한끼갈비', '한식', '정문'),
      _r(3, '스시하루', '일식', '테크노파크'),
      _r(4, '카페우즈', '카페', '후문'),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('어디서 쓸까요?', style: OnboardingStyle.title),
              const SizedBox(height: 8),
              const Text('원하는 식당을 선택해 주세요.', style: OnboardingStyle.subtitle),
              const SizedBox(height: 16),
              Container(
                height: 46,
                decoration: ShapeDecoration(
                  color: const Color(0xFFF4F5F7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                alignment: Alignment.center,
                child: const TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    hintText: '식당 검색',
                    hintStyle: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14.5,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon:
                        Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              CategoryStrip(selected: 'ALL', onSelect: (_) {}),
              const SizedBox(height: 8),
              Expanded(
                child: RestaurantPickList(
                  loading: false,
                  failed: false,
                  restaurants: restaurants,
                  selectedIndex: 0,
                  onSelect: (_) {},
                  onRetry: () {},
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: OnboardingStyle.primaryButton(),
                onPressed: () {},
                child: const Text('이 식당으로 뽑기'),
              ),
              Center(
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: OnboardingStyle.muted,
                    textStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('건너뛰기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinPreview extends StatelessWidget {
  const _SpinPreview({required this.revealed});

  final bool revealed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                revealed ? '당첨을 축하해요!' : '어떤 쿠폰이 나올까요?',
                style: OnboardingStyle.title,
              ),
              const SizedBox(height: 6),
              Text(
                revealed ? '로그인하면 지갑에 담아드려요' : '두구두구…',
                style: OnboardingStyle.subtitle,
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RouletteWheel(
                    labels: RouletteWheel.prizeLabels,
                    rotation: revealed ? 0 : math.pi * 0.72,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: revealed ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !revealed,
                  child: const CouponTicketCard(
                    iconPath: 'assets/icons/category/all.svg',
                    storeLabel: '정든밤',
                    title: '첫 쿠폰 당첨!',
                    subtitle: '로그인하면 바로 쓸 수 있어요',
                    expiryText: '받은 날부터 7일간',
                    onAction: null,
                    margin: EdgeInsets.zero,
                    borderColor: Color(0xFFE1E5EA),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: OnboardingStyle.kakaoButton(),
                onPressed: revealed ? () {} : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/kakaotalk.svg',
                      width: 22,
                      height: 20,
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('카카오 로그인하고 쿠폰 받기'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
