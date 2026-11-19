import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/affiliate_benefits_screen.dart';
import 'package:new1/coupon/limited_coupon_pick_sheet.dart';
import 'package:new1/services/affiliate_service.dart';
import 'package:new1/services/app_session.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/mileage_service.dart';
import 'package:new1/services/survey_service.dart';
import 'package:new1/survey/survey_screen.dart';

import 'castor/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previous = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = CastorHttpOverrides());
  tearDownAll(() => HttpOverrides.global = previous);
  setUp(() {
    FakeBackend.reset();
    AppSession.changing = false;
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'account-a',
      'jwt_refresh_token': 'refresh-a',
      'user_id': 1,
      'access_expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    });
  });

  const question = {
    'code': 'q',
    'text': '검증 질문',
    'options': [
      {'label': '좋아요', 'value': 'yes'}
    ],
  };
  const offer = {
    'coupon_type_code': 'SURVEY',
    'coupon_type_title': '설문 쿠폰',
    'restaurants': [
      {'restaurant_id': 1, 'name': '검증 식당', 'title': '음료'}
    ],
  };

  Future<void> openSurvey(WidgetTester tester,
      {List<Object> questions = const [question]}) async {
    FakeBackend.routes['/api/surveys/review/'] = (_) => {
          'code': 'review',
          'title': '검증 설문',
          'status': 'open',
          'logged_in': true,
          'questions': questions,
        };
    FakeBackend.routes['/api/surveys/review/reward/'] = (_) => {
          'status': 'open',
          'offer': offer,
        };
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => SurveyScreen.open(context,
                          code: 'review', entry: 'test'),
                      child: const Text('설문 열기')),
                ))));
    await tester.tap(find.text('설문 열기'));
    await tester.pumpAndSettle();
  }

  Future<void> pickSurvey(WidgetTester tester) async {
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요'));
    await tester.pump();
    await tester.tap(find.text('제출하고 쿠폰 받기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('검증 식당'));
    await tester.pump();
  }

  int posts(String path) =>
      FakeBackend.log.where((s) => s == 'POST $path').length;

  for (final questions in <List<Object>>[
    [],
    [
      {...question, 'options': []}
    ],
    [question, question],
    [
      {
        ...question,
        'options': [
          {'value': 'yes', 'label': ''}
        ]
      }
    ],
  ]) {
    testWidgets('유효하지 않은 설문은 오류 화면으로 복구한다: $questions', (tester) async {
      await openSurvey(tester, questions: questions);
      expect(find.text('설문을 불러오지\n못했어요'), findsOneWidget);
      expect(find.text('시작하기'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('설문 POST 대기 중 뒤로가기를 막고 timeout 뒤 GET으로만 결과를 확인한다',
      (tester) async {
    FakeBackend.routes['POST /api/surveys/review/complete/'] =
        (_) => FakeResponse.hang();
    await openSurvey(tester);
    await pickSurvey(tester);
    await tester.tap(find.text('이 식당 쿠폰 받기'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LimitedCouponPickSheet), findsOneWidget);
    expect(find.text('받는 중…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('결과 확인'), findsOneWidget);
    await tester.tap(find.text('결과 확인'));
    await tester.pumpAndSettle();
    expect(find.byType(LimitedCouponPickSheet), findsOneWidget);
    expect(posts('/api/surveys/review/complete/'), 1);
    // The POST can finish on the server after the client has stopped waiting.
    FakeBackend.routes['/api/surveys/review/'] = (_) => {
          'code': 'review',
          'status': 'claimed',
          'logged_in': true,
        };
    await tester.tap(find.text('결과 확인'));
    await tester.pumpAndSettle();
    expect(find.byType(LimitedCouponPickSheet), findsNothing);
    expect(find.text('이미 참여한\n설문이에요'), findsOneWidget);
    expect(posts('/api/surveys/review/complete/'), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('쿠폰 선택 전 이탈은 제출하지 않고 설문을 닫는다', (tester) async {
    await openSurvey(tester);
    await pickSurvey(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SurveyScreen), findsNothing);
    expect(posts('/api/surveys/review/complete/'), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('정상 설문 완료는 발급 코드를 돌려주고 두 라우트를 닫는다', (tester) async {
    FakeBackend.routes['POST /api/surveys/review/complete/'] =
        (_) => FakeResponse.json({
              'coupon_code': 'SURVEY-1',
              'issued_coupons': [
                {'code': 'SURVEY-1', 'restaurant_id': 1}
              ],
            }, status: 201);
    await openSurvey(tester);
    await pickSurvey(tester);
    await tester.tap(find.text('이 식당 쿠폰 받기'));
    await tester.pumpAndSettle();
    expect(find.byType(SurveyScreen), findsNothing);
    expect(find.byType(LimitedCouponPickSheet), findsNothing);
    expect(posts('/api/surveys/review/complete/'), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('일반 한정쿠폰도 timeout 후 결과 확인이 가능하고 재전송하지 않는다', (tester) async {
    const path = '/api/coupons/limited/claim/';
    FakeBackend.routes['POST $path'] = (_) => FakeResponse.hang();
    FakeBackend.routes['/api/coupons/limited/offers/'] = (_) => {
          'results': [
            {...offer, 'claimed': false},
          ]
        };
    LimitedCouponPickResult? outcome;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        outcome = await showLimitedCouponPickSheet(context,
                            offer: LimitedCouponOffer.fromJson(offer));
                      },
                      child: const Text('쿠폰 열기')),
                ))));
    await tester.tap(find.text('쿠폰 열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('검증 식당'));
    await tester.pump();
    await tester.tap(find.text('이 식당 쿠폰 받기'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결과 확인'));
    await tester.pumpAndSettle();
    expect(find.byType(LimitedCouponPickSheet), findsOneWidget);
    expect(posts(path), 1);
    FakeBackend.routes['/api/coupons/limited/offers/'] = (_) => {
          'results': [
            {...offer, 'claimed': true},
          ]
        };
    await tester.tap(find.text('결과 확인'));
    await tester.pumpAndSettle();
    expect(outcome?.claimed, isTrue);
    expect(outcome?.alreadyClaimed, isTrue);
    expect(posts(path), 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('기간이 다르거나 사라진 한정쿠폰은 수령 완료로 추정하지 않는다', () async {
    final original = LimitedCouponOffer.fromJson(
        {...offer, 'claim_ends_at': '2026-11-18T23:59:59+09:00'});
    for (final results in [
      [],
      [
        {
          ...offer,
          'claimed': true,
          'claim_ends_at': '2026-11-19T23:59:59+09:00'
        }
      ],
      [
        {...offer, 'claim_ends_at': '2026-11-18T23:59:59+09:00'}
      ],
    ]) {
      FakeBackend.routes['/api/coupons/limited/offers/'] =
          (_) => {'results': results};
      expect(await CouponService.checkLimitedClaimed(original), isNull);
    }
  });

  testWidgets('방문 상태 500은 오류 카드를 표시하고 같은 상세에서 재조회한다', (tester) async {
    FakeBackend.routes['/api/coupons/stamps/my/'] =
        (_) => {'current': 0, 'target': 0};
    FakeBackend.routes['/api/mileage/visit/'] =
        (_) => FakeResponse.json({'detail': 'temporary'}, status: 500);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AffiliateRestaurantDetailSheet(
      restaurant: AffiliateRestaurantSummary.fromJson(
          {'restaurant_id': 1, 'name': '검증 식당'}),
      coupons: const [],
      requiresLogin: false,
      source: 'test',
      isFavorite: false,
      onFavoriteChanged: (_) {},
      onStampStatusUpdated: (_) {},
      onCouponRedeemed: (_) {},
      onRewardCouponsIssued: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('방문 적립 정보를 불러오지 못했어요.'), findsOneWidget);
    FakeBackend.routes['/api/mileage/visit/'] = (_) => {
          'available': true,
          'points': 100,
          'balance': 500,
          'credited_today': false,
        };
    await tester.ensureVisible(find.text('다시 시도').last);
    await tester.tap(find.text('다시 시도').last);
    await tester.pumpAndSettle();
    expect(find.text('방문 적립 정보를 불러오지 못했어요.'), findsNothing);
    expect(find.text('적립하기'), findsOneWidget);
    expect(
        FakeBackend.log.where((s) => s.startsWith('GET /api/mileage/visit/')),
        hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('방문 적립 미대상은 오류나 재시도를 표시하지 않는다', (tester) async {
    FakeBackend.routes['/api/coupons/stamps/my/'] =
        (_) => {'current': 0, 'target': 0};
    FakeBackend.routes['/api/mileage/visit/'] = (_) => {'available': false};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AffiliateRestaurantDetailSheet(
      restaurant: AffiliateRestaurantSummary.fromJson(
          {'restaurant_id': 1, 'name': '검증 식당'}),
      coupons: const [],
      requiresLogin: false,
      source: 'test',
      isFavorite: false,
      onFavoriteChanged: (_) {},
      onStampStatusUpdated: (_) {},
      onCouponRedeemed: (_) {},
      onRewardCouponsIssued: (_) {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('방문 적립 정보를 불러오지 못했어요.'), findsNothing);
    expect(find.text('적립하기'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('방문 적립은 업무 실패와 불완전한 200 응답을 성공으로 처리하지 않는다', () async {
    for (final body in [
      {'ok': false, 'code': 'invalid_pin'},
      <String, dynamic>{},
      {'ok': true, 'credited': true, 'delta': 0, 'balance': 100},
      {'ok': true, 'credited': true, 'delta': 100},
      {'ok': true, 'credited': false, 'delta': 100, 'balance': 100},
      {'ok': true, 'credited': true, 'delta': 1.5, 'balance': 100},
    ]) {
      FakeBackend.routes['POST /api/mileage/visit/'] = (_) => body;
      final result = await StoreVisitService.credit(1, '1234');
      expect(result.ok, isFalse, reason: '$body');
      expect(result.code, body['code'] ?? 'invalid_response');
    }
    FakeBackend.routes['POST /api/mileage/visit/'] = (_) => {
          'ok': true,
          'credited': true,
          'delta': 100,
          'balance': 500,
        };
    final success = await StoreVisitService.credit(1, '1234');
    expect(success.ok, isTrue);
    expect(success.delta, 100);
    expect(success.balance, 500);
  });

  test('쿠폰의 500·잘못된 성공 응답은 결과 미확인으로 분류한다', () async {
    for (final response in [
      FakeResponse.json({'detail': 'temporary'}, status: 500),
      FakeResponse.json({'ok': false}, status: 200),
      FakeResponse.json({'status': 'claimed'}, status: 201),
    ]) {
      FakeBackend.routes['POST /api/coupons/limited/claim/'] = (_) => response;
      final result = await CouponService.claimLimitedCoupon(
          couponTypeCode: 'TEST', restaurantId: 1);
      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'uncertain');
    }
  });

  test('설문 완료 재조회 실패는 미완료로 단정하지 않는다', () async {
    FakeBackend.routes['/api/surveys/review/'] =
        (_) => FakeResponse.json({}, status: 500);
    expect(await SurveyService.checkCompleted('review'), isNull);
  });
}
