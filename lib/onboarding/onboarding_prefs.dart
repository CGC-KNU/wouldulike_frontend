import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/api_client.dart';

/// 온보딩(튜토리얼) 진행 상태 플래그.
///
/// 키의 버전 접미사(_v1)를 올리면 기존 사용자에게 온보딩을 다시 노출할 수 있다.
/// 로컬과 서버(`/api/users/me/onboarding-flags/`)에 같은 키로 저장한다.
class OnboardingPrefs {
  OnboardingPrefs._();

  static const String _introSeenKey = 'onboarding_intro_seen_v1';
  static const String _rewardPendingKey = 'onboarding_reward_pending_v1';
  static const String _rewardDoneKey = 'onboarding_reward_done_v1';
  static const String _pickedRestaurantIdKey =
      'onboarding_picked_restaurant_id';
  static const String _pickedRestaurantNameKey =
      'onboarding_picked_restaurant_name';
  static const String _firstpickSessionIdKey = 'onboarding_firstpick_session_id';

  /// 로그인 전 인삿말 컷을 이미 봤는지
  static Future<bool> isIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introSeenKey) ?? false;
  }

  static Future<void> markIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
    await _pushFlags({_introSeenKey: true});
  }

  /// 가입(필수 프로필 설정) 완료 시 세팅 — 보상 플로우(식당 선택→룰렛→사용법) 노출 예약.
  /// [shouldShowRewardFlow]는 이제 이 값을 보지 않지만, 서버 분석/세그먼트용으로
  /// "가입 직후 예약" 신호 자체는 계속 남겨 둔다.
  static Future<void> markRewardPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rewardPendingKey, true);
    await _pushFlags({_rewardPendingKey: true});
  }

  /// 보상 플로우를 보여줘야 하는지 (아직 한 번도 완료/건너뛰지 않았음).
  /// 신규 가입 직후로만 한정하지 않는다 — 이 기능 출시 이전에 가입한 기존
  /// 계정, 혹은 다른 이유로 `pending`이 세팅된 적 없는 계정도 첫 노출 전이면
  /// 무조건 한 번은 보여줘야 하므로, `pending` 여부와 무관하게 `done`만 본다.
  static Future<bool> shouldShowRewardFlow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_rewardDoneKey) ?? false);
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
    await _pushFlags({
      _rewardDoneKey: true,
      _rewardPendingKey: false,
    });
  }

  /// 로그인 후(또는 앱 재실행 시) 서버 플래그를 로컬에 병합한다.
  /// 기기 변경 시 재노출을 막는 것 + 같은 기기를 다른 계정이 썼을 때 남은
  /// 로컬 값을 계정별 서버 진실로 덮어써 자동 복구하는 것, 두 목적을 겸한다.
  static Future<void> pullFromServer() async {
    try {
      if (!await ApiClient.hasAccessToken()) return;
      final response = await ApiClient.get('/api/users/me/onboarding-flags/');
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return;
      final flagsRaw = decoded['flags'];
      if (flagsRaw is! Map) return;
      final flags = Map<String, dynamic>.from(flagsRaw);
      final prefs = await SharedPreferences.getInstance();
      // 인삿말 컷은 기기 단위 상태라, 서버에 값이 없으면 로컬 값을 그대로 둔다.
      final introValue = flags[_introSeenKey];
      if (introValue is bool) {
        await prefs.setBool(_introSeenKey, introValue);
      }
      // 보상 온보딩(pending/done)은 계정 단위 상태다. 서버에 값이 없다는 건
      // 이 계정이 아직 한 번도 값을 낸 적 없다는 뜻이므로, 이 기기에 이전
      // 계정이 남겨둔 값을 신뢰하지 않고 기본값(false)으로 되돌린다 — 로그아웃
      // 시 정리를 놓쳤거나 구버전 앱에서 남은 오염된 로컬 값도 다음 로그인/앱
      // 실행 때 자동으로 바로잡힌다.
      for (final key in [_rewardPendingKey, _rewardDoneKey]) {
        final value = flags[key];
        await prefs.setBool(key, value is bool ? value : false);
      }
    } catch (e) {
      debugPrint('[OnboardingPrefs] pull failed: $e');
    }
  }

  /// 로그아웃/계정 탈퇴 시 호출. 이 기기에 남아있던 이전 계정의 보상 온보딩
  /// 상태(pending/done, 고른 식당, 세션 키)를 지운다. 지우지 않으면 같은
  /// 기기에서 새 계정으로 로그인했을 때 이전 계정의 `reward_done`이 남아
  /// `shouldShowRewardFlow()`가 항상 false를 반환해 신규 가입자에게 튜토리얼이
  /// 노출되지 않고, 이전 계정이 골라둔 식당으로 쿠폰이 잘못 발급될 수 있다.
  /// `_introSeenKey`는 계정이 아닌 기기 단위 상태라 그대로 둔다.
  static Future<void> clearAccountScoped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rewardPendingKey);
    await prefs.remove(_rewardDoneKey);
    await clearPickedRestaurant();
  }

  /// 보상 플로우가 (로그인 후 인스턴스에서) 끝난 뒤, 또는 로그아웃/계정 전환 시
  /// 호출. 이번 온보딩 세션에서만 유효했던 식당 선택/세션 키를 지운다 — 안
  /// 지우면 오래된 값이 로컬에 계속 남아 다음 사람/다음 세션의 정보를 오염시킬
  /// 수 있다.
  static Future<void> clearPickedRestaurant() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pickedRestaurantIdKey);
    await prefs.remove(_pickedRestaurantNameKey);
    await prefs.remove(_firstpickSessionIdKey);
  }

  static Future<void> _pushFlags(Map<String, bool> flags) async {
    try {
      if (!await ApiClient.hasAccessToken()) return;
      await ApiClient.put(
        '/api/users/me/onboarding-flags/',
        body: {'flags': flags},
      );
    } catch (e) {
      debugPrint('[OnboardingPrefs] push failed: $e');
    }
  }

  /// 온보딩~첫 쿠폰 구간을 잇는 세션 키.
  ///
  /// 로그인 전 룰렛 → 카카오 인증 → 가입 직후 보상 플로우가 서로 다른 화면·세션에
  /// 걸쳐 있어, 단계별 이탈률을 사용자·시각 근사로 추정하면 부정확해진다.
  /// 온보딩 진입 시 1회 생성해 관련 이벤트 전부에 공통으로 실어 보낸다.
  /// (매장 상세의 detail_session_id와 같은 역할)
  static Future<String> firstpickSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_firstpickSessionIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final created = const Uuid().v4();
    await prefs.setString(_firstpickSessionIdKey, created);
    return created;
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
