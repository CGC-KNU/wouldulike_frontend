import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/models/coupon_benefits_summary.dart';
import 'package:new1/widgets/restaurant_coupon_benefits_content.dart';

import 'coupon_benefits_summary_test.dart' show burritoSummaryFixture;

void main() {
  testWidgets('renders signup, referral, and stamp section titles', (tester) async {
    final summary = CouponBenefitsSummary.tryParse(burritoSummaryFixture)!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RestaurantCouponBenefitsContent(summary: summary),
          ),
        ),
      ),
    );

    expect(find.text('신규가입 혜택'), findsOneWidget);
    expect(find.textContaining('친구초대'), findsWidgets);
    expect(find.text('스탬프 혜택'), findsOneWidget);
  });
}
