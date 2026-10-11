import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/coupon/stamp_add_dialog.dart';

void main() {
  testWidgets('스탬프 적립 창에 개수와 매장 PIN이 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showStampAddDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('스탬프 적립'), findsOneWidget);
    expect(find.text('적립 개수'), findsOneWidget);
    expect(find.text('매장 PIN'), findsOneWidget);
    expect(find.text('적립하기'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
  });
}
