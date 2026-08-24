import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/mission_service.dart';

Map<String, dynamic> _m(String code, String status,
        {int progress = 0, int target = 1}) =>
    <String, dynamic>{
      'code': code,
      'title': code,
      'reward_text': '',
      'status': status,
      'progress': progress,
      'target': target,
    };

void main() {
  test('초보자 미션이 남아 있으면 반복 미션이 있어도 beginnerDone은 false', () {
    final track = MissionTrack.fromJson({
      'missions': [_m('SIGNUP', 'CLAIMED'), _m('FIRST_USE', 'OPEN')],
      'daily': [_m('DAILY_STAMP_1', 'OPEN')],
    });
    expect(track.beginnerDone, isFalse);
    expect(track.hasRoutine, isTrue);
  });

  test('READY(미수령) 초보자 미션은 아직 끝난 게 아니다', () {
    final track = MissionTrack.fromJson({
      'missions': [_m('SIGNUP', 'CLAIMED'), _m('STAMP_5', 'READY')],
    });
    expect(track.beginnerDone, isFalse);
  });

  test('수령 완료·만료만 남으면 beginnerDone', () {
    final track = MissionTrack.fromJson({
      'missions': [_m('SIGNUP', 'CLAIMED'), _m('FIRST_USE', 'EXPIRED')],
    });
    expect(track.beginnerDone, isTrue);
  });

  test('일간/주간 파싱 + 남은 개수·수령 대기 개수', () {
    final track = MissionTrack.fromJson({
      'missions': [_m('SIGNUP', 'CLAIMED')],
      'daily': [
        _m('DAILY_STAMP_1', 'READY', progress: 1),
        _m('DAILY_COUPON_USE_1', 'OPEN'),
      ],
      'weekly': [_m('WEEKLY_STAMP_3', 'OPEN', progress: 1, target: 3)],
    });
    expect(track.daily.length, 2);
    expect(track.weekly.single.target, 3);
    // READY는 isDone 취급이라 남은 건 OPEN 2개
    expect(track.routineRemaining, 2);
    expect(track.claimableCount, 1);
  });

  test('반복 미션이 없으면 hasRoutine false (구버전 서버 응답 호환)', () {
    final track = MissionTrack.fromJson({
      'missions': [_m('SIGNUP', 'CLAIMED')],
    });
    expect(track.hasRoutine, isFalse);
    expect(track.daily, isEmpty);
  });
}
