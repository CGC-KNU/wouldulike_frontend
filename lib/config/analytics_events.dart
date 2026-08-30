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

  // ===== 기존 발화부 상수화 =====
  // 아래 둘은 코드에 문자열 리터럴로 박혀 있던 것을 상수로 끌어올린 것이다.
  // 이벤트명은 그대로라 기존 데이터와 이어진다.
  static const String homeBannerClick = 'home_banner_click';
  static const String notificationOpen = 'notification_open';
  static const String tabView = 'tab_view';
  static const String couponPageView = 'coupon_page_view';
  static const String affiliateCategoryClick = 'affiliate_category_click';
  static const String affiliateRestaurantClick = 'affiliate_restaurant_click';
  static const String referralCodeInputClick = 'referral_code_input_click';
  static const String kakaoInviteClick = 'kakao_invite_click';

  // ===== 첫 쿠폰 보강 (룰렛·로그인) =====
  /// 룰렛 회전 시작 (연출 시작 시점, attempt_no: 1부터)
  static const String rouletteSpin = 'roulette_spin';
  /// 로그인 전 당첨 화면에서 "로그인하고 쿠폰 받기" 탭
  static const String rouletteClaimClick = 'roulette_claim_click';
  /// 카카오 인증 시작
  static const String loginStart = 'login_start';
  /// 인증 종료 — 성공·취소·오류를 result로 구분한다
  static const String loginCompleted = 'login_completed';

  // ===== 마일리지 · 식사권 응모 =====
  /// QR 스캔 등으로 마일리지 적립 성공
  static const String mileageEarn = 'mileage_earn';
  /// 마일리지 상점(응모 목록) 진입
  static const String ticketPurchaseView = 'ticket_purchase_view';
  /// 식사권 응모 확정 (마일리지 차감 성공)
  static const String ticketPurchase = 'ticket_purchase';
  /// 응모 실패 — fail_reason으로 사유를 구분한다
  static const String ticketPurchaseFailed = 'ticket_purchase_failed';
  /// 추첨 결과 확인
  static const String drawResultView = 'draw_result_view';
  /// 매장에서 식사권 사용 승인 요청
  static const String voucherRedeemAttempt = 'voucher_redeem_attempt';
  /// 식사권 승인 처리 종료 (성공·실패 모두)
  static const String voucherRedeemResult = 'voucher_redeem_result';

  // ===== 미션 트랙 =====
  static const String missionTrackView = 'mission_track_view';
  /// 개별 미션 달성 (서버 응답 기준)
  static const String missionCompleted = 'mission_completed';
  /// "리워드 받기" 탭 — 달성과 반드시 분리해 집계한다
  static const String missionRewardClaim = 'mission_reward_claim';

  // ===== 쿠폰 사용 =====
  static const String couponUseScreenView = 'coupon_use_screen_view';
  /// PIN 확인 요청 시점 (성공·실패 이전)
  static const String couponRedeemAttempt = 'coupon_redeem_attempt';
  /// 차감 실패 — fail_reason으로 사유를 구분한다
  static const String couponRedeemFailed = 'coupon_redeem_failed';

  // ===== 노출 · 탐색 =====
  /// 홈 배너 노출 (뷰포트 50% · 1초 · 인상당 1회)
  static const String homeBannerImpression = 'home_banner_impression';
  /// 매장 카드 노출 (동일 규칙)
  static const String restaurantListImpression = 'restaurant_list_impression';
  /// 검색어 확정 (엔터·디바운스 종료)
  static const String restaurantSearchSubmit = 'restaurant_search_submit';

  // ===== 실패 · 설정 =====
  /// 스탬프 적립 실패
  static const String stampAddFailed = 'stamp_add_failed';
  /// 이벤트/프로모션 알림 on·off
  static const String notificationSettingToggle = 'notification_setting_toggle';

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

  // ===== 조인 키 =====
  /// 온보딩~첫 쿠폰 구간을 잇는 세션 키. 온보딩 진입 시 1회 생성한다.
  static const String paramFirstpickSessionId = 'firstpick_session_id';
  /// 추첨 회차 식별자
  static const String paramDrawRound = 'draw_round';
  /// 응모 대상 식사권(래플) id
  static const String paramRaffleId = 'raffle_id';

  // ===== 결과 · 실패 =====
  /// 실패 사유 (insufficient_points · network 등)
  static const String paramFailReason = 'fail_reason';
  /// 처리 결과 (success · cancelled · error 등)
  static const String paramResult = 'result';

  // ===== 로그인 =====
  static const String paramMethod = 'method';
  static const String paramEntryPoint = 'entry_point';
  static const String paramIsNewUser = 'is_new_user';
  static const String paramAuthState = 'auth_state';

  // ===== 룰렛 =====
  /// 룰렛 시도 횟수 (1부터)
  static const String paramAttemptNo = 'attempt_no';

  // ===== 마일리지 =====
  static const String paramPoints = 'points';
  static const String paramPointsSpent = 'points_spent';
  static const String paramBalance = 'balance';
  static const String paramBalanceAfter = 'balance_after';
  /// 적립 유형 (qr · first_visit_bonus 등)
  static const String paramEarnType = 'earn_type';
  /// 해당 래플의 누적 응모 수
  static const String paramEntriesCount = 'entries_count';
  static const String paramIsWinner = 'is_winner';
  static const String paramPrizeType = 'prize_type';

  // ===== 식사권 =====
  static const String paramVoucherId = 'voucher_id';
  static const String paramFaceValue = 'face_value';

  // ===== 미션 =====
  static const String paramMissionId = 'mission_id';
  static const String paramStepIndex = 'step_index';
  static const String paramRewardType = 'reward_type';
  static const String paramDoneCount = 'done_count';
  static const String paramTotalCount = 'total_count';
  /// 미션 화면 진입 경로 (home_banner · wallet 등)
  static const String paramEntry = 'entry';

  // ===== 쿠폰 사용 =====
  /// 만료 임박 여부 (normal · soon)
  static const String paramExpiryState = 'expiry_state';

  // ===== 노출 · 탐색 =====
  static const String paramBannerType = 'banner_type';
  static const String paramBannerId = 'banner_id';
  static const String paramBannerIndex = 'banner_index';
  static const String paramListIndex = 'list_index';
  static const String paramListType = 'list_type';
  static const String paramCategory = 'category';
  static const String paramKeyword = 'keyword';
  static const String paramResultCount = 'result_count';
  static const String paramHasResult = 'has_result';

  // ===== 설정 · 알림 =====
  static const String paramChannel = 'channel';
  static const String paramEnabled = 'enabled';
  /// 알림 캠페인 구분 (draw_result · mission_remind 등)
  static const String paramCampaign = 'campaign';

  // ===== 상세 =====
  /// 스크롤 도달 비율 (%) — px 기반 scroll_depth와 별도로 기기 간 비교에 쓴다
  static const String paramScrollRatio = 'scroll_ratio';
}
