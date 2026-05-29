import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'main2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_client.dart';
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
import 'utils/analytics_logger.dart';
import 'utils/analytics_navigator_observer.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'services/user_service.dart';

const String kakaoNativeAppKey = '967525b584e9c1e2a2b5253888b42c83';
const MethodChannel _deviceInfoChannel = MethodChannel('app/device_info');
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
      theme: ThemeData(
        fontFamily: 'Pretendard',
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!widget.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _isCheckingProfile = false;
      });
      return;
    }

    final profile = await UserService.fetchCurrentUserProfile();
    if (!mounted) return;
    AnalyticsLogger.setUserPropertiesFromProfile(profile);
    setState(() {
      _profile = profile;
      _isProfileIncomplete = UserService.isRequiredProfileIncomplete(profile);
      _isCheckingProfile = false;
    });
  }

  void _handleProfileCompleted() {
    if (!mounted) return;
    setState(() {
      _isProfileIncomplete = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoggedIn) {
      return const LoginScreen();
    }
    if (_isCheckingProfile) {
      final showCampaignSplash = _shouldShowCampaignSplash();
      return Scaffold(
        backgroundColor:
            showCampaignSplash ? _campaignSplashBackground() : Colors.white,
        body: const _AppEntryLoadingView(),
      );
    }
    if (_isProfileIncomplete) {
      return ProfileSetupScreen(
        initialProfile: _profile,
        onCompleted: _handleProfileCompleted,
        isRequiredFlow: true,
      );
    }
    return const MainScreen();
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
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF312E81),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  bool _isLoading = true;
  static const String _uuidKey = 'user_uuid'; // SharedPreferences ??
  // 운영 중 필요 시 강제 업데이트 하한 버전을 지정해 사용할 수 있습니다. (예: '2.3.0')
  static const String? _kIosMinimumRequiredVersion = '2.3.0';
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

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => isLoggedIn ? const MainAppScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _checkForAppUpdate() async {
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
      final isBelowMinimum = _kIosMinimumRequiredVersion != null &&
          _compareVersions(currentVersion, _kIosMinimumRequiredVersion!) < 0;
      final hasNewerStoreVersion =
          _compareVersions(currentVersion, latestVersion) < 0;

      if (!hasNewerStoreVersion && !isBelowMinimum) return;

      final trackViewUrlRaw = map['trackViewUrl'];
      final trackViewUrl =
          trackViewUrlRaw is String && trackViewUrlRaw.isNotEmpty
              ? trackViewUrlRaw
              : null;
      final trackIdRaw = map['trackId'];
      final trackId =
          trackIdRaw is int ? trackIdRaw : int.tryParse('$trackIdRaw');
      final displayVersion = hasNewerStoreVersion
          ? latestVersion
          : (_kIosMinimumRequiredVersion ?? latestVersion);

      if (!mounted) return;
      await _showIosUpdateDialog(
        isForceUpdate: isBelowMinimum,
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
        : null;

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
      print('FCM Token: $token');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      await _updateFcmToken(token);
    }

    // 토큰이 회전/갱신될 때마다 서버에 최신 토큰을 업로드
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        print('FCM Token refreshed: $newToken');
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
    AnalyticsLogger.logEvent(
      'notification_open',
      parameters: {
        'message_id': message.messageId ?? '',
        'from': message.from ?? '',
        'has_data': message.data.isNotEmpty,
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

    final url = Uri.parse(
        'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/update/fcm_token/');

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

  Future<void> _checkUUID() async {
    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final checkUrl = Uri.parse(
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final checkResponse = await http.get(checkUrl);

      if (checkResponse.statusCode == 200) {
        final data = json.decode(checkResponse.body);

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
      final url = Uri.parse(
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

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
        backgroundColor:
            isSeasonalSplash ? _campaignSplashBackground() : Colors.white,
        body: isSeasonalSplash
            ? SizedBox.expand(child: _buildCampaignSplashBody())
            : Column(
                children: [
                  const Spacer(flex: 9),
                  Center(
                    child: Image.asset(
                      'assets/images/Logo-Final.png',
                      width: MediaQuery.of(context).size.width * 0.6,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Spacer(flex: 10),
                ],
              ),
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
