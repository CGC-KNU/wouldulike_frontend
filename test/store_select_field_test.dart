import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/store_select_field.dart';
import 'package:new1/data/campus_options.dart';
import 'package:new1/services/affiliate_service.dart';

AffiliateRestaurantSummary _store(int id, String name, {String? campus}) =>
    AffiliateRestaurantSummary(
      campus: campus,
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
  group('filterStoresForPick', () {
    final stores = [
      _store(1, '경대국밥', campus: '경북대'),
      _store(2, '영대분식', campus: '영남대'),
      _store(3, '미지정식당'),
    ];

    test('대학가를 고르면 그 대학가 매장만', () {
      final picked = filterStoresForPick(stores, campus: '영남대');
      expect(picked.map((s) => s.id), [2]);
    });

    test('전체는 대학가 미지정 매장까지 모두', () {
      final picked = filterStoresForPick(stores, campus: kCampusFilterAll);
      expect(picked.map((s) => s.id), [1, 2, 3]);
    });

    test('검색어는 대학가와 함께 적용', () {
      final picked =
          filterStoresForPick(stores, campus: kCampusFilterAll, keyword: '국밥');
      expect(picked.map((s) => s.id), [1]);
    });
  });

  testWidgets('대학가 칩을 누르면 그 값이 전달된다', (tester) async {
    String? tapped;
    await tester.pumpWidget(_host(
      CampusChips(selected: kCampusFilterAll, onSelected: (v) => tapped = v),
    ));
    expect(find.text('전체'), findsOneWidget);
    await tester.tap(find.text('계명대'));
    expect(tapped, '계명대');
  });

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
