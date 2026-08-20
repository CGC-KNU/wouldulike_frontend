import 'dart:async';

import 'package:flutter/material.dart';

import 'package:new1/services/mission_service.dart';

/// 미션 리워드 트랙 (프로토타입 화면 7, 스펙 7.3).
/// 세로 타임라인 4단계. 마감 카운트다운은 서버 시각 기준으로만 계산한다.
class MissionTrackScreen extends StatefulWidget {
  const MissionTrackScreen({super.key});

  @override
  State<MissionTrackScreen> createState() => _MissionTrackScreenState();
}

class _MissionTrackScreenState extends State<MissionTrackScreen> {
  static const _primary = Color(0xFF312E81);
  static const _ink = Color(0xFF191F28);
  static const _muted = Color(0xFF4E5968);
  static const _line = Color(0xFFE7E9EF);

  MissionTrack? _track;
  bool _isLoading = true;
  String? _claimingCode;
  Timer? _ticker;

  /// 서버 시각과 기기 시각의 차이. 카운트다운은 이 보정값을 적용해 계산한다.
  Duration _serverOffset = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _track != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final track = await MissionService.fetchTrack();
    if (!mounted) return;
    setState(() {
      _track = track;
      _isLoading = false;
      final serverTime = track?.serverTime;
      _serverOffset = serverTime != null
          ? serverTime.difference(DateTime.now())
          : Duration.zero;
    });
  }

  Future<void> _claim(MissionItem mission) async {
    setState(() => _claimingCode = mission.code);
    final result = await MissionService.claim(mission.code);
    if (!mounted) return;
    setState(() => _claimingCode = null);
    if (result == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('리워드를 받지 못했어요. 잠시 후 다시 시도해 주세요.')));
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('리워드를 받았어요. 내 지갑에서 확인해 보세요.')));
  }

  /// 마감까지 남은 시간. 기기 시간이 아닌 서버 보정 시각 기준 (스펙 7.2·7.3).
  String? _remainingLabel(DateTime? deadline) {
    if (deadline == null) return null;
    final now = DateTime.now().add(_serverOffset);
    final diff = deadline.difference(now);
    if (diff.isNegative) return '마감됨';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (d > 0) return '$d일 $h시간 남음';
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')} 남음';
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const Text(
          '미션 리워드',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        iconTheme: const IconThemeData(color: _ink),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : track == null || track.missions.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFF6366F1),
                  backgroundColor: Colors.white,
                  strokeWidth: 2,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                    children: [
                      if (track.rewardHeadline.isNotEmpty) ...[
                        Text(
                          track.rewardHeadline,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.54,
                            color: _ink,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      for (var i = 0; i < track.missions.length; i++)
                        _buildNode(track.missions[i], isLast: false),
                      // 프로토타입 화면 7의 5번째 노드 — 완주 보너스
                      if (track.completionBonus != null)
                        _buildNode(track.completionBonus!, isLast: true)
                      else
                        _buildBonusPlaceholder(track.allCleared),
                    ],
                  ),
                ),
    );
  }

  /// 서버가 완주 보너스를 아직 안 내려줄 때의 표시 전용 노드 (수령 버튼 없음).
  Widget _buildBonusPlaceholder(bool allCleared) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: allCleared ? _primary : const Color(0xFFEDEFF5),
          ),
          child: Icon(
            Icons.emoji_events_outlined,
            size: 16,
            color: allCleared ? Colors.white : const Color(0xFF8B95A1),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '완주 보너스',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allCleared
                      ? '랜덤 쿠폰 1장 · 최대 3,000원 — 곧 지급돼요'
                      : '랜덤 쿠폰 1장 · 최대 3,000원',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4E5968),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_outlined, size: 48, color: _primary),
                SizedBox(height: 12),
                Text(
                  '진행 중인 미션이 없어요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNode(MissionItem mission, {required bool isLast}) {
    final done = mission.status == MissionStatus.claimed;
    final ready = mission.status == MissionStatus.ready;
    final open = mission.status == MissionStatus.open;
    final expired = mission.status == MissionStatus.expired;
    final remaining = _remainingLabel(mission.deadlineAt);
    final isClaiming = _claimingCode == mission.code;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타임라인 축: 노드 + 아래로 이어지는 선
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? _primary
                      : (ready
                          ? const Color(0xFFFBF3DC)
                          : (open ? Colors.white : _line)),
                  border: open
                      ? Border.all(color: _primary, width: 2.5)
                      : (ready
                          ? Border.all(color: const Color(0xFFE1B53E), width: 2)
                          : null),
                ),
                child: done
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : ready
                        ? const Icon(Icons.card_giftcard,
                            size: 15, color: Color(0xFF8A6410))
                        : (!open
                            ? const Icon(Icons.lock_outline,
                                size: 14, color: Color(0xFF8B95A1))
                            : null),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 3,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: done ? _primary : _line,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 14),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: open || ready ? const Color(0xFFC7CCFB) : _line,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission.title,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: expired ? const Color(0xFF8B95A1) : _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mission.rewardText,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  if (open && mission.target > 1) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (mission.progress / mission.target).clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: _line,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_primary),
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
                  if (remaining != null && (open || ready)) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 13, color: Color(0xFFE11D48)),
                        const SizedBox(width: 4),
                        Text(
                          remaining,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE11D48),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (ready) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isClaiming ? null : () => _claim(mission),
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
            ),
          ),
        ],
      ),
    );
  }
}
