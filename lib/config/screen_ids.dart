/// 화면 ID. Flutter 라우트 이름 = GA4 `screen_name` = Castor 화면 지도 ID.
///
/// 라우트에 이름을 붙이면 FirebaseAnalyticsObserver 가 그 이름으로 screen_view 를 남긴다.
/// 이름이 없으면 GA4 에 "(이름 없음)"으로 쌓여 화면 이동량을 볼 수 없다.
/// 새 화면에 이름을 붙일 때는 Castor › 화면 지도의 ID와 맞춘다.
class ScreenIds {
  ScreenIds._();

  static const String home = 'home';
  static const String homeMission = 'home.mission';
  static const String storeDetail = 'store.detail';
  static const String featuredDetail = 'featured.detail';
  static const String couponUse = 'coupon.use';
  static const String couponDone = 'coupon.done';
  static const String storeList = 'store.list';
  static const String walletCoupon = 'wallet.coupon';
  static const String walletStamp = 'wallet.stamp';
  static const String walletMileage = 'wallet.mileage';
  static const String my = 'my';
  static const String sheetCouponArrived = 'sheet.coupon_arrived';

  // 10/12 — Castor 화면 지도의 나머지 ID. 라우트로 열리지 않는 화면(진입 분기·온보딩)은 initState 에서 logScreen 으로 남긴다.
  static const String appEntry = 'app.entry';
  static const String authProfile = 'auth.profile';
  static const String onboardingGate = 'onboarding.gate';
  static const String onboardingIntro = 'onboarding.intro';
  static const String onboardingReward = 'onboarding.reward';
  static const String storeFavorites = 'store.favorites';
  static const String storeNearby = 'store.nearby';
  static const String invite = 'invite';
  static const String myWishlist = 'my.wishlist';
  static const String couponLimitedPick = 'coupon.limited_pick';
  static const String mileageShop = 'mileage.shop';
  static const String raffleEntries = 'raffle.entries';
  static const String raffleResult = 'raffle.result';
  static const String raffleTerms = 'raffle.terms';
  static const String raffleWinners = 'raffle.winners';
}
