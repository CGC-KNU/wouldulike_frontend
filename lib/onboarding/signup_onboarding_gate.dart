import 'package:flutter/material.dart';

import '../main2.dart';
import '../profile_setup_screen.dart';
import 'onboarding_prefs.dart';
import 'onboarding_reward_flow.dart';
import 'onboarding_style.dart';

/// 로그인 직후 신규 가입자의 홈 직행을 막는 게이트.
///
/// 필수 프로필 설정 → 보상 온보딩(식당 선택→룰렛→사용법) → 메인 순서로 통과시킨다.
/// 기존 사용자(프로필 완성 + 온보딩 완료)는 이 위젯이 만들어지지 않는다.
class SignupOnboardingGate extends StatefulWidget {
  const SignupOnboardingGate({
    super.key,
    required this.profileIncomplete,
    this.initialProfile,
  });

  final bool profileIncomplete;
  final Map<String, dynamic>? initialProfile;

  @override
  State<SignupOnboardingGate> createState() => _SignupOnboardingGateState();
}

class _SignupOnboardingGateState extends State<SignupOnboardingGate> {
  late bool _needsProfile = widget.profileIncomplete;

  /// null = 플래그 확인 중
  bool? _showReward;

  @override
  void initState() {
    super.initState();
    if (!_needsProfile) {
      _checkRewardFlag();
    }
  }

  Future<void> _checkRewardFlag() async {
    final show = await OnboardingPrefs.shouldShowRewardFlow();
    if (!mounted) return;
    setState(() => _showReward = show);
  }

  void _handleProfileCompleted() {
    if (!mounted) return;
    setState(() => _needsProfile = false);
    _checkRewardFlag();
  }

  @override
  Widget build(BuildContext context) {
    if (_needsProfile) {
      return ProfileSetupScreen(
        initialProfile: widget.initialProfile,
        isRequiredFlow: true,
        onCompleted: _handleProfileCompleted,
      );
    }
    if (_showReward == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: OnboardingStyle.primary),
        ),
      );
    }
    if (_showReward!) {
      return OnboardingRewardFlow(
        onFinished: () {
          if (mounted) setState(() => _showReward = false);
        },
      );
    }
    return const MainAppScreen();
  }
}
