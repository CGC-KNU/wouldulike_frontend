import 'package:flutter/foundation.dart';

/// AdMob 광고 단위 ID 설정
/// - 개발: 테스트 광고 ID 사용 (정책 위반 방지)
/// - 배포: AdMob 콘솔에서 발급받은 실제 ID로 교체
class AdConfig {
  AdConfig._();

  /// 개발/테스트 모드 여부
  static bool get useTestAds => kDebugMode;

  // ========== 앱 ID (AndroidManifest.xml, Info.plist에 설정) ==========
  /// Android AdMob 앱 ID (우주라이크)
  static const String androidAppId = 'ca-app-pub-7506586411141442~4217309465';

  /// iOS AdMob 앱 ID (wouldUlike)
  static const String iosAppId = 'ca-app-pub-7506586411141442~1482242945';

  // ========== 광고 단위 ID ==========
  /// 배너 광고 ID
  static String get bannerAdUnitId {
    if (useTestAds) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/6300978111' // Android 테스트
          : 'ca-app-pub-3940256099942544/2934735716'; // iOS 테스트
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'ca-app-pub-7506586411141442/9963009406' // Android 배너
        : 'ca-app-pub-7506586411141442/8814083843'; // iOS 배너
  }

  /// 전면 광고 ID
  static String get interstitialAdUnitId {
    if (useTestAds) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'ca-app-pub-XXXXX/XXXXX'
        : 'ca-app-pub-XXXXX/XXXXX';
  }

  /// 보상형 광고 ID
  static String get rewardedAdUnitId {
    if (useTestAds) {
      return defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'ca-app-pub-XXXXX/XXXXX'
        : 'ca-app-pub-XXXXX/XXXXX';
  }
}
