import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/analytics_events.dart';
import '../services/affiliate_service.dart';
import '../services/coupon_service.dart';
import '../utils/analytics_logger.dart';
import '../widgets/category_strip.dart';
import 'onboarding_prefs.dart';
import 'onboarding_style.dart';
import 'widgets/restaurant_pick_list.dart';
import 'widgets/roulette_wheel.dart';
import '../widgets/coupon_ticket_card.dart';

enum _RewardStep { pick, spin, guide }

/// 보상 플로우: 식당 선택 → 룰렛 연출 → 다음 단계.
///
/// 식당은 매번 이 화면의 선택 단계에서 직접 고른다 — 이전에 저장된 값이
/// 있어도 자동으로 이어받아 선택 단계를 건너뛰지 않는다. 그래야 룰렛에
/// 걸리는 식당과 사용자가 실제로 방금 고른 식당이 항상 일치한다.
///
/// 여기서 고른 식당이 곧 "가입 시 고른 식당"이다 — 첫 쿠폰뿐 아니라 이후 웰컴
/// 미션(쿠폰 사용·스탬프 2회)도 이 식당을 기준으로 진행된다. 그래서 실제 발급
/// (signupComplete(restaurantId: ...))은 식당이 정해진 뒤인 여기서만 일어난다.
/// [preLogin]=false (가입 직후): 이 화면 진입 시 [_fetchIssuedCoupon]이 먼저
/// 발급 여부를 조회하고, 아직이면 그 자리에서 restaurant_id를 실어 발급한 뒤
/// 룰렛 연출로 공개하고 4컷 사용법으로 이어진다.
/// [preLogin]=true (프로토타입 화면 2·3, 로그인 전): 쿠폰 API를 쓸 수 없으므로
/// 연출만 하고 당첨 후 카카오 로그인으로 유도한다.
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

  /// 온보딩~첫 쿠폰 구간을 잇는 조인 키. 이 화면의 모든 이벤트에 공통으로 싣는다.
  String? _firstpickSessionId;

  /// 룰렛 시도 횟수 (1부터). 재시도 연출이 생겨도 그대로 쓸 수 있게 센다.
  int _spinAttempt = 0;

  // 식당 선택
  bool _isLoadingRestaurants = true;
  bool _restaurantLoadFailed = false;
  List<AffiliateRestaurantSummary> _restaurants = const [];

  /// 필터링된 목록(_visibleRestaurants) 기준 인덱스. 필터가 바뀌면 초기화한다.
  int? _selectedIndex;
  String _categoryKey = 'ALL';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 룰렛
  late final AnimationController _spinController;
  late Animation<double> _spinAnimation;
  List<String> _wheelLabels = const [];
  String _pickedName = '';
  int? _pickedId;
  bool _spinDone = false;
  bool _couponFetchDone = false;
  UserCoupon? _revealedCoupon;

  /// signupComplete()가 HTTP 201을 줬는데도 coupon_code가 비어 온 경우.
  /// 혜택이 비활성화된 식당을 골랐을 때 드물게 발생한다 — "발급 준비 중"이
  /// 아니라 실패로 간주해 재시도를 유도한다.
  bool _issuanceFailed = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    OnboardingPrefs.firstpickSessionId().then((id) {
      if (mounted) setState(() => _firstpickSessionId = id);
    });
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _spinAnimation = const AlwaysStoppedAnimation(0);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadRestaurants();
  }

  @override
  void dispose() {
    _spinController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 카테고리·검색어로 걸러낸 목록. 선택 인덱스는 이 목록 기준이다.
  List<AffiliateRestaurantSummary> get _visibleRestaurants {
    final query = _searchQuery.trim().toLowerCase();
    return _restaurants.where((r) {
      if (_categoryKey != 'ALL' &&
          normalizeCategoryKey(r.category) != _categoryKey) {
        return false;
      }
      if (query.isEmpty) return true;
      return r.name.toLowerCase().contains(query) ||
          r.category.toLowerCase().contains(query) ||
          r.zone.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _isLoadingRestaurants = true;
      _restaurantLoadFailed = false;
    });
    List<AffiliateRestaurantSummary> restaurants = const [];
    try {
      // 웰컴 보상 쿠폰이 설정된 식당만 걸러진 전용 목록을 우선 쓴다 — 여기서
      // 고르면 이후 웰컴 미션 보상이 확실히 나간다.
      restaurants = await AffiliateService.fetchSignupRestaurants();
    } catch (_) {
      // 신규 엔드포인트 실패 시 기존 목록으로 폴백
    }
    if (restaurants.isEmpty) {
      try {
        final active = await AffiliateService.fetchActiveRestaurants();
        restaurants = active.restaurants;
      } catch (_) {
        // active 조회 실패 시 전체 제휴 식당으로 폴백
      }
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

  /// 온보딩 이벤트 공통 파라미터. 세션 키가 아직 로드되지 않았으면 생략한다.
  Map<String, Object?> get _sessionParams => {
        if (_firstpickSessionId != null)
          AnalyticsEvents.paramFirstpickSessionId: _firstpickSessionId,
      };

  void _startSpin() {
    final selected = _visibleRestaurants[_selectedIndex!];
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
          ..._sessionParams,
          AnalyticsEvents.paramRestaurantId: id ?? 0,
          AnalyticsEvents.paramRestaurantName: name,
        },
      );
      OnboardingPrefs.savePickedRestaurant(id ?? 0, name);
    }

    // 휠에는 꽝·마일리지·쿠폰·한 번 더만 올리고, 당첨 칸(0번)은 항상 쿠폰이다.
    const labels = RouletteWheel.prizeLabels;

    final targetRotation =
        2 * math.pi * 4 + RouletteWheel.rotationForIndex(0, labels.length);
    _spinAnimation = Tween<double>(begin: 0, end: targetRotation).animate(
      CurvedAnimation(parent: _spinController, curve: Curves.easeOutQuart),
    );

    _spinAttempt += 1;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.rouletteSpin,
      parameters: {
        ..._sessionParams,
        AnalyticsEvents.paramRestaurantId: id ?? 0,
        AnalyticsEvents.paramAttemptNo: _spinAttempt,
      },
    );

    setState(() {
      _wheelLabels = labels;
      _pickedName = name;
      _pickedId = id;
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
    var issuanceFailed = false;
    try {
      var coupons =
          await CouponService.fetchMyCoupons(status: CouponStatus.issued);
      // 발급 여부는 "가입 축하 쿠폰(SIGNUP_WELCOME)을 이미 받았는가"로만
      // 판단한다. 다른 이유로 발급된 쿠폰(스탬프 리워드, 마일리지 응모 당첨
      // 등)이 있다고 해서 이번 온보딩에서 새로 발급을 건너뛰면 안 된다 —
      // 특히 이미 여러 쿠폰을 가진 기존 계정은 "가장 최근 발급 쿠폰"이
      // 방금 고른 식당과 무관한 엉뚱한 쿠폰이라, 아예 발급이 안 된 것처럼
      // 보인다.
      coupon = _findWelcomeCoupon(coupons);
      // 아직 가입 축하 쿠폰을 못 받았으면 여기서 실제 발급을 보장한다. 이
      // 시점엔 식당이 이미 정해져 있으므로(방금 선택) restaurant_id를 실어
      // 보낸다 — 서버가 필수로 요구한다. signupComplete는 issue_key
      // Unique로 멱등이라 중복 발급되지 않는다.
      if (coupon == null) {
        final result =
            await CouponService.signupComplete(restaurantId: _pickedId);
        // 그 식당의 혜택이 비활성 상태면 서버가 HTTP 201을 주면서도
        // coupon_code를 비워 보낸다 — 이건 "아직 준비 중"이 아니라 발급 실패다.
        final issuedCode = result['coupon_code']?.toString() ?? '';
        if (issuedCode.isEmpty) {
          issuanceFailed = true;
        } else {
          coupons =
              await CouponService.fetchMyCoupons(status: CouponStatus.issued);
          coupon = _findWelcomeCoupon(coupons) ?? _pickRevealCoupon(coupons);
        }
      }
    } catch (_) {
      // 네트워크 오류·서버 500 등으로 조회/발급 자체가 실패한 경우
    }
    // 예외가 났든(위 catch), 발급 직후 재조회가 아직 반영 전이든, 결국 보여줄
    // 쿠폰이 없다면 실패로 표시한다. 그냥 넘어가면 화면엔 "쿠폰을 준비하고
    // 있어요" 플레이스홀더만 뜨고 버튼은 눌리는 상태라, 실제로는 발급되지
    // 않았는데 튜토리얼이 정상 완료된 것처럼 지나가 버린다.
    if (coupon == null) {
      issuanceFailed = true;
    }
    if (!mounted) return;
    setState(() {
      _revealedCoupon = coupon;
      _couponFetchDone = true;
      _issuanceFailed = issuanceFailed;
    });
    _maybeLogReveal();
  }

  /// 이미 받은 가입 축하 쿠폰이 있으면 반환 (없으면 null → 새로 발급해야 함)
  UserCoupon? _findWelcomeCoupon(List<UserCoupon> coupons) {
    final sorted = [...coupons]..sort((a, b) {
        final at = a.issuedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.issuedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
    for (final c in sorted) {
      if (c.couponIssueSource == 'SIGNUP_WELCOME') return c;
    }
    return null;
  }

  /// 방금 발급을 시도했는데도 응답 목록에서 못 찾았을 때의 최후 폴백 —
  /// 가장 최근 발급 쿠폰이라도 보여준다 (발급 자체는 성공했을 가능성이 큼).
  UserCoupon? _pickRevealCoupon(List<UserCoupon> coupons) {
    if (coupons.isEmpty) return null;
    final sorted = [...coupons]..sort((a, b) {
        final at = a.issuedAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.issuedAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
    return sorted.first;
  }

  bool _revealLogged = false;

  void _maybeLogReveal() {
    if (_revealLogged || !_spinDone || !_couponFetchDone) return;
    _revealLogged = true;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingCouponReveal,
      parameters: {
        ..._sessionParams,
        AnalyticsEvents.paramCouponCount: _revealedCoupon != null ? 1 : 0,
        if (_revealedCoupon != null)
          AnalyticsEvents.paramCouponCode: _revealedCoupon!.code,
        if (_issuanceFailed) 'issuance_failed': true,
      },
    );
  }

  bool get _revealReady => _spinDone && _couponFetchDone;

  // ---------- 완료 ----------

  void _goGuide() {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingGuideView,
      parameters: _sessionParams,
    );
    setState(() => _step = _RewardStep.guide);
  }

  /// 로그인 전 당첨 화면에서 "카카오 로그인하고 쿠폰 받기" 탭.
  /// 로그인 게이트로 넘어가기 직전 지점이라, 여기서 이탈하면 첫 쿠폰을 못 받는다.
  void _claimViaLogin() {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.rouletteClaimClick,
      parameters: {
        ..._sessionParams,
        AnalyticsEvents.paramAuthState: 'guest',
        if (_revealedCoupon != null)
          AnalyticsEvents.paramCouponCode: _revealedCoupon!.code,
      },
    );
    _finish(skipped: false);
  }

  Future<void> _finish({required bool skipped}) async {
    if (_finished) return;
    _finished = true;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.onboardingComplete,
      parameters: {
        ..._sessionParams,
        AnalyticsEvents.paramSkipped: skipped,
      },
    );
    await OnboardingPrefs.markRewardDone();
    if (!widget.preLogin) {
      // 로그인 후 인스턴스가 이 온보딩 세션의 최종 종료 지점이다. 로그인 전
      // 인스턴스는 여기서 지우면 안 된다 — 방금 고른 식당을 로그인 후
      // 인스턴스가 이어받아야 하기 때문 (클래스 docstring 참고).
      await OnboardingPrefs.clearPickedRestaurant();
    }
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
          const Text('어디서 쓸까요?', style: OnboardingStyle.title),
          const SizedBox(height: 8),
          const Text('원하는 식당을 선택해 주세요.', style: OnboardingStyle.subtitle),
          const SizedBox(height: 16),
          _buildSearchBar(),
          const SizedBox(height: 4),
          // 식당 탭과 같은 카테고리 아이콘 줄 (widgets/category_strip.dart 공용)
          CategoryStrip(
            selected: _categoryKey,
            onSelect: (key) => setState(() {
              _categoryKey = key;
              _selectedIndex = null; // 목록이 바뀌면 인덱스가 어긋난다
            }),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildRestaurantList()),
          const SizedBox(height: 12),
          ElevatedButton(
            style:
                OnboardingStyle.primaryButton(enabled: _selectedIndex != null),
            onPressed: _selectedIndex == null ? null : _startSpin,
            child: const Text('이 식당으로 뽑기'),
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
              child: const Text('건너뛰기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      decoration: ShapeDecoration(
        color: const Color(0xFFF4F5F7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: Color(0xFF39393E),
          fontSize: 14,
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w600,
        ),
        onChanged: (value) => setState(() {
          _searchQuery = value;
          _selectedIndex = null;
        }),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          hintText: '식당 검색',
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 14.5,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
          ),
          prefixIcon:
              const Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: const Color(0xFF6B7280),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _selectedIndex = null;
                    });
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildRestaurantList() {
    final visible = _visibleRestaurants;
    // 불러오기는 됐는데 필터 결과만 빈 경우 — '다시 시도'가 아니라 필터 안내를 보여준다.
    if (!_isLoadingRestaurants &&
        !_restaurantLoadFailed &&
        visible.isEmpty &&
        _restaurants.isNotEmpty) {
      return const Center(
        child: Text('조건에 맞는 식당이 없어요', style: OnboardingStyle.subtitle),
      );
    }
    return RestaurantPickList(
      loading: _isLoadingRestaurants,
      failed: _restaurantLoadFailed,
      restaurants: visible,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            _revealReady
                ? (widget.preLogin ? '당첨을 축하해요! 🎉' : '축하해요! 🎉')
                : '어떤 쿠폰이 나올까요?',
            style: OnboardingStyle.title,
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 6),
          Text(
            _revealReady
                ? (widget.preLogin ? '로그인하면 지갑에 담아드려요' : '첫 쿠폰이 도착했어요')
                : '두구두구…',
            style: OnboardingStyle.subtitle,
            textAlign: TextAlign.left,
          ),
          // 남는 세로 공간만큼 키우되 가로 폭은 넘지 않게 — 작은 화면에서도 안 깨진다.
          Expanded(
            // Center로 감싸면 느슨한 제약이 내려가 FittedBox가 확대를 안 한다.
            child: FittedBox(
              fit: BoxFit.contain,
              child: AnimatedBuilder(
                animation: _spinController,
                builder: (context, _) => RouletteWheel(
                  labels: _wheelLabels,
                  rotation: _spinAnimation.value,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
          // 로그인 전에는 당첨 후 바로 카카오 로그인으로 유도 (프로토타입 화면 3).
          // 카카오 버튼은 브랜드 규격대로 노란 배경 + 좌측 카카오 아이콘.
          widget.preLogin
              ? ElevatedButton(
                  style: OnboardingStyle.kakaoButton(),
                  onPressed: _revealReady ? _claimViaLogin : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/kakaotalk.svg',
                        width: 22,
                        height: 20,
                      ),
                      const SizedBox(width: 8),
                      // 좁은 화면에서 버튼 문구가 넘치지 않게 줄여 맞춘다.
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('카카오 로그인하고 쿠폰 받기'),
                        ),
                      ),
                    ],
                  ),
                )
              : ElevatedButton(
                  style: OnboardingStyle.primaryButton(enabled: _revealReady),
                  onPressed: _revealReady ? _goGuide : null,
                  child: const Text('내 쿠폰에 담기'),
                ),
        ],
      ),
    );
  }

  /// signupComplete()가 coupon_code 없이 성공(201)한 경우의 재시도.
  Future<void> _retryIssuance() async {
    setState(() => _couponFetchDone = false);
    await _fetchIssuedCoupon();
  }

  /// 당첨 결과는 쿠폰함·식당 상세와 같은 티켓 카드로 보여준다.
  Widget _buildRevealCard() {
    if (_issuanceFailed) {
      return CouponTicketCard(
        iconPath: 'assets/icons/category/all.svg',
        storeLabel: _pickedName.isNotEmpty ? _pickedName : '우주라이크',
        title: '쿠폰 발급에 문제가 생겼어요',
        subtitle: '잠시 후 다시 시도하거나 고객센터로 문의해 주세요',
        actionLabel: '다시 시도',
        borderColor: const Color(0xFFE1E5EA),
        onAction: _retryIssuance,
        margin: EdgeInsets.zero,
      );
    }

    final coupon = _revealedCoupon;
    final benefit = coupon?.benefit;
    final expiresAt = coupon?.expiresAt;
    String? expiryText;
    var expiryUrgent = false;
    if (expiresAt != null) {
      final days = expiresAt.difference(DateTime.now()).inDays;
      expiryUrgent = days <= 1;
      expiryText = days <= 0 ? '오늘까지' : 'D-$days · 잊기 전에 쓰기';
    }

    return CouponTicketCard(
      iconPath: 'assets/icons/category/all.svg',
      storeLabel: benefit?.restaurantNameText ??
          (_pickedName.isNotEmpty ? _pickedName : '우주라이크'),
      title: benefit?.resolvedTitle ??
          (widget.preLogin ? '첫 쿠폰 당첨!' : '첫 쿠폰을 준비하고 있어요'),
      subtitle: benefit?.resolvedSubtitle ??
          (widget.preLogin ? '로그인하면 바로 쓸 수 있어요' : '곧 보유 쿠폰함에서 확인할 수 있어요'),
      notes: benefit?.notesText,
      expiryText: expiryText,
      expiryUrgent: expiryUrgent,
      // 흰 배경과 구분되게 테두리 + 그림자로 입체감만 준다.
      borderColor: const Color(0xFFE1E5EA),
      // 지갑 쿠폰함과 같은 카드 그대로 — 버튼을 누르면 아래 CTA와 같은 동작.
      onAction: !_revealReady
          ? null
          : widget.preLogin
              ? () => _finish(skipped: false)
              : _goGuide,
      margin: EdgeInsets.zero,
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
              // 카드 내용(번호 배지+이모지+제목+설명)이 1.15 비율에서 기기별로
              // 몇 픽셀씩 오버플로우해서(RenderFlex overflow) 살짝 더 낮췄다.
              childAspectRatio: 1.02,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(_guideCuts.length, (i) {
                final cut = _guideCuts[i];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: OnboardingStyle.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      Text(cut.emoji, style: const TextStyle(fontSize: 26)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
