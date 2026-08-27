import 'dart:async';

import 'package:flutter/material.dart';

import 'package:new1/mission/invite_friend.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';
import 'package:new1/mission/welcome_missions.dart';
import 'package:new1/services/mission_service.dart';

/// 미션 화면. 미션은 환영 미션 하나뿐이고, 끝나면 친구 초대만 남는다.
/// 마감 카운트다운은 기기 시간이 아닌 서버 시각 기준으로만 계산한다.
class MissionTrackScreen extends StatefulWidget {
  const MissionTrackScreen({super.key});

  @override
  State<MissionTrackScreen> createState() => _MissionTrackScreenState();
}

class _MissionTrackScreenState extends State<MissionTrackScreen> {
  static const _primary = Color(0xFF312E81);
  static const _ink = Color(0xFF191F28);

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

  /// 환영 미션 완주 리워드 수령. 성공 응답 뒤에만 연출을 재생한다.
  Future<void> _claimWelcome() async {
    final welcome = _track?.welcome;
    if (welcome == null || _claimingCode != null) return;
    final code = welcome.reward?.code ?? 'WELCOME_ALL';
    setState(() => _claimingCode = code);
    final result = await MissionService.claim(code);
    if (!mounted) return;
    setState(() => _claimingCode = null);
    if (result == null) {
      _showClaimError();
      return;
    }
    await _load();
    if (!mounted) return;
    await showCouponIssuedDialog(
      context,
      tag: '환영 미션 완주',
      title: welcome.reward?.rewardText.isNotEmpty == true
          ? welcome.reward!.rewardText
          : '제휴 매장 쿠폰 1장',
    );
  }

  void _showClaimError() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('리워드를 받지 못했어요. 잠시 후 다시 시도해 주세요.')));
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const Text(
          '환영 미션',
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
          : track == null || _isEmpty(track)
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFF6366F1),
                  backgroundColor: Colors.white,
                  strokeWidth: 2,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                    children: _buildStageBody(track),
                  ),
                ),
    );
  }

  bool _isEmpty(MissionTrack track) => track.welcome == null;

  List<Widget> _buildStageBody(MissionTrack track) {
    final welcome = track.welcome!;
    // 기간이 지났는데 서버가 아직 stage를 안 넘겼으면 안내 후 친구 초대로 보낸다.
    if (welcome.isClosedAt(DateTime.now().add(_serverOffset))) {
      return [
        WelcomeMissionClosed(
          onGoStampBook: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const InviteFriendScreen()),
          ),
        ),
      ];
    }
    return [
      WelcomeMissionSection(
        welcome: welcome,
        serverOffset: _serverOffset,
        onClaim: _claimWelcome,
        isClaiming: _claimingCode != null,
      ),
    ];
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
}
