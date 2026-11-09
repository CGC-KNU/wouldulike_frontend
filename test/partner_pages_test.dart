import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/partner/partner_pages.dart';
import 'package:new1/partner/partner_access_controller.dart';

void main() {
  late PartnerAccessController access;
  setUp(() {
    access = PartnerAccessController();
    access.state = PartnerAccess.owner;
    access.userId = 1;
  });
  tearDown(() => access.dispose());
  testWidgets('업종은 서버 label을 사용하고 매장 저장에는 허용 필드만 전송한다', (tester) async {
    Map<String, dynamic>? saved;
    Future<Map<String, dynamic>> request(String route,
        {String method = 'GET', Map<String, dynamic>? body}) async {
      if (method == 'PATCH') {
        saved = body;
        return {'success': true};
      }
      if (route == 'categories')
        return {
          'categories': [
            {'code': 'ALL', 'label': '전체'},
            {'code': 'KOREAN', 'label': '한식'}
          ]
        };
      return {
        'name': '테스트 가게',
        'category': '한식',
        'has_pin': false,
        's3_image_urls': []
      };
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PartnerPage(
                tab: 1, scope: '1:1', request: request, access: access))));
    await tester.pumpAndSettle();
    expect(find.text('한식'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('매장 정보 저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('매장 정보 저장'));
    await tester.pumpAndSettle();
    expect(saved?['category'], '한식');
    expect(saved?.containsKey('name'), false);
    expect(saved?.containsKey('campus'), false);
  });
  testWidgets('매장 변경 전의 늦은 조회 응답이 새 화면을 덮지 않는다', (tester) async {
    final old = Completer<Map<String, dynamic>>();
    Future<Map<String, dynamic>> request(String route,
            {String method = 'GET', Map<String, dynamic>? body}) =>
        old.future;
    Widget page(String scope, PartnerRequest req) => MaterialApp(
        home: Scaffold(
            body: PartnerPage(
                tab: 3, scope: scope, request: req, access: access)));
    await tester.pumpWidget(page('1:1', request));
    await tester.pumpWidget(page(
        '1:2',
        (route, {String method = 'GET', Map<String, dynamic>? body}) async => {
              'feed': [
                {
                  'kind': 'post',
                  'title': '새 매장 게시물',
                  'date': '2026-11-06',
                  'state': 'published'
                }
              ]
            }));
    await tester.pumpAndSettle();
    old.complete({
      'feed': [
        {'kind': 'post', 'title': '이전 매장 게시물'}
      ]
    });
    await tester.pumpAndSettle();
    expect(find.text('새 매장 게시물'), findsOneWidget);
    expect(find.text('이전 매장 게시물'), findsNothing);
  });
  testWidgets('콘텐츠는 post/campaign만 표시하고 내부 활동 항목을 제외한다', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PartnerPage(
      tab: 3,
      scope: '1:1',
      access: access,
      request: (_, {String method = 'GET', Map<String, dynamic>? body}) async =>
          {
        'feed': [
          {
            'kind': 'post',
            'title': '게시물',
            'date': '2026-11-06',
            'state': 'published'
          },
          {
            'kind': 'activity',
            'title': '영업 활동',
            'date': '2026-11-06',
            'state': 'done'
          },
        ]
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('게시물'), findsOneWidget);
    expect(find.text('영업 활동'), findsNothing);
  });
}
