import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// 원격 설정(Firebase Remote Config)으로 문구·기본값을 바꾸는 창구 (기획안 결정 25).
///
/// 앱을 새로 내지 않고 "관리자 비밀번호 → 매장 PIN" 같은 문구를 바꾸기 위한 것이다.
/// - 원격 값이 없거나 비어 있거나 가져오기에 실패하면 [defaults]의 코드 기본값을 쓴다.
///   (오프라인·첫 실행에도 화면이 깨지지 않는다.)
/// - 키는 콘솔 규칙에 맞게 영문·숫자·밑줄만 쓴다.
/// - 화면은 build 때 읽으므로, 활성화된 값은 다음 진입부터 반영된다.
///
/// 지금 원격화된 화면: 쿠폰 사용(`coupon_use_*`). 홈 블록 순서 등은 이후에 같은 방식으로 추가한다.
class RemoteText {
  RemoteText._();

  /// 코드 기본값. 원격 설정이 없을 때의 정본이다.
  static const Map<String, Object> defaults = {
    'coupon_use_screen_title': '쿠폰 사용',
    'coupon_use_show_staff': '직원에게 이 화면을 보여주세요',
    'coupon_use_pin_label': '매장 PIN',
    'coupon_use_pin_help': 'PIN은 계산대 안내문에 있어요',
    // 쿠폰을 쓸 때 "스탬프도 함께 적립"을 기본으로 켤지 (결정 7: 기본 꺼짐)
    'coupon_use_with_stamp_default': false,
    // 홈 배너 자동 넘김 초 (0이면 자동 넘김 없음)
    'banner_autoplay_seconds': 5,
    // 홈 블록 순서 (쉼표로 구분). promo · mission · featured · restaurants · banner
    'home_block_order': 'promo,mission,featured,restaurants,banner',
  };

  /// 홈 블록 기본 순서. 원격 값에 빠졌거나 모르는 이름이 섞여도 블록이 사라지지 않게
  /// [resolveBlockOrder]가 이 목록으로 보정한다.
  static const List<String> homeBlockDefaultOrder = [
    'promo',
    'mission',
    'featured',
    'restaurants',
    'banner',
  ];

  /// 원격 `home_block_order` 를 읽어 블록 순서를 돌려준다.
  /// - 적힌 순서대로 앞에 두고, 모르는 이름·중복은 무시한다.
  /// - 적히지 않은 블록은 기본 순서대로 뒤에 붙인다 (오타로 블록이 숨지 않는다).
  static List<String> resolveBlockOrder(String raw) {
    final seen = <String>{};
    final order = <String>[];
    for (final part in raw.split(',')) {
      final name = part.trim().toLowerCase();
      if (homeBlockDefaultOrder.contains(name) && seen.add(name)) {
        order.add(name);
      }
    }
    for (final name in homeBlockDefaultOrder) {
      if (seen.add(name)) order.add(name);
    }
    return order;
  }

  static FirebaseRemoteConfig? _config;

  /// 앱 시작 때 한 번. 실패해도 앱 시작을 막지 않는다.
  static Future<void> init() async {
    try {
      final config = FirebaseRemoteConfig.instance;
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          // 디버그는 바로바로, 릴리스는 1시간(콘솔 쿼터 보호)
          minimumFetchInterval:
              kDebugMode ? Duration.zero : const Duration(hours: 1),
        ),
      );
      await config.setDefaults(defaults);
      _config = config;
      await config.fetchAndActivate();
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteText] init 실패, 기본값 사용: $e');
    }
  }

  /// 문구. 원격 값이 비어 있으면 코드 기본값.
  static String string(String key) {
    final fallback = defaults[key]?.toString() ?? '';
    try {
      final value = _config?.getString(key).trim() ?? '';
      return value.isEmpty ? fallback : value;
    } catch (_) {
      return fallback;
    }
  }

  static bool boolValue(String key) {
    final fallback = defaults[key] == true;
    try {
      final config = _config;
      return config == null ? fallback : config.getBool(key);
    } catch (_) {
      return fallback;
    }
  }

  static int intValue(String key) {
    final fallback = (defaults[key] as int?) ?? 0;
    try {
      final config = _config;
      return config == null ? fallback : config.getInt(key);
    } catch (_) {
      return fallback;
    }
  }
}
