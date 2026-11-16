// QR 로 들어왔을 때 스탬프 적립까지 이어지는지 — 실제 딥링크 → 식당 상세 → QR 시트 →
// 스탬프(PIN) 화면 → 적립 요청 전체를 가짜 서버로 돌린다.
//
// 지키려는 것
//  1) 첫 QR 방문에서도 스탬프 적립(PIN 입력)에 갈 수 있다. (예전엔 첫 방문 시트에 쿠폰 버튼뿐이라
//     첫 손님은 스탬프를 못 찍었다.)
//  2) PIN 입력 화면이 먼저 뜨고, PIN 을 다 누르기 전에는 적립 요청이 나가지 않는다.
//  3) 서버에는 스탬프 버튼이 있는 앱이라는 표시(X-Client-Caps)가 실려 간다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/affiliate_benefits_screen.dart';
import 'package:new1/services/app_config_service.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'castor/castor_screens_test.dart' show installCommonRoutes;
import 'castor/fixtures.dart';
import 'castor/harness.dart';

const _qrLink =
    'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=105&src=sticker';

final _store = fakeStores.firstWhere((s) => s.id == 105);

Map<String, dynamic> _entry(
  String branch, {
  bool withCoupon = true,
  int current = 0,
}) =>
    {
      'branch': branch,
      'restaurant_id': _store.id,
      if (withCoupon) 'coupon_code': 'QR-C1',
      'stamp': {
        'enabled': true,
        'current': current,
        'target': 10,
        'remaining': 10 - current,
        'next_reward': '음료 서비스',
        'stamped_today': false,
      },
    };

void _routes(Map<String, dynamic> entry, {bool withCoupon = true}) {
  final r = FakeBackend.routes;
  r['/api/coupons/my/'] = (q) => [
        if (withCoupon)
          couponJson('QR-C1', _store,
              issueKey: 'QR_VISIT_COUPON:1',
              expires: const Duration(hours: 3)),
      ];
  r['POST /api/mileage/qr-visit/'] = (_) => {
        'credited': true,
        'delta': 100,
        'balance': 300,
        'coupon_issued': false,
        'entry': entry,
      };
  r['POST /api/coupons/stamps/add/'] = (_) => {
        'ok': true,
        'added': 1,
        'current': 1,
        'target': 10,
        'rewards': [
          {'stamps': 5, 'title': '음료 서비스'},
          {'stamps': 10, 'title': '메인 메뉴 1개 무료'},
        ],
      };
  r['POST /api/coupons/redeem/'] = (_) => {'ok': true, 'status': 'REDEEMED'};
}

/// 앱을 띄우고 QR 링크를 연다. QR 시트가 뜰 때까지 시간을 흘린다.
Future<void> _scan(WidgetTester tester) async {
  setPhone(tester);
  SharedPreferences.setMockInitialValues(loggedInPrefs());
  await tester.pumpWidget(castorApp(home: const AffiliateBenefitsScreen()));
  await letItLoad(tester, total: const Duration(seconds: 3));
  DeepLinkService.instance.handleUri(Uri.parse(_qrLink));
  // 앱 코드의 addPostFrameCallback 은 프레임을 새로 요청하지 않는다. 실제 앱은 애니메이션 등으로
  // 프레임이 계속 돌지만, 정지한 테스트 화면에서는 직접 한 프레임을 요청해 줘야 상세 시트가 열린다.
  tester.binding.scheduleFrame();
  await letItLoad(tester, total: const Duration(seconds: 4));
  await settleImages(tester);
  await letItLoad(tester, total: const Duration(seconds: 2));
}

Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: '"$text" 를 화면에서 찾지 못함');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _typePin(WidgetTester tester) async {
  for (var i = 0; i < AppConfigService.pinLength; i++) {
    await _tap(tester, '${(i % 9) + 1}');
  }
  await tester.pump(const Duration(seconds: 1));
}

List<String> _calls(String path) =>
    FakeBackend.log.where((l) => l.startsWith('POST $path')).toList();

void main() {
  setUpAll(() async {
    HttpOverrides.global = CastorHttpOverrides();
    await loadCastorFonts();
    await buildFakePhotos();
  });

  setUp(() {
    FakeBackend.reset();
    installCommonRoutes();
    DeepLinkService.instance.pendingQrEntry.value = null;
  });

  tearDown(() async {
    DeepLinkService.instance.pendingQrEntry.value = null;
  });

  testWidgets('첫 QR 방문: 스탬프만 찍기 → PIN 화면 → PIN 입력 뒤에야 적립 요청', (tester) async {
    _routes(_entry('coupon_arrived'));
    await _scan(tester);

    // 서버에 스탬프 버튼이 있는 앱이라는 표시가 간다
    expect(_calls('/api/mileage/qr-visit/'), isNotEmpty);

    // 첫 방문 시트에 스탬프 적립 길이 있다
    expect(find.text('쿠폰이 도착했어요'), findsOneWidget);
    expect(find.text('스탬프만 찍기'), findsOneWidget);
    expect(find.text('쿠폰 쓰고 스탬프도 찍기'), findsOneWidget);

    await _tap(tester, '스탬프만 찍기');

    // PIN 화면이 먼저 뜬다 — 아직 적립 요청은 없다
    expect(find.text('매장 PIN'), findsOneWidget);
    expect(find.text('스탬프 1개 적립'), findsOneWidget);
    expect(_calls('/api/coupons/stamps/add/'), isEmpty,
        reason: 'PIN 입력 전에 적립 요청이 나가면 안 된다');

    // PIN 을 한 자리 덜 누르면 아직 안 나간다
    for (var i = 0; i < AppConfigService.pinLength - 1; i++) {
      await _tap(tester, '${(i % 9) + 1}');
    }
    expect(_calls('/api/coupons/stamps/add/'), isEmpty);

    // 마지막 자리를 누르면 적립 요청이 나간다
    await _tap(tester, '${((AppConfigService.pinLength - 1) % 9) + 1}');
    await tester.pump(const Duration(seconds: 1));
    final calls = _calls('/api/coupons/stamps/add/');
    expect(calls, hasLength(1));
  });

  testWidgets('첫 QR 방문 요청에는 X-Client-Caps: qr_stamp_buttons 가 실린다', (tester) async {
    String? caps;
    _routes(_entry('coupon_arrived'));
    final base = FakeBackend.routes['POST /api/mileage/qr-visit/']!;
    FakeBackend.routes['POST /api/mileage/qr-visit/'] = (req) {
      caps = req.headers['x-client-caps'];
      return base(req);
    };
    await _scan(tester);
    expect(caps, 'qr_stamp_buttons');
  });

  testWidgets('적립 요청에는 입력한 PIN·개수·매장이 실린다', (tester) async {
    Map<String, dynamic>? sent;
    _routes(_entry('coupon_arrived'));
    final base = FakeBackend.routes['POST /api/coupons/stamps/add/']!;
    FakeBackend.routes['POST /api/coupons/stamps/add/'] = (req) {
      sent = req.jsonBody;
      return base(req);
    };
    await _scan(tester);
    await _tap(tester, '스탬프만 찍기');
    await _typePin(tester);

    expect(sent, isNotNull);
    final n = AppConfigService.pinLength;
    expect(sent!['pin'], [for (var i = 0; i < n; i++) '${(i % 9) + 1}'].join());
    expect(sent!['count'], 1);
    expect(sent!['restaurant_id'], _store.id);
  });

  testWidgets('첫 QR 방문: 쿠폰 쓰고 스탬프도 찍기 → 쿠폰 사용 화면(스탬프 켜짐) → PIN 뒤 사용+적립',
      (tester) async {
    _routes(_entry('coupon_arrived'));
    await _scan(tester);
    await _tap(tester, '쿠폰 쓰고 스탬프도 찍기');

    // 쿠폰 사용 화면, PIN 전에는 아무 요청도 없다
    expect(find.text('쿠폰 사용'), findsOneWidget);
    expect(find.text('몇 명이 함께 결제했나요?'), findsOneWidget);
    expect(_calls('/api/coupons/redeem/'), isEmpty);
    expect(_calls('/api/coupons/stamps/add/'), isEmpty);

    await _typePin(tester);

    expect(_calls('/api/coupons/redeem/'), hasLength(1));
    expect(_calls('/api/coupons/stamps/add/'), hasLength(1));
  });

  testWidgets('재방문(쿠폰 없음): 스탬프 찍기 → PIN 화면 → 적립', (tester) async {
    _routes(_entry('stamp_progress', withCoupon: false, current: 3),
        withCoupon: false);
    await _scan(tester);

    expect(find.text('쿠폰이 도착했어요'), findsNothing);
    expect(find.text('스탬프 찍기'), findsOneWidget);
    await _tap(tester, '스탬프 찍기');
    expect(find.text('매장 PIN'), findsOneWidget);
    expect(_calls('/api/coupons/stamps/add/'), isEmpty);

    await _typePin(tester);
    expect(_calls('/api/coupons/stamps/add/'), hasLength(1));
  });
}
