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
  static const String userSignupCompleted = 'user_signup_completed';
  /// 쿠폰 발급 경로별 보유량 (issue_key 기반)
  static const String couponIssueBreakdown = 'coupon_issue_breakdown';

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
  /// 쿠폰 사용 시 발급 경로 (기획전 쿠폰 처리량 분석용, campaign_code 우선)
  static const String paramCouponIssueSource = 'coupon_issue_source';
  /// 쿠폰 타입 코드 (WELCOME_3000 등)
  static const String paramCouponTypeCode = 'coupon_type_code';
}
