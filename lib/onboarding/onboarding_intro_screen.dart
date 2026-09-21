import 'package:flutter/material.dart';

import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';
import 'onboarding_prefs.dart';
import 'onboarding_style.dart';
import 'widgets/animated_reveal_text.dart';
import '../widgets/coupon_ticket_card.dart';

// 좌상단 굵은 헤드라인 (메시지 컷 공용)
const TextStyle _headline = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 28,
  fontWeight: FontWeight.w800,
  height: 1.35,
  letterSpacing: -0.6,
  color: OnboardingStyle.ink,
);

/// 인트로 카피 종류.
/// [newUser]: 로그인 전 첫 실행(프로토타입 화면 0·1) — 앱을 처음 보는 사람용.
/// [renewal]: 이미 쓰던 기존 계정이 개편 후 다시 로그인했을 때 — "처음 오셨네요"가
/// 아니라 "그동안 앱이 달라졌어요"로 톤을 바꾼다.
enum OnboardingIntroVariant { newUser, renewal }

// 프로토타입 화면 0·1 카피
const List<({String title, String subtitle, String button})>
    _newUserMessageCuts = [
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

// 기존 계정이 개편 후 다시 로그인했을 때 보여줄 카피
const List<({String title, String subtitle, String button})>
    _renewalMessageCuts = [
  (
    title: '우주라이크가\n새롭게 바뀌었어요',
    subtitle: '대학가 인근 제휴 식당의 쿠폰과 스탬프 등\n모든 혜택을 한 곳에 모았어요.',
    button: '둘러보기',
  ),
  (
    title: '지금 식당을 고르면,\n바로 쓸 쿠폰을 드려요',
    subtitle: '원하는 식당 하나를 고르면\n바로 사용 가능한 쿠폰을 드려요!',
    button: '쿠폰 즉시 발급 받기',
  ),
];

/// 첫 실행 인트로 (프로토타입 화면 0·1).
///
/// 앱 소개 두 컷만 보여주고, 이후 식당 선택→룰렛(OnboardingRewardFlow)으로 이어진다.
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({
    super.key,
    required this.onFinished,
    this.variant = OnboardingIntroVariant.newUser,
  });

  final VoidCallback onFinished;
  final OnboardingIntroVariant variant;

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  final GlobalKey<AnimatedRevealTextState> _titleKey =
      GlobalKey<AnimatedRevealTextState>();
  int _step = 0;
  bool _finished = false;

  /// 온보딩~첫 쿠폰 구간을 잇는 조인 키. 이 화면이 구간의 시작점이다.
  String? _firstpickSessionId;

  List<({String title, String subtitle, String button})> get _messageCuts =>
      widget.variant == OnboardingIntroVariant.renewal
          ? _renewalMessageCuts
          : _newUserMessageCuts;

  @override
  void initState() {
    super.initState();
    OnboardingPrefs.firstpickSessionId().then((id) {
      if (mounted) setState(() => _firstpickSessionId = id);
    });
    _logStepView();
  }

  Map<String, Object?> get _sessionParams => {
        if (_firstpickSessionId != null)
          AnalyticsEvents.paramFirstpickSessionId: _firstpickSessionId,
      };

  void _logStepView() {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingIntroView,
      parameters: {
        ..._sessionParams,
        AnalyticsEvents.paramStep: _step + 1,
      },
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
        ..._sessionParams,
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

  // 화면 1: 쿠폰 히어로 — 지갑·식당 상세와 같은 공용 쿠폰 티켓 카드를 그대로 보여준다.
  Widget _buildCouponHero() {
    return Transform.rotate(
      angle: -1.5 * 3.141592 / 180,
      child: SizedBox(
        width: 320,
        child: CouponTicketCard(
          iconPath: 'assets/icons/category/korean.svg',
          storeLabel: '정든밤',
          title: '2,000원 할인',
          subtitle: '1만원 이상 주문 시 사용 가능',
          expiryText: '받은 날부터 7일간',
          onAction: () {},
          margin: EdgeInsets.zero,
          borderColor: const Color(0xFFE1E5EA),
        ),
      ),
    );
  }
}
