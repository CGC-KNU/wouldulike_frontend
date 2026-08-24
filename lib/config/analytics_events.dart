/// Firebase Analytics 이벤트명 및 파라미터 키 상수
class AnalyticsEvents {
  AnalyticsEvents._();

  // ========== 이벤트명 ==========
  static const String couponRedeemed = 'coupon_redeemed';
  /// 쿠폰 발급 (전환율 계산용: restaurant_id, coupon_issue_source)
  static const String couponIssued = 'coupon_issued';
  static const String backButtonClick = 'back_button_click';
  static const String appSessionStart = 'app_session_start';
  static const String appRevisit = 'app_revisit';
  static const String stampIssued = 'stamp_issued';
  static const String stampRewardCouponIssued = 'stamp_reward_coupon_issued';
  static const String restaurantFavoriteToggle = 'restaurant_favorite_toggle';
  static const String restaurantDetailScroll = 'restaurant_detail_scroll';
  static const String restaurantDetailOpen = 'restaurant_detail_open';
  static const String restaurantDetailClose = 'restaurant_detail_close';
  static const String restaurantDetailCtaClick = 'restaurant_detail_cta_click';
  static const String userSignupCompleted = 'user_signup_completed';
  /// 쿠폰 발급 경로별 보유량 (issue_key 기반)
  static const String couponIssueBreakdown = 'coupon_issue_breakdown';

  // ===== 온보딩(튜토리얼) =====
  /// 로그인 전 인삿말 컷 노출 (step: 1부터)
  static const String onboardingIntroView = 'onboarding_intro_view';
  static const String onboardingIntroComplete = 'onboarding_intro_complete';
  /// 보상 플로우에서 식당 선택
  static const String onboardingRestaurantPick = 'onboarding_restaurant_pick';
  /// 룰렛 연출 후 쿠폰 공개 (coupon_count: 0이면 조회 실패/미발급)
  static const String onboardingCouponReveal = 'onboarding_coupon_reveal';
  static const String onboardingGuideView = 'onboarding_guide_view';
  static const String onboardingComplete = 'onboarding_complete';

  // ========== 파라미터 키 ==========
  static const String paramCouponCode = 'coupon_code';
  static const String paramRestaurantId = 'restaurant_id';
  static const String paramRestaurantName = 'restaurant_name';
  static const String paramFromScreen = 'from_screen';
  static const String paramIsReturning = 'is_returning';
  static const String paramInactiveMinutes = 'inactive_minutes';
  static const String paramStampCountAfter = 'stamp_count_after';
  static const String paramCouponCount = 'coupon_count';
  static const String paramAction = 'action';
  static const String paramScrollDepth = 'scroll_depth';
  static const String paramSchoolCode = 'school_code';
  static const String paramCollegeCode = 'college_code';
  static const String paramDepartmentCode = 'department_code';
  static const String paramIssueSource = 'issue_source';
  static const String paramCount = 'count';
  static const String paramDetailSessionId = 'detail_session_id';
  static const String paramDurationMs = 'duration_ms';
  static const String paramExitType = 'exit_type';
  static const String paramCta = 'cta';
  static const String paramSource = 'source';
  static const String paramPrevRestaurantId = 'prev_restaurant_id';
  static const String paramPrevSource = 'prev_source';
  /// 쿠폰 사용 시 발급 경로 (기획전 쿠폰 처리량 분석용, campaign_code 우선)
  static const String paramCouponIssueSource = 'coupon_issue_source';
  /// 쿠폰 타입 코드 (WELCOME_3000 등)
  static const String paramCouponTypeCode = 'coupon_type_code';
  /// 이번 요청으로 적립된 스탬프 수량
  static const String paramStampAddedCount = 'stamp_added_count';
  /// 온보딩 컷/단계 번호 (1부터)
  static const String paramStep = 'step';
  /// 사용자가 건너뛰기로 종료했는지
  static const String paramSkipped = 'skipped';
}
