import 'package:flutter/material.dart';

import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';
import 'onboarding_style.dart';
import 'widgets/animated_reveal_text.dart';

// 좌상단 굵은 헤드라인 (메시지 컷 공용)
const TextStyle _headline = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 28,
  fontWeight: FontWeight.w800,
  height: 1.35,
  letterSpacing: -0.6,
  color: OnboardingStyle.ink,
);

// 프로토타입 화면 0·1 카피
const List<({String title, String subtitle, String button})> _messageCuts = [
  (
    title: '대학가 맛집,\n우주라이크와 함께 하세요!',
    subtitle: '대학가 인근 제휴 식당의 쿠폰과 스탬프 등\n모든 혜택을 한 곳에 모았어요.',
    button: '시작하기',
  ),
  (
    title: '지금 시작하면,\n바로 쓸 쿠폰을 드려요',
    subtitle: '원하는 식당 하나를 고르면\n바로 사용 가능한 쿠폰을 드려요!',
    button: '쿠폰 즉시 발급 받기',
  ),
];

/// 로그인 전 첫 실행 인트로 (프로토타입 화면 0·1).
///
/// 앱 소개 두 컷만 보여주고, 이후 식당 선택→룰렛(OnboardingRewardFlow)으로 이어진다.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  final GlobalKey<AnimatedRevealTextState> _titleKey =
      GlobalKey<AnimatedRevealTextState>();
  int _step = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _logStepView();
  }

  void _logStepView() {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingIntroView,
      parameters: {AnalyticsEvents.paramStep: _step + 1},
    );
  }

  void _handleTapAnywhere() {
    final title = _titleKey.currentState;
    if (title != null && !title.isCompleted) {
      title.completeNow();
    }
  }

  void _handlePrimary() {
    // 타이핑 중이면 먼저 완성
    final title = _titleKey.currentState;
    if (title != null && !title.isCompleted) {
      title.completeNow();
      return;
    }
    if (_step >= _messageCuts.length - 1) {
      _finish(skipped: false);
      return;
    }
    setState(() {
      _step++;
    });
    _logStepView();
  }

  void _finish({required bool skipped}) {
    if (_finished) return;
    _finished = true;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingIntroComplete,
      parameters: {
        AnalyticsEvents.paramSkipped: skipped,
        AnalyticsEvents.paramStep: _step + 1,
      },
    );
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final cut = _messageCuts[_step];
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTapAnywhere,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _finish(skipped: true),
                    style: TextButton.styleFrom(
                      foregroundColor: OnboardingStyle.muted,
                      textStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    child: const Text('건너뛰기'),
                  ),
                ),
                Expanded(child: _buildMessageCut(cut)),
                _buildDots(),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: OnboardingStyle.primaryButton(),
                  onPressed: _handlePrimary,
                  child: Text(cut.button),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_messageCuts.length, (i) {
        final active = i == _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? OnboardingStyle.primary : OnboardingStyle.line,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }

  // ---------- 메시지 컷: 헤드라인 + 서브카피 + 히어로 비주얼 ----------

  Widget _buildMessageCut(
      ({String title, String subtitle, String button}) cut) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: AnimatedRevealText(
            key: ValueKey(_step),
            text: cut.title,
            textAlign: TextAlign.left,
            style: _headline,
          ),
        ),
        const SizedBox(height: 12),
        Text(cut.subtitle, style: OnboardingStyle.subtitle),
        Expanded(
          child: Center(
            child: _step == 0 ? _buildPlateHero() : _buildCouponHero(),
          ),
        ),
      ],
    );
  }

  // 화면 0: 3D 접시 아이콘
  Widget _buildPlateHero() {
    return Image.asset(
      'assets/images/onboarding_hero_plate.png',
      width: 170,
      fit: BoxFit.contain,
    );
  }

  // 화면 1: 쿠폰 카드 목업 (프로토타입 .rcpn.cpnhero)
  Widget _buildCouponHero() {
    return Transform.rotate(
      angle: -1.5 * 3.141592 / 180,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        decoration: BoxDecoration(
          color: const Color(0xFF192132),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x6B192132),
              blurRadius: 38,
              offset: Offset(0, 22),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // Center가 느슨한 제약을 주므로 min이 없으면 카드가 세로 전체로 늘어난다.
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '한끼갈비',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFCBD5FF),
              ),
            ),
            SizedBox(height: 6),
            Text(
              '2,000원 할인',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '1만원 이상 주문 시 사용 가능',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFFD1D6FF),
              ),
            ),
            SizedBox(height: 11),
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 13, color: Color(0xFFE1B53E)),
                SizedBox(width: 5),
                Text(
                  '받은 날부터 7일간 사용 가능',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE1B53E),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
