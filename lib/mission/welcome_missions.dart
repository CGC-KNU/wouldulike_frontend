import 'package:flutter/material.dart';

import 'package:new1/services/mission_service.dart';

const _navy = Color(0xFF202038);
const _indigo = Color(0xFF4F46E5);
const _ink = Color(0xFF17171B);
const _muted = Color(0xFF6B6B73);
const _sub = Color(0xFF9A9AA2);
const _line = Color(0xFFE9E9ED);
const _surface = Color(0xFFF6F6F8);
const _yellow = Color(0xFFFFD84D);
const _yellowSoft = Color(0xFFFFF6CD);

String? welcomeRemainingLabel(
  DateTime? endsAt,
  Duration serverOffset, {
  bool short = false,
}) {
  if (endsAt == null) return null;
  final diff = endsAt.difference(DateTime.now().add(serverOffset));
  if (diff.isNegative) return '종료됨';
  final d = diff.inDays;
  final h = diff.inHours % 24;
  final m = diff.inMinutes % 60;
  final s = diff.inSeconds % 60;
  if (d > 0) return 'D-${d + 1}';
  if (short) return '$h시간 $m분';
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

/// 상세 화면의 큰 카운트다운용. 일(day)을 따로 끊지 않고 전체 시간을 사용해
/// 시간의 흐름이 `00:00:00` 형식에서 계속 이어지게 한다.
String? welcomeCountdownLabel(DateTime? endsAt, Duration serverOffset) {
  if (endsAt == null) return null;
  final diff = endsAt.difference(DateTime.now().add(serverOffset));
  if (diff.isNegative) return '00:00:00';
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  final s = diff.inSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

/// 홈에서는 상세 미션을 반복하지 않고 현재 상태와 다음 행동만 보여준다.
class WelcomeMissionBanner extends StatelessWidget {
  const WelcomeMissionBanner({
    super.key,
    required this.welcome,
    required this.serverOffset,
    required this.onTap,
  });

  final WelcomeMissions welcome;
  final Duration serverOffset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = welcome.rewardReady && !welcome.rewardClaimed;
    final total = welcome.missions.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A14123C),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프로토타입 .mb-main — 문구 왼쪽, 선물 상자 오른쪽
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ready ? '선물이 도착했어요' : '미션 깨고 쿠폰 받아가세요',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.46,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          ready
                              ? '제휴 매장 쿠폰이 기다리고 있어요'
                              : '간단한 미션 $total개, 지금 ${welcome.remainingCount}개 남았어요',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.12,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Transform.rotate(
                    angle: -0.052, // -3deg (프로토타입 .mb-img)
                    child: Image.asset(
                      'assets/images/mission_banner.png',
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _TrackStrip(missions: welcome.missions),
            ],
          ),
        ),
      ),
    );
  }
}

/// 프로토타입 .trk — 미션마다 노드 하나, 마지막은 금색 선물 노드.
class _TrackStrip extends StatelessWidget {
  const _TrackStrip({required this.missions});

  final List<MissionItem> missions;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < missions.length; i++) {
      final done = missions[i].isDone;
      // 아직 안 끝난 첫 미션이 '현재' 노드
      final current = !done && missions.take(i).every((e) => e.isDone);
      children.add(
        Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? _indigo : (current ? Colors.white : _line),
            border: current ? Border.all(color: _indigo, width: 2.5) : null,
          ),
          child: done
              ? const Icon(Icons.check, size: 11, color: Colors.white)
              : null,
        ),
      );
      children.add(
        Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: done ? _indigo : _line,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      );
    }
    children.add(
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFBF3DC),
          border: Border.all(color: const Color(0xFFE1B53E), width: 2),
        ),
        child:
            const Icon(Icons.card_giftcard, size: 14, color: Color(0xFF8A6410)),
      ),
    );
    return Row(children: children);
  }
}

class WelcomeMissionRow extends StatelessWidget {
  const WelcomeMissionRow({super.key, required this.mission});
  final MissionItem mission;

  @override
  Widget build(BuildContext context) => _MissionRow(mission: mission);
}

/// 상세 화면은 카드 여러 장 대신 하나의 체크리스트로 읽힌다.
class WelcomeMissionSection extends StatelessWidget {
  const WelcomeMissionSection({
    super.key,
    required this.welcome,
    required this.serverOffset,
    required this.onClaim,
    this.isClaiming = false,
    this.countdownOverride,
  });

  final WelcomeMissions welcome;
  final Duration serverOffset;
  final VoidCallback onClaim;
  final bool isClaiming;

  /// 골든 테스트·디자인 프리뷰처럼 고정 시각이 필요한 경우에만 사용한다.
  final String? countdownOverride;

  @override
  Widget build(BuildContext context) {
    final total = welcome.missions.length;
    final done = total - welcome.remainingCount;
    final countdown = countdownOverride ??
        welcomeCountdownLabel(welcome.endsAt, serverOffset);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$done/$total 완료',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _indigo,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '우주라이크를\n가볍게 시작해볼까요?',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 25,
            height: 1.28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: _ink,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          '두 가지를 마치면 제휴 매장 쿠폰을 드려요',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _muted,
          ),
        ),
        if (countdown != null) ...[
          const SizedBox(height: 22),
          _CountdownPanel(value: countdown),
        ],
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              for (var i = 0; i < welcome.missions.length; i++) ...[
                _MissionRow(mission: welcome.missions[i], number: i + 1),
                if (i < welcome.missions.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 64),
                    child: Divider(height: 1, color: _line),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _RewardTicket(
          welcome: welcome,
          onClaim: onClaim,
          isClaiming: isClaiming,
        ),
      ],
    );
  }
}

class _CountdownPanel extends StatelessWidget {
  const _CountdownPanel({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '환영 미션 종료까지 $value 남음',
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MISSION CLOSES IN',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Color(0xFFB9B9C7),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '환영 미션 종료까지',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 27,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                height: 1,
                color: _yellow,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.mission, this.number});
  final MissionItem mission;
  final int? number;

  @override
  Widget build(BuildContext context) {
    final done = mission.isDone;
    final progress = mission.target == 0
        ? 0.0
        : (mission.progress / mission.target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? _navy : _surface,
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : Text(
                    '${number ?? 1}',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _muted,
                    ),
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: done ? _sub : _ink,
                  ),
                ),
                if (mission.rewardText.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    mission.rewardText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                ],
                if (!done && mission.target > 1) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: _line,
                      valueColor: const AlwaysStoppedAnimation(_indigo),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            done ? '완료' : '${mission.progress}/${mission.target}',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: done ? _sub : _indigo,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardTicket extends StatelessWidget {
  const _RewardTicket({
    required this.welcome,
    required this.onClaim,
    required this.isClaiming,
  });
  final WelcomeMissions welcome;
  final VoidCallback onClaim;
  final bool isClaiming;

  @override
  Widget build(BuildContext context) {
    final claimed = welcome.rewardClaimed;
    final ready = welcome.rewardReady && !claimed;
    final reward = welcome.reward;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _yellowSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: _yellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_activity_rounded, color: _navy),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WELCOME REWARD',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF806700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reward?.rewardText.isNotEmpty == true
                          ? reward!.rewardText
                          : '제휴 매장 쿠폰 1장',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (claimed) const Icon(Icons.check_circle_rounded, color: _navy),
            ],
          ),
          if (!claimed) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: ready && !isClaiming ? onClaim : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE3DDBF),
                  disabledForegroundColor: const Color(0xFF99927B),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: isClaiming
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(ready ? '쿠폰 받기' : '미션을 완료하면 받을 수 있어요'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class WelcomeMissionClosed extends StatelessWidget {
  const WelcomeMissionClosed({super.key, required this.onGoStampBook});
  final VoidCallback onGoStampBook;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '환영 미션이 끝났어요',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '이제 친구와 우주라이크를 함께 써보세요.',
          style:
              TextStyle(fontFamily: 'Pretendard', fontSize: 14, color: _muted),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onGoStampBook,
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '친구 초대하기',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
