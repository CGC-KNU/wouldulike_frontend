import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';

import 'package:new1/mission/invite_friend.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';
import 'package:new1/mission/welcome_missions.dart';
import 'package:new1/services/mission_service.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';

/// 미션 화면. 미션은 환영 미션 하나뿐이고, 끝나면 친구 초대만 남는다.
/// 마감 카운트다운은 기기 시간이 아닌 서버 시각 기준으로만 계산한다.
class MissionTrackScreen extends StatefulWidget {
  const MissionTrackScreen({super.key, this.entry = 'unknown'});

  /// 진입 경로 (home_banner · wallet · deeplink). 미션 지속률의 분모를
  /// 경로별로 나눠 보기 위해 호출부에서 넘긴다.
  final String entry;

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

  /// 진입 이벤트는 화면당 1회만 보낸다 (_load는 리워드 수령 후에도 다시 돈다).
  bool _viewLogged = false;

  /// 이미 mission_completed를 보낸 미션 코드.
  ///
  /// 달성은 미션당 1회뿐인 사건이라 화면을 다시 열 때마다 재발화하면 안 된다.
  /// 화면 인스턴스가 아니라 기기 단위로 기억해야 단계별 달성률이 부풀지 않는다.
  static const String _completedLoggedKey = 'mission_completed_logged_v1';
  Set<String> _completedLogged = {};
  bool _completedLoggedReady = false;

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
    _logTrackView();
    _logNewlyCompleted();
  }

  void _logTrackView() {
    if (_viewLogged) return;
    _viewLogged = true;
    final missions = _track?.welcome?.missions ?? const <MissionItem>[];
    AnalyticsLogger.logEvent(
      AnalyticsEvents.missionTrackView,
      parameters: {
        AnalyticsEvents.paramEntry: widget.entry,
        AnalyticsEvents.paramDoneCount: missions.where((m) => m.isDone).length,
        AnalyticsEvents.paramTotalCount: missions.length,
      },
    );
  }

  /// 달성한 미션을 단계별로 남긴다.
  ///
  /// 수령(mission_reward_claim)과 반드시 분리해야 "깼는데 안 받아간 사용자"를
  /// 찾을 수 있다. 서버 status가 진실이므로 조회 응답 기준으로만 센다.
  Future<void> _logNewlyCompleted() async {
    final missions = _track?.welcome?.missions ?? const <MissionItem>[];
    if (missions.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (!_completedLoggedReady) {
      _completedLogged =
          (prefs.getStringList(_completedLoggedKey) ?? const <String>[]).toSet();
      _completedLoggedReady = true;
    }

    var changed = false;
    for (var i = 0; i < missions.length; i++) {
      final m = missions[i];
      if (!m.isDone || m.code.isEmpty) continue;
      if (!_completedLogged.add(m.code)) continue;
      changed = true;
      AnalyticsLogger.logEvent(
        AnalyticsEvents.missionCompleted,
        parameters: {
          AnalyticsEvents.paramMissionId: m.code,
          AnalyticsEvents.paramStepIndex: i,
        },
      );
    }
    if (changed) {
      await prefs.setStringList(_completedLoggedKey, _completedLogged.toList());
    }
  }

  /// 환영 미션 완주 리워드 수령. 성공 응답 뒤에만 연출을 재생한다.
  Future<void> _claimWelcome() async {
    final welcome = _track?.welcome;
    if (welcome == null || _claimingCode != null) return;
    final code = (welcome.reward?.code ?? '').trim();
    if (code.isEmpty) {
      _showClaimError();
      return;
    }

    // 달성(mission_completed)과 분리해 남긴다. 두 이벤트의 UU 차이가
    // "깼는데 안 받아간 사용자" — 리마인드 푸시의 타깃 모수다.
    AnalyticsLogger.logEvent(
      AnalyticsEvents.missionRewardClaim,
      parameters: {
        AnalyticsEvents.paramMissionId: code,
        AnalyticsEvents.paramRewardType:
            welcome.reward?.rewardText ?? 'random_coupon',
        AnalyticsEvents.paramDoneCount:
            welcome.missions.where((m) => m.isDone).length,
        AnalyticsEvents.paramTotalCount: welcome.missions.length,
      },
    );

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
          : '가입할 때 고른 식당 쿠폰 1장',
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
