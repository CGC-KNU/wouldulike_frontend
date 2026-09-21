import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/store_select_field.dart';
import 'package:new1/services/affiliate_service.dart';

AffiliateRestaurantSummary _store(int id, String name) =>
    AffiliateRestaurantSummary(
      id: id,
      name: name,
      description: '',
      address: '',
      category: '한식',
      zone: '',
      phoneNumber: '',
      url: '',
      imageUrls: const [],
      stampCurrent: 0,
      stampTarget: 10,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('매장 미선택 상태는 안내 문구를 보여준다', (tester) async {
    await tester.pumpWidget(_host(
      StoreSelectField(selected: null, onSelected: (_) {}),
    ));

    expect(find.text('사용할 매장'), findsOneWidget);
    expect(find.text('매장을 선택하세요'), findsOneWidget);
  });

  testWidgets('매장을 고르면 그 이름이 표시된다', (tester) async {
    await tester.pumpWidget(_host(
      StoreSelectField(selected: _store(30, '고니식탁'), onSelected: (_) {}),
    ));

    expect(find.text('고니식탁'), findsOneWidget);
    expect(find.text('매장을 선택하세요'), findsNothing);
  });

  testWidgets('전송 중(enabled=false)에는 매장을 바꿀 수 없다', (tester) async {
    var opened = false;
    await tester.pumpWidget(_host(
      StoreSelectField(
        selected: null,
        enabled: false,
        onSelected: (_) => opened = true,
      ),
    ));

    await tester.tap(find.text('매장을 선택하세요'));
    await tester.pump();

    expect(opened, isFalse);
  });
}
