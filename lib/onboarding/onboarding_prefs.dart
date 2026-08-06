import 'package:shared_preferences/shared_preferences.dart';

/// 온보딩(튜토리얼) 진행 상태 플래그.
///
/// 키의 버전 접미사(_v1)를 올리면 기존 사용자에게 온보딩을 다시 노출할 수 있다.
class OnboardingPrefs {
  OnboardingPrefs._();

  static const String _introSeenKey = 'onboarding_intro_seen_v1';
  static const String _rewardPendingKey = 'onboarding_reward_pending_v1';
  static const String _rewardDoneKey = 'onboarding_reward_done_v1';
  static const String _pickedRestaurantIdKey =
      'onboarding_picked_restaurant_id';
  static const String _pickedRestaurantNameKey =
      'onboarding_picked_restaurant_name';

  /// 로그인 전 인삿말 컷을 이미 봤는지
  static Future<bool> isIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introSeenKey) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
  }

  /// 가입(필수 프로필 설정) 완료 시 세팅 — 보상 플로우(식당 선택→룰렛→사용법) 노출 예약
  static Future<void> markRewardPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rewardPendingKey, true);
  }

  /// 보상 플로우를 보여줘야 하는지 (가입 직후 && 아직 안 봤음)
  static Future<bool> shouldShowRewardFlow() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_rewardPendingKey) ?? false;
    final done = prefs.getBool(_rewardDoneKey) ?? false;
    return pending && !done;
  }

  /// 룰렛 연출을 이미 소비했는지 (로그인 전 플로우 포함).
  /// true면 로그인 전 게이트는 바로 로그인 화면으로, 로그인 후 보상 플로우도 재노출하지 않는다.
  static Future<bool> isRewardDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rewardDoneKey) ?? false;
  }

  static Future<void> markRewardDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rewardDoneKey, true);
    await prefs.setBool(_rewardPendingKey, false);
  }

  /// 온보딩에서 고른 식당 — 추후 홈 개인화/식당별 쿠폰 발급 연동용
  static Future<void> savePickedRestaurant(int id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pickedRestaurantIdKey, id);
    await prefs.setString(_pickedRestaurantNameKey, name);
  }

  static Future<int?> pickedRestaurantId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pickedRestaurantIdKey);
  }

  static Future<String?> pickedRestaurantName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pickedRestaurantNameKey);
  }
}
