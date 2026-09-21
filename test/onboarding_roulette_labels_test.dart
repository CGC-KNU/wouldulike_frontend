import 'package:flutter_test/flutter_test.dart';
import 'package:new1/onboarding/widgets/roulette_wheel.dart';

void main() {
  test('당첨 칸(0번)은 항상 쿠폰이고 포인터가 거기 멈춘다', () {
    expect(RouletteWheel.prizeLabels.first, '쿠폰');
    expect(
      RouletteWheel.rotationForIndex(0, RouletteWheel.prizeLabels.length),
      0,
    );
  });

  test('칸 비율: 쿠폰 절반, 마일리지 25%, 꽝 25%', () {
    const labels = RouletteWheel.prizeLabels;
    expect(labels.toSet(), {'쿠폰', '마일리지', '꽝'});
    expect(labels.where((l) => l == '쿠폰').length, labels.length ~/ 2);
    expect(labels.where((l) => l == '마일리지').length, labels.length ~/ 4);
    expect(labels.where((l) => l == '꽝').length, labels.length ~/ 4);
  });
}
