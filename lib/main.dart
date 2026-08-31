import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'main2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_client.dart';
import 'services/app_config_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login_screen.dart';
import 'profile_setup_screen.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'config/analytics_events.dart';
import 'onboarding/onboarding_intro_screen.dart';
import 'onboarding/onboarding_prefs.dart';
import 'onboarding/onboarding_reward_flow.dart';
import 'onboarding/signup_onboarding_gate.dart';
import 'utils/analytics_logger.dart';
import 'utils/analytics_navigator_observer.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'services/user_service.dart';

const String kakaoNativeAppKey = '967525b584e9c1e2a2b5253888b42c83';
const MethodChannel _deviceInfoChannel = MethodChannel('app/device_info');

/// 리브랜딩 기본 스플래시 배경 (보라)
const Color _kBrandSplashColor = Color(0xFF4F46E5);

/// 기본 스플래시: 보라 배경 + 흰 로고 블록 (splash_logo.png)
class _BrandSplashView extends StatelessWidget {
  const _BrandSplashView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kBrandSplashColor,
      child: Center(
        child: Image.asset(
          'assets/images/splash_logo.png',
          width: MediaQuery.of(context).size.width * 0.3,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
class _CampaignSplashConfig {
  const _CampaignSplashConfig({
    required this.asset,
    required this.background,
    required this.start,
    required this.end,
  });

  final String asset;
  final Color background;
  final DateTime start;
  final DateTime end;
}

final _kSummerCampaignSplash = _CampaignSplashConfig(
  asset: 'assets/images/summer_splash_2026_0522_0531.png',
  background: const Color(0xFF55BCF7),
  start: DateTime(2026, 5, 22),
  end: DateTime(2026, 5, 31, 23, 59, 59),
);

final _kWorldCupCampaignSplash = _CampaignSplashConfig(
  asset: 'assets/images/worldcup_splash_2026_0608_0621.png',
  background: Colors.white,
  start: DateTime(2026, 6, 8),
  end: DateTime(2026, 6, 21, 23, 59, 59),
);

const String _kSplashMode =
    String.fromEnvironment('SPLASH_MODE', defaultValue: 'auto');

enum _CampaignSplashPreview { none, summer, worldCup }

const _CampaignSplashPreview _kCampaignSplashPreview =
    _CampaignSplashPreview.none;

bool _isInCampaignPeriod(DateTime now, _CampaignSplashConfig config) {
  return !now.isBefore(config.start) && !now.isAfter(config.end);
}

_CampaignSplashConfig? _resolveActiveCampaignSplashByDate() {
  final now = DateTime.now();
  if (_isInCampaignPeriod(now, _kWorldCupCampaignSplash)) {
    return _kWorldCupCampaignSplash;
  }
  if (_isInCampaignPeriod(now, _kSummerCampaignSplash)) {
    return _kSummerCampaignSplash;
  }
  return null;
}

_CampaignSplashConfig? _resolveActiveCampaignSplash() {
  switch (_kCampaignSplashPreview) {
    case _CampaignSplashPreview.worldCup:
      return _kWorldCupCampaignSplash;
    case _CampaignSplashPreview.summer:
      return _kSummerCampaignSplash;
    case _CampaignSplashPreview.none:
      break;
  }

  switch (_kSplashMode) {
    case 'seasonal':
      return _resolveActiveCampaignSplashByDate() ?? _kWorldCupCampaignSplash;
    case 'default':
      return null;
    default:
      return _resolveActiveCampaignSplashByDate();
  }
}

bool _shouldShowCampaignSplash() => _resolveActiveCampaignSplash() != null;

Color _campaignSplashBackground() =>
    _resolveActiveCampaignSplash()?.background ?? Colors.white;

Widget _buildCampaignSplashBody() {
  final config = _resolveActiveCampaignSplash();
  if (config == null) {
    return const SizedBox.shrink();
  }
  return ColoredBox(
    color: config.background,
    child: Center(
      child: Image(
        image: AssetImage(config.asset),
        fit: BoxFit.contain,
      ),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await MobileAds.instance.initialize();
  KakaoSdk.init(nativeAppKey: kakaoNativeAppKey, loggingEnabled: true);
  try {
    final origin = await KakaoSdk.origin;
    debugPrint('[Kakao] origin (key hash): $origin');
  } catch (_) {}
  final appLinks = AppLinks();
  // Listen for deep links such as the Kakao login redirect.
  appLinks.uriLinkStream.listen((Uri? uri) {
    if (uri != null) {
      debugPrint('Deep link received: $uri');
      DeepLinkService.instance.handleUri(uri);
    }
  });
  try {
    final initialUri = await appLinks.getInitialAppLink();
    if (initialUri != null) {
      debugPrint('Initial deep link: $initialUri');
      DeepLinkService.instance.handleUri(initialUri);
    }
  } on PlatformException {
    // Ignored: platform not ready for deep links.
  }
  final prefs = await SharedPreferences.getInstance();
  // 카카오 로그인 플래그가 있으나 JWT가 비어 있으면, UI 없이 refresh-first 복구를 먼저 시도합니다.
  await _tryAutoRecoverSession(prefs);

  // 카카오 로그인 플래그와 무관하게 JWT 존재 여부로 로그인 상태를 판단합니다.
  final jwt = prefs.getString('jwt_access_token');
  final loggedIn = jwt != null && jwt.isNotEmpty;
  runApp(MyApp(isLoggedIn: loggedIn));
}

Future<bool> _tryAutoRecoverSession(SharedPreferences prefs) async {
  final kakaoLoggedIn = prefs.getBool('kakao_logged_in') ?? false;
  if (!kakaoLoggedIn) return false;

  final jwt = prefs.getString('jwt_access_token');
  if (jwt != null && jwt.isNotEmpty) return false;

  final kakaoAccessToken = prefs.getString('kakao_access_token');
  if (kakaoAccessToken == null || kakaoAccessToken.isEmpty) {
    if (kDebugMode) {
      debugPrint('[Auth] Auto recover skipped: missing kakao_access_token');
    }
    return false;
  }

  final guestUuid = prefs.getString('user_uuid');
  try {
    final data = await AuthService.loginWithKakao(
      kakaoAccessToken,
      guestUuid: guestUuid,
    );
    if (kDebugMode) {
      debugPrint(
        '[Auth] Auto recover success (auth_method: ${data['auth_method'] ?? 'unknown'})',
      );
    }
    return true;
  } on ReloginRequiredException catch (e) {
    if (kDebugMode) {
      debugPrint(
          '[Auth] Auto recover requires relogin: ${e.code ?? e.message}');
    }
    return false;
  } catch (e) {
    // 네트워크/일시 오류일 수 있으므로 기존 플래그는 유지하고 앱 진입 후 재시도 가능 상태로 둡니다.
    if (kDebugMode) {
      debugPrint('[Auth] Auto recover failed: $e');
    }
    return false;
  }
}

class MyApp extends StatefulWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱 시작 시 토큰 상태 확인
    _checkTokenOnAppStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 타이머 취소
    ApiClient.cancelTokenRefreshTimer();
    super.dispose();
  }

  static const String _kLastAppPauseTsKey = 'last_app_pause_ts';
  static const int _kRevisitThresholdMinutes = 30;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _logAppSessionOrRevisit();
      // 앱이 포그라운드로 돌아올 때 토큰 상태 확인 및 타이머 재설정
      _checkTokenWhenResumed();
    } else if (state == AppLifecycleState.paused) {
      _savePauseTimestamp();
      // 백그라운드로 갈 때 타이머 취소 (배터리 절약)
      ApiClient.cancelTokenRefreshTimer();
    }
  }

  Future<void> _savePauseTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kLastAppPauseTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> _logAppSessionOrRevisit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPause = prefs.getInt(_kLastAppPauseTsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final inactiveMinutes =
          lastPause > 0 ? (now - lastPause) ~/ (60 * 1000) : 0;
      final isReturning =
          lastPause > 0 && inactiveMinutes >= _kRevisitThresholdMinutes;

      AnalyticsLogger.logEvent(
        AnalyticsEvents.appSessionStart,
        parameters: {
          AnalyticsEvents.paramIsReturning: isReturning,
        },
      );
      if (isReturning) {
        AnalyticsLogger.logEvent(
          AnalyticsEvents.appRevisit,
          parameters: {
            AnalyticsEvents.paramInactiveMinutes: inactiveMinutes,
          },
        );
      }
    } catch (_) {}
  }

  /// 앱 시작 시 토큰 상태 확인
  Future<void> _checkTokenOnAppStart() async {
    final prefs = await SharedPreferences.getInstance();
    await _tryAutoRecoverSession(prefs);

    if (!widget.isLoggedIn) {
      return;
    }
    // 약간의 지연 후 토큰 확인 (앱 초기화 완료 후)
    await Future.delayed(const Duration(seconds: 1));
    await _ensureTokenValid();
    // 토큰 갱신 타이머 설정
    await ApiClient.scheduleTokenRefresh();
  }

  /// 앱이 포그라운드로 돌아올 때 토큰 상태 확인
  Future<void> _checkTokenWhenResumed() async {
    final prefs = await SharedPreferences.getInstance();
    final recovered = await _tryAutoRecoverSession(prefs);
    if (recovered && mounted && !(widget.isLoggedIn)) {
      Navigator.of(context).pushReplacementNamed('/main');
      return;
    }

    if (!widget.isLoggedIn) {
      return;
    }
    await _ensureTokenValid();
    // 토큰 갱신 타이머 다시 설정
    await ApiClient.scheduleTokenRefresh();
  }

  /// 토큰이 유효한지 확인하고 필요시 갱신
  Future<void> _ensureTokenValid() async {
    try {
      // ApiClient의 ensureTokenValid 메서드를 사용
      // 이 메서드는 토큰이 곧 만료되면 자동으로 갱신합니다
      await ApiClient.ensureTokenValid();
    } catch (e) {
      // 토큰 갱신 실패는 조용히 처리 (API 요청 시 다시 시도됨)
      debugPrint('[MyApp] Token validation error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Pretendard',
        // Material 3 기본 surface(#FEF7FF)는 분홍기가 돌아 상단 안전영역이 분홍으로 보인다.
        scaffoldBackgroundColor: Colors.white,
      ),
      home: AppEntryScreen(isLoggedIn: widget.isLoggedIn),
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: _analytics),
        AnalyticsNavigatorObserver(),
      ],
      routes: {
        '/main': (context) => const MainScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

class AppEntryScreen extends StatefulWidget {
  const AppEntryScreen({super.key, required this.isLoggedIn});

  final bool isLoggedIn;

  @override
  State<AppEntryScreen> createState() => _AppEntryScreenState();
}

class _AppEntryScreenState extends State<AppEntryScreen> {
  bool _isCheckingProfile = true;
  bool _isProfileIncomplete = false;
  Map<String, dynamic>? _profile;
  // 온보딩(튜토리얼) 게이트: 첫 실행 인삿말 컷 / 가입 직후 보상 플로우
  bool _introSeen = true;
  bool _showRewardFlow = false;
  // 로그인 전 보상 플로우(식당 선택→룰렛→로그인 유도) — 프로토타입 화면 2·3
  bool _showPreLoginReward = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!widget.isLoggedIn) {
      final introSeen = await OnboardingPrefs.isIntroSeen();
      // 룰렛 연출을 이미 봤으면(완료/건너뜀) 바로 로그인 화면으로
      final rewardDone = await OnboardingPrefs.isRewardDone();
      if (!mounted) return;
      setState(() {
        _introSeen = introSeen;
        _showPreLoginReward = !rewardDone;
        _isCheckingProfile = false;
      });
      return;
    }

    final profile = await UserService.fetchCurrentUserProfile();
    // 앱 종료 등으로 보상 온보딩을 못 본 가입자는 다음 실행에서 이어서 보여준다.
    final showRewardFlow = await OnboardingPrefs.shouldShowRewardFlow();
    if (!mounted) return;
    AnalyticsLogger.setUserPropertiesFromProfile(profile);
    setState(() {
      _profile = profile;
      _isProfileIncomplete = UserService.isRequiredProfileIncomplete(profile);
      _showRewardFlow = showRewardFlow;
      _isCheckingProfile = false;
    });
  }

  void _handleProfileCompleted() {
    if (!mounted) return;
    setState(() {
      _isProfileIncomplete = false;
    });
    // 방금 가입을 마쳤으면(플래그는 프로필 저장 시 세팅) 보상 온보딩으로 진입
    OnboardingPrefs.shouldShowRewardFlow().then((show) {
      if (!mounted) return;
      setState(() {
        _showRewardFlow = show;
      });
    });
  }

  void _handleIntroFinished() {
    OnboardingPrefs.markIntroSeen();
    if (!mounted) return;
    setState(() {
      _introSeen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingProfile) {
      final showCampaignSplash = _shouldShowCampaignSplash();
      return Scaffold(
        backgroundColor: showCampaignSplash
            ? _campaignSplashBackground()
            : _kBrandSplashColor,
        body: const _AppEntryLoadingView(),
      );
    }
    if (!widget.isLoggedIn) {
      // 첫 실행: 홈/로그인 직행 대신 인삿말 컷부터
      if (!_introSeen) {
        return OnboardingIntroScreen(onFinished: _handleIntroFinished);
      }
      // 프로토타입 순서: 인트로 → 식당 선택 → 룰렛 당첨 → 카카오 로그인 유도
      if (_showPreLoginReward) {
        return OnboardingRewardFlow(
          preLogin: true,
          onFinished: () {
            if (!mounted) return;
            setState(() {
              _showPreLoginReward = false;
            });
          },
        );
      }
      return const LoginScreen();
    }
    if (_isProfileIncomplete) {
      return ProfileSetupScreen(
        initialProfile: _profile,
        onCompleted: _handleProfileCompleted,
        isRequiredFlow: true,
      );
    }
    if (_showRewardFlow) {
      return OnboardingRewardFlow(
        onFinished: () {
          if (!mounted) return;
          setState(() {
            _showRewardFlow = false;
          });
        },
      );
    }
    // 이 화면에서 이미 프로필/온보딩 게이트를 통과했으므로 중복 확인 생략
    return const MainScreen(skipOnboardingGate: true);
  }
}

class _AppEntryLoadingView extends StatelessWidget {
  const _AppEntryLoadingView();

  @override
  Widget build(BuildContext context) {
    final shouldShowSplash = _shouldShowCampaignSplash();
    if (shouldShowSplash) {
      return SizedBox.expand(child: _buildCampaignSplashBody());
    }
    return const SizedBox.expand(child: _BrandSplashView());
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.skipOnboardingGate = false});

  /// AppEntryScreen이 이미 프로필/온보딩 게이트를 통과시킨 경우 true.
  /// false면(로그인 직후 '/main' 라우트 등) 신규 가입자의 홈 직행을 막기 위해
  /// 프로필 완성 여부와 보상 온보딩 플래그를 확인한다.
  final bool skipOnboardingGate;

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  bool _isLoading = true;
  static const String _uuidKey = 'user_uuid'; // SharedPreferences ??
  StreamSubscription<InstallStatus>? _flexibleUpdateSubscription;
  bool get _isSeasonalSplashPeriod => _shouldShowCampaignSplash();

  @override
  void dispose() {
    unawaited(_flexibleUpdateSubscription?.cancel());
    _flexibleUpdateSubscription = null;
    super.dispose();
  }

  Future<void> _navigateAfterSplash() async {
    final prefs = await SharedPreferences.getInstance();
    final jwt = prefs.getString('jwt_access_token');
    final isLoggedIn = jwt != null && jwt.isNotEmpty;

    Widget destination;
    if (!isLoggedIn) {
      destination = const LoginScreen();
    } else if (widget.skipOnboardingGate) {
      destination = const MainAppScreen();
    } else {
      // 로그인 직후 경로: 신규 가입자는 홈 직행 대신
      // 프로필 설정 → 보상 온보딩(식당 선택→룰렛→사용법)을 거친다.
      Map<String, dynamic>? profile;
      bool profileIncomplete = false;
      try {
        profile = await UserService.fetchCurrentUserProfile();
        profileIncomplete = UserService.isRequiredProfileIncomplete(profile);
      } catch (_) {
        // 프로필 확인 실패 시 기존 동작(메인 진입) 유지
      }
      final showRewardFlow = await OnboardingPrefs.shouldShowRewardFlow();
      destination = (profileIncomplete || showRewardFlow)
          ? SignupOnboardingGate(
              profileIncomplete: profileIncomplete,
              initialProfile: profile,
            )
          : const MainAppScreen();
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _checkForAppUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final belowMin = AppConfigService.isBelowMinSupported(currentVersion);
      final force = AppConfigService.forceUpdateFlag() || belowMin;
      final storeUrl = AppConfigService.storeUrl();
      final hasStoreTarget =
          storeUrl.isNotEmpty || AppConfigService.appleAppId.isNotEmpty;
      if (force && hasStoreTarget) {
        await _showServerForceUpdateDialog(
          currentVersion: currentVersion,
          minSupported: AppConfigService.minSupportedVersion(),
        );
      }
    } catch (e) {
      debugPrint('[Update] 서버 버전 확인 실패: $e');
    }

    if (Platform.isAndroid) {
      try {
        final info = await InAppUpdate.checkForUpdate();

        // 이전 flexible 다운로드가 완료된 경우 설치만 진행
        if (info.installStatus == InstallStatus.downloaded) {
          await InAppUpdate.completeFlexibleUpdate();
          return;
        }

        if (info.updateAvailability != UpdateAvailability.updateAvailable) {
          return;
        }

        if (info.immediateUpdateAllowed) {
          // 필수 업데이트: 전체 화면 UI로 강제 업데이트
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          // 선택 업데이트: 다운로드 완료 후 설치
          unawaited(_startAndroidFlexibleUpdate());
        }
      } catch (e) {
        debugPrint('[Update] 업데이트 확인 실패: $e');
      }
      return;
    }

    if (Platform.isIOS) {
      await _checkForIosAppUpdate();
    }
  }

  Future<void> _startAndroidFlexibleUpdate() async {
    await _flexibleUpdateSubscription?.cancel();
    _flexibleUpdateSubscription = InAppUpdate.installUpdateListener.listen(
      (status) async {
        if (status == InstallStatus.downloaded) {
          try {
            await InAppUpdate.completeFlexibleUpdate();
          } catch (e) {
            debugPrint('[Update] flexible 설치 실패: $e');
          } finally {
            await _flexibleUpdateSubscription?.cancel();
            _flexibleUpdateSubscription = null;
          }
        } else if (status == InstallStatus.canceled ||
            status == InstallStatus.failed) {
          await _flexibleUpdateSubscription?.cancel();
          _flexibleUpdateSubscription = null;
        }
      },
    );

    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result != AppUpdateResult.success) {
        await _flexibleUpdateSubscription?.cancel();
        _flexibleUpdateSubscription = null;
      }
    } catch (e) {
      debugPrint('[Update] flexible 다운로드 시작 실패: $e');
      await _flexibleUpdateSubscription?.cancel();
      _flexibleUpdateSubscription = null;
    }
  }

  Future<void> _checkForIosAppUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final bundleId = packageInfo.packageName;
      final lookupUri = Uri.https(
        'itunes.apple.com',
        '/lookup',
        {'bundleId': bundleId, 'country': 'kr'},
      );
      final response =
          await http.get(lookupUri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return;
      final first = results.first;
      if (first is! Map) return;
      final map = Map<String, dynamic>.from(first);
      final latestVersionRaw = map['version'];
      if (latestVersionRaw is! String || latestVersionRaw.trim().isEmpty) {
        return;
      }
      final latestVersion = latestVersionRaw.trim();
      final minSupported = AppConfigService.minSupportedVersion();
      final isBelowMinimum = minSupported.isNotEmpty &&
          AppConfigService.compareVersions(currentVersion, minSupported) < 0;
      final hasNewerStoreVersion =
          AppConfigService.compareVersions(currentVersion, latestVersion) < 0;

      if (!hasNewerStoreVersion &&
          !isBelowMinimum &&
          !AppConfigService.forceUpdateFlag()) {
        return;
      }

      final configStoreUrl = AppConfigService.storeUrl();
      final trackViewUrlRaw = map['trackViewUrl'];
      final trackViewUrl = configStoreUrl.isNotEmpty
          ? configStoreUrl
          : (trackViewUrlRaw is String && trackViewUrlRaw.isNotEmpty
              ? trackViewUrlRaw
              : null);
      final trackIdRaw = map['trackId'];
      final trackId =
          trackIdRaw is int ? trackIdRaw : int.tryParse('$trackIdRaw');
      final displayVersion = hasNewerStoreVersion
          ? latestVersion
          : (minSupported.isNotEmpty ? minSupported : latestVersion);

      if (!mounted) return;
      await _showIosUpdateDialog(
        isForceUpdate: isBelowMinimum || AppConfigService.forceUpdateFlag(),
        displayVersion: displayVersion,
        storeUrl: trackViewUrl,
        trackId: trackId,
      );
    } catch (e) {
      debugPrint('[Update][iOS] 업데이트 확인 실패: $e');
    }
  }

  int _compareVersions(String a, String b) {
    List<int> normalize(String version) {
      return version
          .split('.')
          .map((part) =>
              int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final left = normalize(a);
    final right = normalize(b);
    final maxLen = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxLen; i++) {
      final lv = i < left.length ? left[i] : 0;
      final rv = i < right.length ? right[i] : 0;
      if (lv != rv) return lv.compareTo(rv);
    }
    return 0;
  }

  Future<void> _showServerForceUpdateDialog({
    required String currentVersion,
    required String minSupported,
  }) async {
    if (!mounted) return;
    final storeUrl = AppConfigService.storeUrl();
    final appleAppId = AppConfigService.appleAppId;
    final display = minSupported.isNotEmpty ? minSupported : currentVersion;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('업데이트 안내'),
            content: Text(
              '안정적인 서비스 이용을 위해 버전 $display 이상으로 업데이트가 필요해요.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (Platform.isIOS) {
                    await _launchIosStoreUrl(
                      storeUrl: storeUrl.isNotEmpty ? storeUrl : null,
                      trackId: int.tryParse(appleAppId),
                    );
                  } else if (storeUrl.isNotEmpty) {
                    final uri = Uri.tryParse(storeUrl);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  }
                },
                child: const Text('업데이트'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showIosUpdateDialog({
    required bool isForceUpdate,
    required String displayVersion,
    required String? storeUrl,
    required int? trackId,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (dialogContext) {
        return PopScope(
          canPop: !isForceUpdate,
          child: AlertDialog(
            title: const Text('업데이트 안내'),
            content: Text(
              isForceUpdate
                  ? '안정적인 서비스 이용을 위해 버전 $displayVersion 이상으로 업데이트가 필요해요.'
                  : '새 버전($displayVersion)이 출시되었어요. 더 좋은 경험을 위해 업데이트해 주세요.',
            ),
            actions: [
              if (!isForceUpdate)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('나중에'),
                ),
              TextButton(
                onPressed: () async {
                  await _launchIosStoreUrl(
                      storeUrl: storeUrl, trackId: trackId);
                  if (!isForceUpdate && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('업데이트'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchIosStoreUrl({
    required String? storeUrl,
    required int? trackId,
  }) async {
    Uri? preferred;
    if (storeUrl != null && storeUrl.isNotEmpty) {
      preferred = Uri.tryParse(storeUrl);
    }
    final fallback = trackId != null
        ? Uri.parse('itms-apps://itunes.apple.com/app/id$trackId')
        : (AppConfigService.appleAppId.isNotEmpty
            ? Uri.parse(
                'itms-apps://itunes.apple.com/app/id${AppConfigService.appleAppId}')
            : null);

    if (preferred != null) {
      final ok =
          await launchUrl(preferred, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
    if (fallback != null) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _initializeApp() async {
    await AppConfigService.prefetch();
    await OnboardingPrefs.pullFromServer();
    await _checkForAppUpdate();

    final prefs = await SharedPreferences.getInstance();
    // FCM 초기화가 너무 오래 걸려 스플래시에 머무르지 않도록 타임아웃을 건다.
    try {
      await _initFirebaseMessaging().timeout(const Duration(seconds: 5));
    } catch (e) {
      print('FCM init error/timeout: $e');
    }

    // 위치 갱신은 메인 화면 진입 후 비동기로 처리
    final storedUUID = prefs.getString(_uuidKey);
    //final storedUUID = null;
    if (storedUUID != null) {
      print('Stored UUID found: $storedUUID');
      await _navigateAfterSplash();
    } else {
      print('No UUID found in SharedPreferences. Generating a new UUID...');
      await _createUUID();
    }
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 알림 권한 요청 (Android 13 이상)
    // badge: false → 앱 아이콘 우측 상단 알림 수(배지) 표시 안 함
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('알림 권한 상태: ${settings.authorizationStatus}');

    final isIosSimulator = await _isIosSimulator();
    if (isIosSimulator) {
      debugPrint(
          'iOS simulator detected. Skip FCM token fetch; verify push on real device.');
      return;
    }

    String? token;
    try {
      token = await messaging.getToken().timeout(const Duration(seconds: 5));
    } catch (e) {
      print('FCM token fetch error/timeout: $e');
    }
    if (token != null) {
      if (kDebugMode) {
        print('FCM Token: $token');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      await _updateFcmToken(token);
    }

    // 토큰이 회전/갱신될 때마다 서버에 최신 토큰을 업로드
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        if (kDebugMode) {
          print('FCM Token refreshed: $newToken');
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);
        await _updateFcmToken(newToken);
      } catch (e) {
        print('FCM token refresh handling error: $e');
      }
    }).onError((e) {
      print('FCM onTokenRefresh stream error: $e');
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }
  }

  Future<bool> _isIosSimulator() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final value = await _deviceInfoChannel.invokeMethod<bool>('isSimulator');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    // campaign은 구매 유도 알림의 효과를 측정할 유일한 키다. 서버가 payload에
    // 실어 보내는 값을 그대로 옮겨, 마감 임박·추첨 결과·미션 리마인드를 구분한다.
    final data = message.data;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.notificationOpen,
      parameters: {
        'message_id': message.messageId ?? '',
        'from': message.from ?? '',
        'has_data': data.isNotEmpty,
        AnalyticsEvents.paramCampaign:
            data['campaign']?.toString() ?? 'unknown',
        if (data['draw_round'] != null)
          AnalyticsEvents.paramDrawRound: data['draw_round'].toString(),
      },
    );
  }

  Future<void> _updateFcmToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final uuid = prefs.getString(_uuidKey);

    if (uuid == null) {
      print('UUID not found. FCM token update postponed.');
      return;
    }

    final url = Uri.parse('${ApiClient.baseUrl}/guests/update/fcm_token/');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uuid': uuid, 'fcm_token': token}),
      );

      if (response.statusCode == 200) {
        print('FCM token updated successfully');
      } else {
        print('Failed to update FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('<')) {
      return null;
    }
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _checkUUID() async {
    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final checkUrl = Uri.parse('${ApiClient.baseUrl}/guests/retrieve/');
      final checkResponse = await http.get(checkUrl);

      if (checkResponse.statusCode == 200) {
        final data = _tryDecodeJsonMap(checkResponse.body);
        if (data == null) {
          throw Exception('UUID 응답이 JSON이 아니에요.');
        }

        if (data['uuid'] != null) {
          final prefs = await SharedPreferences.getInstance();
          final String fetchedUuid = data['uuid'];
          await prefs.setString(_uuidKey, fetchedUuid);
          await _navigateAfterSplash();
        } else {
          await _createUUID();
        }
      } else {
        throw Exception('Failed to check UUID');
      }
    } catch (e) {
      print('Error checking UUID: $e');
      _showErrorDialog();
    }
  }

  Future<void> _createUUID() async {
    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final url = Uri.parse('${ApiClient.baseUrl}/guests/retrieve/');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = _tryDecodeJsonMap(response.body);
        if (data == null) {
          throw Exception('UUID 응답이 JSON이 아니에요.');
        }

        if (data['uuid'] != null) {
          final prefs = await SharedPreferences.getInstance();
          final String newUuid = data['uuid'];
          await prefs.setString(_uuidKey, newUuid);
          print('New UUID created and saved: ' + newUuid);
          await _navigateAfterSplash();
        } else {
          throw Exception(
              'UUID creation failed: Response does not contain UUID');
        }
      } else {
        throw Exception('Failed to create UUID');
      }
    } catch (e) {
      print('Error creating UUID: $e');
      _showErrorDialog();
    }
  }

  void _showErrorDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: const Text('There was a problem verifying your UUID.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _isLoading = false;
              });
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      final isSeasonalSplash = _isSeasonalSplashPeriod;
      return Scaffold(
        backgroundColor: isSeasonalSplash
            ? _campaignSplashBackground()
            : _kBrandSplashColor,
        body: isSeasonalSplash
            ? SizedBox.expand(child: _buildCampaignSplashBody())
            : const SizedBox.expand(child: _BrandSplashView()),
      );
    }
    // 濡쒕???꾨땺 ??? ?붾㈃
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ElevatedButton(
          onPressed: _checkUUID,
          child: const Text('Retry'),
        ),
      ),
    );
  }
}
