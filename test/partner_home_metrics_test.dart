import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/partner/partner_design.dart';
import 'package:new1/partner/widgets/home_metrics.dart';

void main() {
  final bucket = {
    'views': 1234,
    'reach': 890,
    'status': 'ok',
    'captured_at': '2026-11-11T09:00:00+09:00'
  };
  final data = <String, dynamic>{
    'store': {'stamp_enabled': true},
    'metrics': {
      'since': '2026-04-01',
      'coupon_used': {'month': 3, 'total': 17},
      'stamp': {'month': 8, 'total': 45},
      'promotion': {
        'month': bucket,
        'total': {...bucket, 'views': 4567}
      },
      'instagram': {...bucket, 'views': 98765},
      'store_views': {
        'month': 56,
        'total': 789,
        'month_status': 'ok',
        'total_status': 'partial',
        'through': '2026-11-10',
        'available_from': '2026-05-05'
      },
    },
  };

  Widget app(Map<String, dynamic> payload, {double scale = 1}) => MaterialApp(
        theme: PartnerDesign.theme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      PartnerHomeMetrics(data: payload),
                      PartnerInstagramSummary(data: payload)
                    ])))),
      );

  testWidgets('공통 네 카드에 월간·누적을 표시하고 전체 인스타와 일부 기간을 구분한다', (tester) async {
    await tester.pumpWidget(app(data));
    expect(find.text('홍보 게시물 도달·조회'), findsOneWidget);
    expect(find.text('매장 상세 열람'), findsOneWidget);
    expect(find.text('이번 달'), findsNothing);
    expect(find.text('입점 후 누적'), findsNothing);
    expect(find.text('3장 / 누적 17장'), findsOneWidget);
    expect(find.text('8개 / 누적 45개'), findsOneWidget);
    expect(find.textContaining('조회 1,234회'), findsOneWidget);
    expect(find.textContaining('일부 기간입니다.'), findsOneWidget);
    expect(find.text('우주라이크 전체 인스타 성과'), findsOneWidget);
    expect(find.text('조회 98,765회'), findsOneWidget);
    expect(find.text('재방문'), findsNothing);
    expect(find.text('단골 누적'), findsNothing);
  });

  testWidgets('스탬프 미사용과 수집 실패를 실제 0으로 표시하지 않는다', (tester) async {
    await tester.pumpWidget(app({
      'store': {'stamp_enabled': false},
      'metrics': {
        'since': null,
        'promotion': {'status': 'unavailable'},
        'instagram': {'status': 'unavailable'},
        'store_views': {
          'month_status': 'pending',
          'total_status': 'unknown_start'
        }
      },
    }));
    expect(find.text('미사용'), findsOneWidget);
    expect(find.textContaining('집계 준비 중'), findsOneWidget);
    expect(find.textContaining('입점 기준일 미등록'), findsOneWidget);
    expect(find.text('0회'), findsNothing);
    expect(find.text('조회 0회'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
    for (final text in tester.widgetList<Text>(find.byWidgetPredicate(
        (widget) =>
            widget is Text && (widget.data?.contains('집계 미확인') ?? false)))) {
      expect(text.style?.color, PartnerDesign.red);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px·큰 글자에서도 지표가 넘치지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(data, scale: 2));
    expect(tester.takeException(), isNull);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1500));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
