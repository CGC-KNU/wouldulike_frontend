import 'package:flutter_test/flutter_test.dart';
import 'package:new1/utils/analytics_logger.dart';

void main() {
  test('같은 설치에서 LAB 종료 후 일반 실행이 수집 상태를 복원한다', () async {
    var persisted = true;
    Future<void> setEnabled(bool enabled) async => persisted = enabled;
    await AnalyticsLogger.configureCollection(
        isLab: true, setEnabled: setEnabled);
    expect(persisted, isFalse);
    await AnalyticsLogger.configureCollection(
        isLab: false, setEnabled: setEnabled);
    expect(persisted, isTrue);
    await AnalyticsLogger.configureCollection(
        isLab: false, collectionAllowed: false, setEnabled: setEnabled);
    expect(persisted, isFalse);
  });
}
