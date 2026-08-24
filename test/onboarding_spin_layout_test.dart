import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/onboarding/onboarding_reward_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 작은 화면(iPhone SE급)에서도 룰렛 단계가 오버플로 없이 들어가야 한다.
  testWidgets('룰렛 화면이 작은 화면에서도 안 깨진다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_picked_restaurant_id': 1,
      'onboarding_picked_restaurant_name': '한끼갈비',
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: OnboardingRewardFlow(preLogin: true, onFinished: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(tester.takeException(), isNull);
  });
}
