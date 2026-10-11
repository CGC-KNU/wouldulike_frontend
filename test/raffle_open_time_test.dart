import 'package:flutter_test/flutter_test.dart';
import 'package:new1/mileage/mileage_shop_screen.dart';

void main() {
  test('다음 응모 시작 시각을 "월 일(요일) 시"로 쓴다', () {
    expect(formatRaffleOpenTime(DateTime(2026, 10, 6, 11)), '10월 6일(화) 11시');
    expect(
      formatRaffleOpenTime(DateTime(2026, 10, 12, 11, 30)),
      '10월 12일(월) 11시 30분',
    );
  });
}
