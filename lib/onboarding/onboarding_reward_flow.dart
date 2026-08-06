import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/analytics_events.dart';
import '../services/affiliate_service.dart';
import '../services/coupon_service.dart';
import '../utils/analytics_logger.dart';
import 'onboarding_prefs.dart';
import 'onboarding_style.dart';
import 'widgets/restaurant_pick_list.dart';
import 'widgets/roulette_wheel.dart';

enum _RewardStep { pick, spin, guide }

/// 보상 플로우: 식당 선택 → 룰렛 연출 → 다음 단계.
///
/// [preLogin]=false (가입 직후): 쿠폰은 가입 완료 시점에 signupComplete()로 이미
/// 발급되어 있고, 여기서는 보유 쿠폰을 조회해 룰렛 연출로 공개한 뒤 4컷 사용법으로 이어진다.
/// [preLogin]=true (프로토타입 화면 2·3, 로그인 전): 쿠폰 API를 쓸 수 없으므로
/// 연출만 하고 당첨 후 카카오 로그인으로 유도한다. 실제 발급은 가입 완료 시점의
/// signupComplete()(멱등)가 보장한다.
/// 선택한 식당은 이후 개인화(식당별 쿠폰 발급 연동 예정)를 위해 저장만 한다.
class OnboardingRewardFlow extends StatefulWidget {
  const OnboardingRewardFlow({
    super.key,
    required this.onFinished,
    this.preLogin = false,
  });

  final VoidCallback onFinished;

  /// 로그인 전 노출 여부 — 쿠폰 조회를 생략하고 당첨 후 로그인 유도로 마무리한다.
  final bool preLogin;

  @override
  State<OnboardingRewardFlow> createState() => _OnboardingRewardFlowState();
}

class _OnboardingRewardFlowState extends State<OnboardingRewardFlow>
    with SingleTickerProviderStateMixin {
  _RewardStep _step = _RewardStep.pick;

  // 식당 선택
  bool _isLoadingRestaurants = true;
  bool _restaurantLoadFailed = false;
  List<AffiliateRestaurantSummary> _restaurants = const [];
  int? _selectedIndex;

  // 룰렛
  late final AnimationController _spinController;
  late Animation<double> _spinAnimation;
  List<String> _wheelLabels = const [];
  String _pickedName = '';
  bool _spinDone = false;
  bool _couponFetchDone = false;
  UserCoupon? _revealedCoupon;
  bool _finished = false;

  // 인트로에서 이미 고른 식당 (있으면 선택 단계를 건너뛴다)
  int? _savedPickId;
  String? _savedPickName;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _spinAnimation = const AlwaysStoppedAnimation(0);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _savedPickId = await OnboardingPrefs.pickedRestaurantId();
    _savedPickName = await OnboardingPrefs.pickedRestaurantName();
    await _loadRestaurants();
    _maybeAutoSpinFromSaved();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _isLoadingRestaurants = true;
      _restaurantLoadFailed = false;
    });
    List<AffiliateRestaurantSummary> restaurants = const [];
    try {
      final active = await AffiliateService.fetchActiveRestaurants();
      restaurants = active.restaurants;
    } catch (_) {
      // active 조회 실패 시 전체 제휴 식당으로 폴백
    }
    if (restaurants.isEmpty) {
      try {
        restaurants = await AffiliateService.fetchRestaurants();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _restaurants = restaurants;
      _isLoadingRestaurants = false;
      _restaurantLoadFailed = restaurants.isEmpty;
    });
  }

  // ---------- 룰렛 ----------

  /// 인트로에서 저장한 식당이 있으면 선택 단계를 건너뛰고 바로 룰렛으로.
  void _maybeAutoSpinFromSaved() {
    if (!mounted) return;
    var name = _savedPickName ?? '';
    final id = _savedPickId;
    if (name.isEmpty && id != null) {
      for (final r in _restaurants) {
        if (r.id == id) {
          name = r.name;
          break;
        }
      }
    }
    if (name.isEmpty) return;
    // 선택 로깅은 인트로에서 이미 했으므로 생략
    _beginSpin(name: name, id: id, logPick: false);
  }

  void _startSpin() {
    final selected = _restaurants[_selectedIndex!];
    _beginSpin(name: selected.name, id: selected.id, logPick: true);
  }

  void _beginSpin({
    required String name,
    int? id,
    required bool logPick,
  }) {
    if (logPick) {
      AnalyticsLogger.logEvent(
        AnalyticsEvents.onboardingRestaurantPick,
        parameters: {
          AnalyticsEvents.paramRestaurantId: id ?? 0,
          AnalyticsEvents.paramRestaurantName: name,
        },
      );
      OnboardingPrefs.savePickedRestaurant(id ?? 0, name);
    }

    // 휠에는 고른 식당 + 다른 식당 최대 7곳
    final others = _restaurants
        .where((r) => r.name != name)
        .map((r) => r.name)
        .take(7)
        .toList();
    final labels = [name, ...others];
    // 세그먼트가 2개는 돼야 룰렛처럼 보인다.
    if (labels.length < 2) labels.add('우주라이크');

    final targetRotation =
        2 * math.pi * 4 + RouletteWheel.rotationForIndex(0, labels.length);
    _spinAnimation = Tween<double>(begin: 0, end: targetRotation).animate(
      CurvedAnimation(parent: _spinController, curve: Curves.easeOutQuart),
    );

    setState(() {
      _wheelLabels = labels;
      _pickedName = name;
      _step = _RewardStep.spin;
      _spinDone = false;
      _couponFetchDone = widget.preLogin;
    });

    _spinController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _spinDone = true);
      _maybeLogReveal();
    });
    // 로그인 전에는 쿠폰 API를 쓸 수 없으므로 연출만 진행한다.
    if (!widget.preLogin) {
      _fetchIssuedCoupon();
    }
  }

  Future<void> _fetchIssuedCoupon() async {
    UserCoupon? coupon;
    try {
      var coupons =
          await CouponService.fetchMyCoupons(status: CouponStatus.issued);
      coupon = _pickRevealCoupon(coupons);
      // 아직 발급 전이면 여기서 실제 발급을 보장한다.
      // signupComplete는 issue_key Unique로 멱등이라 중복 발급되지 않는다.
      if (coupon == null) {
        await CouponService.signupComplete();
        coupons =
            await CouponService.fetchMyCoupons(status: CouponStatus.issued);
        coupon = _pickRevealCoupon(coupons);
      }
    } catch (_) {
      // 조회/발급 실패해도 연출은 계속 진행 (쿠폰함에서 다시 확인 가능)
    }
    if (!mounted) return;
    setState(() {
      _revealedCoupon = coupon;
      _couponFetchDone = true;
    });
    _maybeLogReveal();
  }

  /// 가입 축하 쿠폰 우선, 없으면 가장 최근 발급 쿠폰
  UserCoupon? _pickRevealCoupon(List<UserCoupon> coupons) {
    if (coupons.isEmpty) return null;
    final sorted = [...coupons]..sort((a, b) {
        final at = a.issuedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.issuedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
    for (final c in sorted) {
      if (c.couponIssueSource == 'SIGNUP_WELCOME') return c;
    }
    return sorted.first;
  }

  bool _revealLogged = false;

  void _maybeLogReveal() {
    if (_revealLogged || !_spinDone || !_couponFetchDone) return;
    _revealLogged = true;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingCouponReveal,
      parameters: {
        AnalyticsEvents.paramCouponCount: _revealedCoupon != null ? 1 : 0,
        if (_revealedCoupon != null)
          AnalyticsEvents.paramCouponCode: _revealedCoupon!.code,
      },
    );
  }

  bool get _revealReady => _spinDone && _couponFetchDone;

  // ---------- 완료 ----------

  void _goGuide() {
    AnalyticsLogger.logEvent(AnalyticsEvents.onboardingGuideView);
    setState(() => _step = _RewardStep.guide);
  }

  Future<void> _finish({required bool skipped}) async {
    if (_finished) return;
    _finished = true;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingComplete,
      parameters: {AnalyticsEvents.paramSkipped: skipped},
    );
    await OnboardingPrefs.markRewardDone();
    if (!mounted) return;
    widget.onFinished();
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_step) {
            _RewardStep.pick => _buildPickStep(),
            _RewardStep.spin => _buildSpinStep(),
            _RewardStep.guide => _buildGuideStep(),
          },
        ),
      ),
    );
  }

  // ---------- STEP 1: 식당 선택 ----------

  Widget _buildPickStep() {
    return Padding(
      key: const ValueKey('pick'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('자주 가는 곳을\n골라 주세요', style: OnboardingStyle.title),
          const SizedBox(height: 8),
          const Text('고르시면 첫 쿠폰을 바로 드려요', style: OnboardingStyle.subtitle),
          const SizedBox(height: 20),
          Expanded(child: _buildRestaurantList()),
          const SizedBox(height: 12),
          ElevatedButton(
            style: OnboardingStyle.primaryButton(enabled: _selectedIndex != null),
            onPressed: _selectedIndex == null ? null : _startSpin,
            child: const Text('쿠폰 받으러 가기'),
          ),
          Center(
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
              child: const Text('나중에 볼게요'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantList() {
    return RestaurantPickList(
      loading: _isLoadingRestaurants,
      failed: _restaurantLoadFailed,
      restaurants: _restaurants,
      selectedIndex: _selectedIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      onRetry: _loadRestaurants,
    );
  }

  // ---------- STEP 2: 룰렛 ----------

  Widget _buildSpinStep() {
    return Padding(
      key: const ValueKey('spin'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            _revealReady
                ? (widget.preLogin ? '당첨을 축하해요! 🎉' : '축하해요! 🎉')
                : '어떤 쿠폰이 나올까요?',
            style: OnboardingStyle.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _revealReady
                ? (widget.preLogin ? '로그인하면 지갑에 담아드려요' : '첫 쿠폰이 도착했어요')
                : '두구두구…',
            style: OnboardingStyle.subtitle,
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _spinController,
            builder: (context, _) => RouletteWheel(
              labels: _wheelLabels,
              rotation: _spinAnimation.value,
            ),
          ),
          const SizedBox(height: 24),
          AnimatedScale(
            scale: _revealReady ? 1 : 0.8,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: _revealReady ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: _buildRevealCard(),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            style: OnboardingStyle.primaryButton(enabled: _revealReady),
            // 로그인 전에는 당첨 후 바로 카카오 로그인으로 유도 (프로토타입 화면 3)
            onPressed: !_revealReady
                ? null
                : widget.preLogin
                    ? () => _finish(skipped: false)
                    : _goGuide,
            child: Text(widget.preLogin ? '카카오 로그인하고 쿠폰 받기' : '내 쿠폰에 담기'),
          ),
        ],
      ),
    );
  }

  Widget _buildRevealCard() {
    final coupon = _revealedCoupon;
    final title = coupon?.benefit?.resolvedTitle ??
        (widget.preLogin ? '첫 쿠폰 당첨!' : '첫 쿠폰을 준비하고 있어요');
    final restaurantName = coupon?.benefit?.restaurantNameText ??
        (widget.preLogin && _pickedName.isNotEmpty ? _pickedName : null);
    final expiresAt = coupon?.expiresAt;
    String? ddayText;
    if (expiresAt != null) {
      final days = expiresAt.difference(DateTime.now()).inDays;
      ddayText = days <= 0 ? '오늘까지!' : 'D-$days · 잊기 전에 쓰기';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: OnboardingStyle.primary.withOpacity(0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          if (restaurantName != null)
            Text(restaurantName, style: OnboardingStyle.caption),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: OnboardingStyle.primary,
              height: 1.4,
            ),
          ),
          if (coupon == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.preLogin ? '로그인하면 바로 쓸 수 있어요' : '곧 보유 쿠폰함에서 확인할 수 있어요',
                style: OnboardingStyle.caption,
              ),
            ),
          if (ddayText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  ddayText,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: OnboardingStyle.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- STEP 3: 4컷 사용법 ----------

  static const List<({String emoji, String title, String sub})> _guideCuts = [
    (emoji: '🏃', title: '식당에 가서', sub: '쿠폰 있는 가게로'),
    (emoji: '📱', title: '우즈라이크 켜고', sub: '보유 쿠폰에서 꺼내요'),
    (emoji: '🙌', title: '직원분께 보여주면', sub: '말은 안 해도 돼요'),
    (emoji: '😋', title: '할인 끝!', sub: '맛있게 드세요'),
  ];

  Widget _buildGuideStep() {
    return Padding(
      key: const ValueKey('guide'),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('쓰는 법,\n딱 네 걸음이에요', style: OnboardingStyle.title),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(_guideCuts.length, (i) {
                final cut = _guideCuts[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: OnboardingStyle.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: OnboardingStyle.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(cut.emoji, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 8),
                      Text(
                        cut.title,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: OnboardingStyle.ink,
                        ),
                      ),
                      Text(cut.sub, style: OnboardingStyle.caption),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: OnboardingStyle.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '따로 말하지 않아도 괜찮아요.\n화면만 보여주면 끝!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: OnboardingStyle.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: OnboardingStyle.primaryButton(),
            onPressed: () => _finish(skipped: false),
            child: const Text('우즈라이크 시작하기'),
          ),
        ],
      ),
    );
  }
}
