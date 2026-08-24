import 'package:flutter/material.dart';

import '../config/analytics_events.dart';
import '../services/affiliate_service.dart';
import '../utils/analytics_logger.dart';
import 'onboarding_prefs.dart';
import 'onboarding_style.dart';
import 'widgets/animated_reveal_text.dart';
import 'widgets/restaurant_pick_list.dart';

// 좌상단 굵은 헤드라인 (메시지 컷 공용)
const TextStyle _headline = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 28,
  fontWeight: FontWeight.w800,
  height: 1.35,
  letterSpacing: -0.6,
  color: OnboardingStyle.ink,
);

// 메시지 컷: 굵은 글씨만 (캐릭터·부가설명 없음)
const List<String> _messageCuts = [
  '대학가 식당 혜택,\n여기 다 모았어요',
  '가입하면 바로 쓸\n첫 쿠폰을 드려요',
];

// 마지막 단계(식당 선택)를 포함한 전체 스텝 수
const int _totalSteps = 3;
const int _pickStep = 2;

/// 로그인 전 첫 실행 튜토리얼.
///
/// 좌상단 굵은 헤드라인 두 컷 → 실제 식당 DB에서 하나를 고르는 선택 단계 → 로그인.
/// 고른 식당은 저장되어 로그인 후 룰렛 지급으로 이어진다.
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

  // 식당 선택
  bool _loadingRestaurants = false;
  bool _restaurantsFailed = false;
  List<AffiliateRestaurantSummary> _restaurants = const [];
  int? _selectedRestaurant;

  @override
  void initState() {
    super.initState();
    _logStepView();
    if (_isPickStep && _restaurants.isEmpty) {
      _loadRestaurants();
    }
  }

  void _logStepView() {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingIntroView,
      parameters: {AnalyticsEvents.paramStep: _step + 1},
    );
  }

  bool get _isPickStep => _step == _pickStep;

  Future<void> _loadRestaurants() async {
    setState(() {
      _loadingRestaurants = true;
      _restaurantsFailed = false;
    });
    List<AffiliateRestaurantSummary> list = const [];
    try {
      // 로그인 전이므로 공개 목록 API 사용
      list = await AffiliateService.fetchRestaurants();
    } catch (_) {
      // 아래에서 실패 처리
    }
    if (!mounted) return;
    setState(() {
      _restaurants = list;
      _loadingRestaurants = false;
      _restaurantsFailed = list.isEmpty;
    });
  }

  void _handleTapAnywhere() {
    final title = _titleKey.currentState;
    if (title != null && !title.isCompleted) {
      title.completeNow();
    }
  }

  void _handlePrimary() {
    // 식당 선택 단계: 로그인으로
    if (_isPickStep) {
      final index = _selectedRestaurant;
      if (index == null) return;
      final selected = _restaurants[index];
      AnalyticsLogger.logEvent(
        AnalyticsEvents.onboardingRestaurantPick,
        parameters: {
          AnalyticsEvents.paramRestaurantId: selected.id,
          AnalyticsEvents.paramRestaurantName: selected.name,
        },
      );
      OnboardingPrefs.savePickedRestaurant(selected.id, selected.name);
      _finish(skipped: false);
      return;
    }

    // 메시지 컷: 타이핑 중이면 먼저 완성
    final title = _titleKey.currentState;
    if (title != null && !title.isCompleted) {
      title.completeNow();
      return;
    }
    setState(() {
      _step++;
    });
    _logStepView();
    if (_isPickStep && _restaurants.isEmpty) {
      _loadRestaurants();
    }
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isPickStep ? null : _handleTapAnywhere,
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
                Expanded(
                  child: _isPickStep ? _buildPickStep() : _buildMessageCut(),
                ),
                _buildDots(),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: OnboardingStyle.primaryButton(
                    enabled: !_isPickStep || _selectedRestaurant != null,
                  ),
                  onPressed: (_isPickStep && _selectedRestaurant == null)
                      ? null
                      : _handlePrimary,
                  child: Text(_isPickStep ? '로그인하고 쿠폰 받기' : '다음'),
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
      children: List.generate(_totalSteps, (i) {
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

  // ---------- 메시지 컷: 좌상단 굵은 글씨만 ----------

  Widget _buildMessageCut() {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: AnimatedRevealText(
          key: ValueKey(_step),
          text: _messageCuts[_step],
          textAlign: TextAlign.left,
          style: _headline,
        ),
      ),
    );
  }

  // ---------- 식당 선택 단계 ----------

  Widget _buildPickStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 16),
          child: Text('자주 가는 식당을\n골라 주세요', style: _headline),
        ),
        Expanded(
          child: RestaurantPickList(
            loading: _loadingRestaurants,
            failed: _restaurantsFailed,
            restaurants: _restaurants,
            selectedIndex: _selectedRestaurant,
            onSelect: (i) => setState(() => _selectedRestaurant = i),
            onRetry: _loadRestaurants,
          ),
        ),
      ],
    );
  }
}
