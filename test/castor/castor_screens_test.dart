// Castor 화면 캡처 — 화면 ID 마다 PNG 한 장(build/castor_shots/<화면 ID>.png).
//
//   flutter test test/castor/castor_screens_test.dart
//
// 가짜 데이터(fixtures.dart)로 실제 화면 위젯을 띄운다. 서버 · Firebase · 기기 없이 돈다.
// 화면 ID = lib/config/screen_ids.dart = GA4 screen_name = Castor 화면 지도 ID.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:new1/affiliate_benefits_screen.dart';
import 'package:new1/coupon/limited_coupon_pick_sheet.dart';
import 'package:new1/coupon/qr_entry_sheet.dart';
import 'package:new1/coupon/redeem_pin_dialog.dart';
import 'package:new1/coupon_list_screen.dart';
import 'package:new1/favorite_restaurants_screen.dart';
import 'package:new1/featured/featured_campaign_screen.dart';
import 'package:new1/food_recommendation_screen.dart';
import 'package:new1/home.dart';
import 'package:new1/login_screen.dart';
import 'package:new1/main.dart';
import 'package:new1/main2.dart';
import 'package:new1/match.dart';
import 'package:new1/mileage/mileage_shop_screen.dart';
import 'package:new1/mileage/my_raffle_entries_screen.dart';
import 'package:new1/mileage/raffle_result_dialog.dart';
import 'package:new1/mileage/raffle_terms_screen.dart';
import 'package:new1/mileage/raffle_winners_screen.dart';
import 'package:new1/mission/invite_friend.dart';
import 'package:new1/mission/mission_track_screen.dart';
import 'package:new1/nearby_restaurants_screen.dart';
import 'package:new1/onboarding/onboarding_intro_screen.dart';
import 'package:new1/onboarding/onboarding_reward_flow.dart';
import 'package:new1/onboarding/signup_onboarding_gate.dart';
import 'package:new1/profile_setup_screen.dart';
import 'package:new1/question_screen.dart';
import 'package:new1/result_screen.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/mileage_service.dart';
import 'package:new1/services/promotion_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/start_survey.dart';
import 'package:new1/wish.dart';

import 'fixtures.dart';
import 'harness.dart';

// ───────────────────────── 공통 가짜 API ─────────────────────────

void installCommonRoutes() {
  final r = FakeBackend.routes;
  // 사용자
  r['/api/users/me/'] = (_) => userMe();
  r['/api/users/me/onboarding-flags/'] = (_) => {
        'flags': {
          'onboarding_intro_seen_v1': true,
          'onboarding_reward_pending_v1': false,
          'onboarding_reward_done_v1': true,
        }
      };
  r['/guests/retrieve/'] = (_) => {'uuid': '00000000-castor-0000-0000-000000000001'};
  // 매장
  r['/restaurants/affiliate-restaurants/'] = (_) => {'restaurants': storesJson()};
  r['/restaurants/affiliate-restaurants/active/'] =
      (_) => {'source': 'all', 'restaurants': storesJson()};
  r['/restaurants/affiliate-restaurants/detail/'] = (q) {
    final id = int.tryParse(q.uri.queryParameters['restaurant_id'] ?? '') ?? fakeStores.first.id;
    final s = fakeStores.firstWhere((e) => e.id == id, orElse: () => fakeStores.first);
    return {'restaurant': storeJson(s, detail: true)};
  };
  // 쿠폰 · 스탬프
  r['/api/coupons/my/'] = (q) {
    final status = q.uri.queryParameters['status'];
    final all = myCoupons();
    return status == null ? all : all.where((c) => c['status'] == status).toList();
  };
  r['/api/coupons/limited/offers/'] = (_) => {'results': []};
  r['/api/coupons/stamps/my/all/'] = (_) => stampsAll();
  r['/api/coupons/signup/restaurants/'] = (_) => {'restaurants': storesJson()};
  r['/api/coupons/signup/restaurants/preview/'] = (_) => {'restaurants': storesJson()};
  // 마일리지 · 응모
  r['/api/mileage/summary/'] = (_) => mileageSummary();
  r['/api/wallet/overview/'] = (_) => walletOverview();
  r['/api/mileage/history/'] = (_) => mileageHistory();
  r['/api/raffles/'] = (_) => raffles();
  r['/api/raffles/my/'] = (_) => myRaffleEntries();
  r['/api/raffles/win-popups/'] = (_) => {'results': []};
  r['/api/raffles/winners/'] = (_) => raffleWinners();
  r['/api/users/me/favorites'] = (_) => [fakeStores[2].id, fakeStores[6].id, fakeStores[0].id];
  r['/api/coupons/stamps/my/'] = (q) {
    final id = int.tryParse(q.uri.queryParameters['restaurant_id'] ?? '') ?? fakeStores.first.id;
    return stampStatus(fakeStores.firstWhere((e) => e.id == id, orElse: () => fakeStores.first));
  };
  r['/restaurants/tab-restaurants/'] = (_) => tabRestaurants();
  r['/api/coupons/invite/my/'] = (_) => {'code': 'SPACE24'};
  // 홈
  r['/trends/trend_list/'] = (_) => trends();
  r['/trends/popup_campaigns/'] = (_) => [];
  r['/api/promotions/featured/current/'] = (_) => {'results': [featuredCampaign()]};
  r['/api/missions/track/'] = (_) => missionTrack();
  r['/restaurants/get-nearby-restaurants/'] = (_) => {'restaurants': randomRestaurants()['random_restaurants']};
  // 음식 추천(옛 화면)
  r['/food-by-type/random-foods/'] = (_) => {'random_foods': randomFoods()};
  r['/food-by-type/unique-random-foods/'] = (_) => {'random_foods': randomFoods()};
  r['/restaurants/get-random-restaurants/'] = (_) => randomRestaurants();
}

// ───────────────────────── 띄우기 도우미 ─────────────────────────

/// 첫 프레임 뒤에 [open] 을 부른다(시트 · 다이얼로그 · 전체 화면 라우트용).
class _Launcher extends StatefulWidget {
  const _Launcher({required this.open, this.background});
  final void Function(BuildContext context) open;
  final Widget? background;
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.background ?? const Scaffold(backgroundColor: Colors.white);
}

Future<void> shoot(
  WidgetTester tester,
  String id, {
  Widget? home,
  Map<String, Object>? prefs,
  void Function()? routes,
  Future<void> Function(WidgetTester tester)? act,
  Duration load = const Duration(seconds: 3),
  VoidCallback? before,
}) async {
  setPhone(tester);
  FakeBackend.reset();
  installCommonRoutes();
  routes?.call();
  SharedPreferences.setMockInitialValues(prefs ?? loggedInPrefs());
  before?.call();

  await tester.pumpWidget(castorApp(home: home));
  await letItLoad(tester, total: load);
  await settleImages(tester);
  if (act != null) {
    await act(tester);
    await settleImages(tester);
  }
  final file = await captureScreen(tester, id);
  if (FakeBackend.misses.isNotEmpty) {
    debugPrint('[castor] $id — 가짜 응답 없는 API: ${FakeBackend.misses.join(', ')}');
  }
  debugPrint('[castor] $id → ${file.path}');

  // 남은 타이머를 비우고 트리를 내린다.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 20));
}

/// 화면 하나가 실패해도 나머지 캡처는 계속한다. 실패는 마지막에 모아 알린다.
final List<String> failures = [];

void screen(String id, Future<void> Function(WidgetTester tester) body) {
  testWidgets(id, (tester) async {
    final errors = <String>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      // 레이아웃 경고 · 이미지 오류는 캡처를 막지 않는다.
      errors.add(msg.split('\n').first);
    };
    try {
      await body(tester);
    } finally {
      FlutterError.onError = prevOnError;
    }
    if (errors.isNotEmpty) {
      debugPrint('[castor] $id — 그리는 중 경고 ${errors.length}건: ${errors.toSet().take(3).join(' | ')}');
    }
  });
}

Future<void> tapText(WidgetTester tester, String text, {Duration settle = const Duration(milliseconds: 600)}) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    debugPrint('[castor] 누를 글자를 못 찾음: $text');
    return;
  }
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(settle);
}

UserCoupon fakeCoupon([int i = 0]) => UserCoupon.fromJson(myCoupons()[i]);

// ───────────────────────── 화면들 ─────────────────────────

void main() {
  setUpAll(() async {
    HttpOverrides.global = CastorHttpOverrides();
    await loadCastorFonts();
    await buildFakePhotos();
    PackageInfo.setMockInitialValues(
      appName: '우주라이크', packageName: 'com.example.castor', version: '2.6.0',
      buildNumber: '60', buildSignature: '');
  });

  // ── 진입 ──
  screen('app.entry', (t) => shoot(t, 'app.entry',
      home: const AppEntryScreen(isLoggedIn: true),
      routes: () => FakeBackend.routes['/api/users/me/'] = (_) => FakeResponse.hang()));

  screen('app.splash', (t) => shoot(t, 'app.splash',
      home: const MainScreen(),
      routes: () => FakeBackend.routes['/api/config/app/'] = (_) => FakeResponse.hang()));

  screen('auth.login', (t) => shoot(t, 'auth.login',
      home: const LoginScreen(),
      prefs: const {},
      before: () => debugDefaultTargetPlatformOverride = TargetPlatform.iOS,
      act: (t) async => debugDefaultTargetPlatformOverride = null));

  screen('auth.profile', (t) => shoot(t, 'auth.profile',
      home: ProfileSetupScreen(
        initialProfile: const {'nickname': '배고픈다람쥐', 'campus': '경북대'},
        isRequiredFlow: true,
        onCompleted: () {},
      )));

  screen('onboarding.gate', (t) => shoot(t, 'onboarding.gate',
      home: const SignupOnboardingGate(
        profileIncomplete: true,
        initialProfile: {'nickname': '', 'campus': null},
      )));

  screen('onboarding.intro', (t) => shoot(t, 'onboarding.intro',
      home: OnboardingIntroScreen(onFinished: () {}),
      prefs: const {},
      load: const Duration(seconds: 4)));

  screen('onboarding.reward', (t) => shoot(t, 'onboarding.reward',
      home: OnboardingRewardFlow(onFinished: () {}),
      prefs: loggedInPrefs({'onboarding_reward_done_v1': false})));

  // ── 탭 ──
  screen('app.tabs', (t) => shoot(t, 'app.tabs', home: const MainAppScreen(), load: const Duration(seconds: 4)));
  screen('home', (t) => shoot(t, 'home', home: const MainAppScreen(), load: const Duration(seconds: 4)));
  screen('store.list', (t) => shoot(t, 'store.list',
      home: const MainAppScreen(),
      act: (t) async {
        await tapText(t, '식당', settle: const Duration(seconds: 3));
      }));
  screen('my', (t) => shoot(t, 'my',
      home: const MainAppScreen(),
      act: (t) async {
        await tapText(t, '마이페이지', settle: const Duration(seconds: 3));
      }));

  // ── 지갑 ──
  for (final (id, tab) in const [
    ('wallet', 0),
    ('wallet.coupon', 0),
    ('wallet.stamp', 1),
    ('wallet.mileage', 2),
  ]) {
    screen(id, (t) => shoot(t, id,
        home: const MainAppScreen(),
        act: (t) async {
          DeepLinkService.instance.pendingWalletTab.value = tab;
          await tapText(t, '내 지갑', settle: const Duration(seconds: 3));
          await t.pump(const Duration(seconds: 1));
        }));
  }

  // ── 둘러보기 ──
  screen('home.mission', (t) => shoot(t, 'home.mission', home: const MissionTrackScreen(entry: 'castor')));
  screen('featured.detail', (t) => shoot(t, 'featured.detail', home: FeaturedCampaignScreen(campaign: parseFeaturedCampaigns({'results': [featuredCampaign()]}).first)));
  screen('store.favorites', (t) => shoot(t, 'store.favorites', home: const FavoriteRestaurantsScreen()));
  screen('store.nearby', (t) => shoot(t, 'store.nearby', home: const NearbyRestaurantsScreen()));
  screen('invite', (t) => shoot(t, 'invite', home: const InviteFriendScreen()));
  screen('my.wishlist', (t) => shoot(t, 'my.wishlist',
      home: const WishlistScreen(),
      prefs: loggedInPrefs({
        'restaurants_data': jsonEncode(wishlistRestaurants()),
        for (final w in wishlistRestaurants().take(4)) 'liked_${w['name']}_${w['road_address']}': true,
      })));

  screen('store.detail', (t) => shoot(t, 'store.detail',
      home: const AffiliateBenefitsScreen(),
      act: (t) async {
        await tapText(t, fakeStores.first.name, settle: const Duration(seconds: 3));
      }));

  // ── 쿠폰 ──
  screen('coupon.limited_offer', (t) => shoot(t, 'coupon.limited_offer',
      home: const MainAppScreen(),
      routes: () => FakeBackend.routes['/api/coupons/limited/offers/'] = (_) => {
            'results': [
              {...limitedOffer(), 'campus_required': true, 'user_campus': null, 'restaurants': []},
            ]
          },
      act: (t) async {
        DeepLinkService.instance.pendingWalletTab.value = 0;
        await tapText(t, '내 지갑', settle: const Duration(seconds: 3));
      }));

  screen('coupon.limited_pick', (t) => shoot(t, 'coupon.limited_pick',
      home: LimitedCouponPickSheet(offer: LimitedCouponOffer.fromJson(limitedOffer())),
      act: (t) => tapText(t, fakeStores[2].name)));

  screen('sheet.coupon_arrived', (t) => shoot(t, 'sheet.coupon_arrived',
      home: _Launcher(
        background: const AffiliateBenefitsScreen(),
        open: (ctx) => showQrEntrySheet(
          ctx,
          entry: QrEntry(
            branch: QrEntryBranch.couponArrived,
            restaurantId: fakeStores[6].id,
            couponCode: 'CSTR-A2',
            stamp: const QrEntryStamp(enabled: true, current: 0, target: 10),
          ),
          restaurantName: fakeStores[6].name,
          coupon: fakeCoupon(1),
        ),
      )));

  Widget pinLauncher() => _Launcher(
        background: const CouponListScreen(source: 'wallet'),
        open: (ctx) => showCouponRedeemPinDialog(
          context: ctx,
          coupon: fakeCoupon(0),
          restaurantId: fakeStores[0].id,
          restaurantName: fakeStores[0].name,
          notes: '1인 1회 · 다른 쿠폰과 중복 사용 불가',
          fromScreen: 'castor',
        ),
      );

  screen('coupon.use', (t) => shoot(t, 'coupon.use', home: pinLauncher()));
  screen('coupon.redeem_pin', (t) => shoot(t, 'coupon.redeem_pin',
      home: pinLauncher(),
      act: (t) async {
        await tapText(t, '1', settle: const Duration(milliseconds: 100));
        await tapText(t, '2', settle: const Duration(milliseconds: 300));
      }));
  screen('coupon.done', (t) => shoot(t, 'coupon.done',
      home: pinLauncher(),
      routes: () => FakeBackend.routes['/api/coupons/redeem/'] = (_) => {'ok': true, 'coupon_code': 'CSTR-A1'},
      act: (t) async {
        for (final d in ['1', '2', '3', '4']) {
          await tapText(t, d, settle: const Duration(milliseconds: 120));
        }
        await t.pump(const Duration(seconds: 2));
      }));

  // ── 마일리지 · 응모 ──
  screen('mileage.shop', (t) => shoot(t, 'mileage.shop', home: const MileageShopScreen()));
  screen('raffle.entries', (t) => shoot(t, 'raffle.entries', home: const MyRaffleEntriesScreen()));
  screen('raffle.terms', (t) => shoot(t, 'raffle.terms', home: const RaffleTermsScreen()));
  screen('raffle.winners', (t) => shoot(t, 'raffle.winners', home: const RaffleWinnersScreen()));
  screen('raffle.result', (t) => shoot(t, 'raffle.result',
      home: _Launcher(
        background: const MyRaffleEntriesScreen(),
        open: (ctx) => showRaffleResultDialog(ctx, won: true, prizeAmount: 10000, title: '식사권', raffleId: 29),
      ),
      act: (t) async => t.pump(const Duration(seconds: 3))));

  // ── 그 밖(옛 추천 흐름) ──
  screen('etc.start_survey', (t) => shoot(t, 'etc.start_survey', home: const StartSurveyScreen(), load: const Duration(seconds: 5)));
  screen('etc.quiz', (t) => shoot(t, 'etc.quiz', home: QuizScreen(questionIndex: 0, answerPressed: (_) {})));
  screen('etc.result', (t) => shoot(t, 'etc.result',
      home: ResultScreen(totalScore: 2121, selectedQuestions: List.filled(12, 'x'), resetQuiz: () {})));
  screen('etc.food_recommendation', (t) => shoot(t, 'etc.food_recommendation', home: const FoodRecommendationScreen()));
  screen('etc.food_restaurant_list', (t) => shoot(t, 'etc.food_restaurant_list',
      home: const FoodRestaurantListScreen(foodName: '김치찌개', imageUrl: 'https://castor-fake-images.s3.ap-northeast-2.amazonaws.com/store/food_korean.jpg')));
  screen('etc.matching', (t) => shoot(t, 'etc.matching', home: const MatchingScreen()));
}
