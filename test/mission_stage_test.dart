import 'package:flutter_test/flutter_test.dart';
import 'package:new1/mission/welcome_missions.dart';
import 'package:new1/services/mission_service.dart';

void main() {
  group('stage 판별', () {
    test('stage 필드가 없으면 payload 모양으로 판별한다', () {
      expect(
        MissionTrack.fromJson({
          'welcome': {'missions': []}
        }).stage,
        MissionStage.welcome,
      );
      // 환영 미션 데이터가 없으면 친구 초대 단계다.
      expect(MissionTrack.fromJson({}).stage, MissionStage.invite);
    });

    test('stage 필드가 있으면 그것을 따른다', () {
      final track = MissionTrack.fromJson({'stage': 'WELCOME'});
      expect(track.stage, MissionStage.welcome);
    });
  });

  group('환영 미션', () {
    test('큰 타이머는 남은 전체 시간을 HH:MM:SS로 표시한다', () {
      final end = DateTime.now().add(
        const Duration(hours: 27, minutes: 4, seconds: 5),
      );
      final label = welcomeCountdownLabel(end, Duration.zero)!;
      // 실행 중 1초가 지날 수 있으므로 초만 한 칸 차이를 허용한다.
      expect(label, matches(RegExp(r'^27:04:0[34]$')));
    });

    Map<String, dynamic> item(String code, String status,
            {int progress = 0, int target = 1}) =>
        {
          'code': code,
          'title': code,
          'reward_text': '',
          'status': status,
          'progress': progress,
          'target': target,
        };

    test('둘 다 끝나야 완주로 본다', () {
      final partial = WelcomeMissions.fromJson({
        'missions': [
          item('WELCOME_COUPON_USE', 'CLAIMED', progress: 1),
          item('WELCOME_STAMP_2', 'OPEN', progress: 1, target: 2),
        ],
      });
      expect(partial.allCleared, isFalse);
      expect(partial.remainingCount, 1);

      final done = WelcomeMissions.fromJson({
        'missions': [
          item('WELCOME_COUPON_USE', 'CLAIMED', progress: 1),
          item('WELCOME_STAMP_2', 'CLAIMED', progress: 2, target: 2),
        ],
      });
      expect(done.allCleared, isTrue);
      // 서버가 reward를 안 내려주면 클라이언트 판단으로 대체한다.
      expect(done.rewardReady, isTrue);
    });

    test('서버 reward status가 클라이언트 판단보다 우선한다', () {
      final w = WelcomeMissions.fromJson({
        'missions': [item('WELCOME_COUPON_USE', 'CLAIMED', progress: 1)],
        'reward': item('WELCOME_ALL', 'CLAIMED'),
      });
      expect(w.allCleared, isTrue);
      expect(w.rewardClaimed, isTrue);
      expect(w.rewardReady, isFalse);
    });
  });

  group('프로모 블록', () {
    test('https + 허용 도메인만 링크로 통과한다', () {
      expect(PromoBlock.sanitizeLink('https://wouldulike.com/event')?.host,
          'wouldulike.com');
      expect(PromoBlock.sanitizeLink('https://cdn.wouldulike.com/e')?.host,
          'cdn.wouldulike.com');
      // 스킴·도메인 우회는 전부 막는다.
      expect(PromoBlock.sanitizeLink('http://wouldulike.com'), isNull);
      expect(PromoBlock.sanitizeLink('javascript:alert(1)'), isNull);
      expect(PromoBlock.sanitizeLink('intent://wouldulike.com#Intent;end'),
          isNull);
      expect(
          PromoBlock.sanitizeLink('https://evil.com/wouldulike.com'), isNull);
      // 접미사만 같은 도메인도 막는다 (notwouldulike.com)
      expect(PromoBlock.sanitizeLink('https://notwouldulike.com'), isNull);
      expect(PromoBlock.sanitizeLink(''), isNull);
      expect(PromoBlock.sanitizeLink(null), isNull);
    });

    test('active·기간·제목을 모두 만족해야 노출한다', () {
      final now = DateTime(2026, 8, 25, 12);
      PromoBlock make(Map<String, dynamic> extra) => PromoBlock.fromJson({
            'active': true,
            'title': '8월 기획전',
            ...extra,
          });

      expect(make({}).isVisibleAt(now), isTrue);
      expect(make({'active': false}).isVisibleAt(now), isFalse);
      expect(make({'title': ''}).isVisibleAt(now), isFalse);
      expect(
        make({'starts_at': '2026-08-26T00:00:00'}).isVisibleAt(now),
        isFalse,
      );
      expect(
        make({'ends_at': '2026-08-24T23:59:59'}).isVisibleAt(now),
        isFalse,
      );
    });

    test('http 이미지는 버리고 텍스트형으로 떨어뜨린다', () {
      final block = PromoBlock.fromJson({
        'active': true,
        'title': 'x',
        'image_url': 'http://cdn.example.com/a.png',
      });
      expect(block.imageUrl, isNull);
    });
  });

  group('환영 미션 종료', () {
    Map<String, dynamic> m(String status) => {
          'code': 'WELCOME_STAMP_2',
          'title': '',
          'reward_text': '',
          'status': status,
          'progress': 0,
          'target': 2,
        };
    final now = DateTime(2026, 8, 27, 12);

    test('3일이 지나면 닫힌 것으로 본다', () {
      final w = WelcomeMissions.fromJson({
        'ends_at': '2026-08-26T12:00:00',
        'missions': [m('OPEN')],
      });
      expect(w.isClosedAt(now), isTrue);
    });

    test('기간이 남아 있으면 열려 있다', () {
      final w = WelcomeMissions.fromJson({
        'ends_at': '2026-08-28T12:00:00',
        'missions': [m('OPEN')],
      });
      expect(w.isClosedAt(now), isFalse);
    });

    test('기간이 지나도 못 받은 리워드가 있으면 닫지 않는다', () {
      final w = WelcomeMissions.fromJson({
        'ends_at': '2026-08-26T12:00:00',
        'missions': [m('CLAIMED')],
        'reward': {'code': 'WELCOME_ALL', 'status': 'READY'},
      });
      expect(w.rewardReady, isTrue);
      expect(w.isClosedAt(now), isFalse);
    });

    test('종료 시각이 없으면 서버 stage만 따른다', () {
      final w = WelcomeMissions.fromJson({
        'missions': [m('OPEN')]
      });
      expect(w.isClosedAt(now), isFalse);
    });
  });
}
