import 'package:flutter_test/flutter_test.dart';
import 'package:new1/models/coupon_benefits_summary.dart';
import 'package:new1/services/coupon_service.dart';

StampStatus statusOf({
  required int current,
  required int target,
  List<int> thresholds = const [],
  Map<int, String> titles = const {},
}) {
  return StampStatus(
    current: current,
    target: target,
    rewards: [
      for (final t in thresholds)
        StampReward(stamps: t, title: titles[t] ?? '$t개 보상'),
    ],
  );
}

void main() {
  group('StampStatusBoard', () {
    test('판 칸 수는 서버 target(cycle_target)을 그대로 쓴다', () {
      expect(
        statusOf(current: 2, target: 10, thresholds: [3, 5, 10]).boardLength,
        10,
      );
      // 리워드가 1단계뿐인 매장은 그 칸 수만큼만 그린다 (예전엔 10칸 강제)
      expect(statusOf(current: 1, target: 3, thresholds: [3]).boardLength, 3);
    });

    test('리워드가 target 밖에 있으면 판을 리워드까지 늘린다', () {
      expect(
        statusOf(current: 0, target: 5, thresholds: [3, 5, 10]).boardLength,
        10,
      );
    });

    test('다음 리워드는 아직 못 받은 가장 가까운 단계', () {
      final s = statusOf(
        current: 2,
        target: 10,
        thresholds: [3, 5, 10],
        titles: {3: '음료 서비스', 5: '계란말이', 10: '찌개 1인분'},
      );
      expect(s.nextReward?.stamps, 3);
      expect(stampRewardBenefitText(s.nextReward!), '음료 서비스');
      expect(s.remainingToNextReward, 1);
    });

    test('중간 단계를 받은 뒤에는 그 다음 단계까지 남은 개수', () {
      final s = statusOf(current: 3, target: 10, thresholds: [3, 5, 10]);
      expect(s.nextReward?.stamps, 5);
      expect(s.remainingToNextReward, 2);
    });

    test('모든 단계를 받으면 다음 리워드 없음', () {
      final s = statusOf(current: 10, target: 10, thresholds: [3, 5, 10]);
      expect(s.nextReward, isNull);
      expect(s.remainingToNextReward, 0);
    });

    test('rewards 가 비면 임계값을 만들어내지 않는다', () {
      final s = statusOf(current: 2, target: 10);
      expect(s.thresholdRewards, isEmpty);
      expect(s.nextReward, isNull);
      // 리워드 정보가 없을 때만 판 기준으로 남은 개수를 센다
      expect(s.remainingToNextReward, 8);
    });

    test('VISIT 패턴은 다음 방문 구간을 다음 리워드로 본다', () {
      final s = StampStatus(
        current: 2,
        target: 10,
        rewards: const [
          StampReward(visitRange: '1_4', minVisit: 1, maxVisit: 4, title: 'A'),
          StampReward(visitRange: '5_9', minVisit: 5, maxVisit: 9, title: 'B'),
        ],
      );
      expect(s.nextReward?.minVisit, 5);
      expect(s.remainingToNextReward, 3);
    });
  });

  group('resolveStampStatus (공개 요약 폴백)', () {
    const summary = CouponBenefitsStampSection(
      enabled: true,
      ruleType: 'THRESHOLD',
      notes: '하루 최대 5회 적립',
      cycleTarget: 10,
      rewards: [
        StampReward(stamps: 3, title: '음료 서비스'),
        StampReward(stamps: 10, title: '찌개 1인분'),
      ],
    );

    test('개인 현황이 0/0이면 매장 공개 요약으로 판을 그린다', () {
      final s = resolveStampStatus(
        personal: const StampStatus(current: 0, target: 0),
        summary: summary,
      );
      expect(s.boardLength, 10);
      expect(s.nextReward?.stamps, 3);
      expect(s.remainingToNextReward, 3);
      expect(s.notes, '하루 최대 5회 적립');
    });

    test('개인 현황에 판이 있으면 그대로 쓴다', () {
      final s = resolveStampStatus(
        personal: statusOf(current: 4, target: 9, thresholds: [3, 6, 9]),
        summary: summary,
      );
      expect(s.boardLength, 9);
      expect(s.current, 4);
      expect(s.nextReward?.stamps, 6);
    });

    test('스탬프 미운영 매장은 판이 0 (섹션 숨김 조건)', () {
      final s = resolveStampStatus(
        personal: null,
        summary: const CouponBenefitsStampSection(
          enabled: false,
          ruleType: null,
          notes: '',
          cycleTarget: null,
          rewards: [],
        ),
      );
      expect(s.boardLength, 0);
    });
  });

}
