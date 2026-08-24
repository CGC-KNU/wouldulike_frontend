import 'package:flutter/material.dart';

import 'package:new1/services/mission_service.dart';

/// 초보자 미션(회원가입~스탬프 5개)을 끝낸 뒤 열리는 일간·주간 반복 미션 UI.
/// 홈 배너(`RoutineMissionBanner`)와 미션 화면 섹션(`RoutineMissionSection`)이
/// 같은 카드 표현을 공유한다.
const _primary = Color(0xFF312E81);
const _ink = Color(0xFF191F28);
const _muted = Color(0xFF4E5968);
const _line = Color(0xFFE7E9EF);
const _gold = Color(0xFFE1B53E);

/// 다음 초기화까지 남은 시간. 기기 시간이 아닌 서버 보정 시각 기준.
String? routineResetLabel(DateTime? resetAt, Duration serverOffset) {
  if (resetAt == null) return null;
  final diff = resetAt.difference(DateTime.now().add(serverOffset));
  if (diff.isNegative) return '곧 초기화';
  final d = diff.inDays;
  final h = diff.inHours % 24;
  final m = diff.inMinutes % 60;
  if (d > 0) return '$d일 $h시간 후 초기화';
  if (h > 0) return '$h시간 $m분 후 초기화';
  return '$m분 후 초기화';
}

/// 일간/주간 그룹의 대표 초기화 시각 (가장 이른 마감).
DateTime? _earliestReset(List<MissionItem> items) {
  DateTime? earliest;
  for (final m in items) {
    final at = m.deadlineAt;
    if (at == null) continue;
    if (earliest == null || at.isBefore(earliest)) earliest = at;
  }
  return earliest;
}

/// ===== 홈 배너 =====
/// 초보자 미션 배너 자리를 대체한다. 탭하면 미션 화면으로 이동.
class RoutineMissionBanner extends StatelessWidget {
  const RoutineMissionBanner({
    super.key,
    required this.track,
    required this.onTap,
  });

  final MissionTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final claimable = track.claimableCount;
    final remaining = track.routineRemaining;
    final subtitle = claimable > 0
        ? '받을 수 있는 리워드가 $claimable개 있어요'
        : (remaining > 0
            ? '일간·주간 미션 $remaining개가 남았어요'
            : '오늘 미션을 모두 끝냈어요');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7E9EF)),
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '오늘의 미션',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.46,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
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
                  if (claimable > 0)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF3DC),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: _gold),
                      ),
                      child: Text(
                        '리워드 $claimable개',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8A6410),
                        ),
                      ),
                    )
                  else
                    Transform.rotate(
                      angle: -0.052,
                      child: Image.asset(
                        'assets/images/mission_banner.png',
                        width: 46,
                        height: 46,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final m in _bannerItems(track))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _RoutineRow(mission: m.$2, badge: m.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 배너에는 최대 3줄만. 수령 대기 → 진행 중 → 완료 순으로 고른다.
  static List<(String, MissionItem)> _bannerItems(MissionTrack track) {
    final all = <(String, MissionItem)>[
      for (final m in track.daily) ('일간', m),
      for (final m in track.weekly) ('주간', m),
    ];
    int rank((String, MissionItem) e) {
      switch (e.$2.status) {
        case MissionStatus.ready:
          return 0;
        case MissionStatus.open:
          return 1;
        default:
          return 2;
      }
    }

    all.sort((a, b) => rank(a).compareTo(rank(b)));
    return all.take(3).toList();
  }
}

/// 배너용 한 줄: [일간] 스탬프 1회 적립하기 · 0/1 또는 "받기"
class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.mission, required this.badge});

  final MissionItem mission;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final ready = mission.status == MissionStatus.ready;
    final claimed = mission.status == MissionStatus.claimed;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: badge == '일간' ? const Color(0xFFEEF0FF) : const Color(0xFFF3F0FF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            mission.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: claimed ? const Color(0xFF8B95A1) : _ink,
              decoration: claimed ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (ready)
          const Text(
            '받기',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8A6410),
            ),
          )
        else if (claimed)
          const Icon(Icons.check_circle, size: 16, color: _primary)
        else
          Text(
            '${mission.progress}/${mission.target}',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
      ],
    );
  }
}

/// ===== 미션 화면 섹션 =====
class RoutineMissionSection extends StatelessWidget {
  const RoutineMissionSection({
    super.key,
    required this.title,
    required this.description,
    required this.missions,
    required this.serverOffset,
    required this.onClaim,
    this.claimingCode,
  });

  final String title;
  final String description;
  final List<MissionItem> missions;
  final Duration serverOffset;
  final ValueChanged<MissionItem> onClaim;
  final String? claimingCode;

  @override
  Widget build(BuildContext context) {
    if (missions.isEmpty) return const SizedBox.shrink();
    final reset = routineResetLabel(_earliestReset(missions), serverOffset);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: _ink,
              ),
            ),
            const SizedBox(width: 8),
            if (reset != null)
              Text(
                reset,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: _muted,
          ),
        ),
        const SizedBox(height: 12),
        for (final m in missions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RoutineMissionCard(
              mission: m,
              isClaiming: claimingCode == m.code,
              onClaim: () => onClaim(m),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class RoutineMissionCard extends StatelessWidget {
  const RoutineMissionCard({
    super.key,
    required this.mission,
    required this.onClaim,
    this.isClaiming = false,
  });

  final MissionItem mission;
  final VoidCallback onClaim;
  final bool isClaiming;

  @override
  Widget build(BuildContext context) {
    final ready = mission.status == MissionStatus.ready;
    final claimed = mission.status == MissionStatus.claimed;
    final ratio = mission.target == 0
        ? 0.0
        : (mission.progress / mission.target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ready ? _gold : _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: claimed
                      ? _primary
                      : (ready ? const Color(0xFFFBF3DC) : const Color(0xFFEEF0FF)),
                ),
                child: Icon(
                  claimed
                      ? Icons.check
                      : (ready ? Icons.card_giftcard : Icons.bolt),
                  size: 15,
                  color: claimed
                      ? Colors.white
                      : (ready ? const Color(0xFF8A6410) : _primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission.title,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: claimed ? const Color(0xFF8B95A1) : _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mission.rewardText,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!claimed && mission.target > 1) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: _line,
                valueColor: const AlwaysStoppedAnimation<Color>(_primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${mission.progress} / ${mission.target}',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _primary,
              ),
            ),
          ],
          if (ready) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isClaiming ? null : onClaim,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: isClaiming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('리워드 받기'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
