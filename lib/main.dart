import 'dart:async';
import 'package:flutter/material.dart';
import 'main2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login_screen.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'utils/analytics_logger.dart';

const String kakaoNativeAppKey = '967525b584e9c1e2a2b5253888b42c83';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  KakaoSdk.init(nativeAppKey: kakaoNativeAppKey, loggingEnabled: true);
  try {
    final origin = await KakaoSdk.origin;
    debugPrint('[Kakao] origin (key hash): ' + origin);
  } catch (_) {}
  final appLinks = AppLinks();
  // Listen for deep links such as the Kakao login redirect.
  appLinks.uriLinkStream.listen((Uri? uri) {
    if (uri != null) {
      debugPrint('Deep link received: ' + uri.toString());
    }
  });
  try {
    final initialUri = await appLinks.getInitialAppLink();
    if (initialUri != null) {
      debugPrint('Initial deep link: ' + initialUri.toString());
    }
  } on PlatformException {
    // Ignored: platform not ready for deep links.
  }
  final prefs = await SharedPreferences.getInstance();
  // Consider a user logged in only if flag is true AND JWT exists
  final kakaoLoggedIn = prefs.getBool('kakao_logged_in') ?? false;
  final jwt = prefs.getString('jwt_access_token');
  final loggedIn = kakaoLoggedIn && jwt != null && jwt.isNotEmpty;
  runApp(MyApp(isLoggedIn: loggedIn));
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 토큰 상태 확인 및 타이머 재설정
      _checkTokenWhenResumed();
    } else if (state == AppLifecycleState.paused) {
      // 백그라운드로 갈 때 타이머 취소 (배터리 절약)
      ApiClient.cancelTokenRefreshTimer();
    }
  }

  /// 앱 시작 시 토큰 상태 확인
  Future<void> _checkTokenOnAppStart() async {
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
      home: widget.isLoggedIn ? const MainScreen() : const LoginScreen(),
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: _analytics),
      ],
      routes: {
        '/main': (context) => const MainScreen(),
        '/login': (context) => const LoginScreen(),
      },
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

  void _navigateToMainScreen() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const MainAppScreen(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    await _initFirebaseMessaging();

    // 위치 갱신은 메인 화면 진입 후 비동기로 처리
    final storedUUID = prefs.getString(_uuidKey);
    //final storedUUID = null;
    if (storedUUID != null) {
      print('Stored UUID found: $storedUUID');
      _navigateToMainScreen();
    } else {
      print('No UUID found in SharedPreferences. Generating a new UUID...');
      await _createUUID();
    }
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 알림 권한 요청 (Android 13 이상)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('알림 권한 상태: ${settings.authorizationStatus}');

    String? token = await messaging.getToken();
    if (token != null) {
      print('FCM Token: \$token');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      await _updateFcmToken(token);
    }

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
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
          _navigateToMainScreen();
        } else {
          await _createUUID();
        }
      } else {
        throw Exception('Failed to check UUID');
      }
    } catch (e) {
      print('Error checking UUID: ' + e.toString());
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
          _navigateToMainScreen();
        } else {
          throw Exception(
              'UUID creation failed: Response does not contain UUID');
        }
      } else {
        throw Exception('Failed to create UUID');
      }
    } catch (e) {
      print('Error creating UUID: ' + e.toString());
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
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Spacer(flex: 9),
            Center(
              child: Image.asset(
                'assets/images/Logo-Final.png', // 濡쒓??????寃쎈?
                width:
                    MediaQuery.of(context).size.width * 0.6, // ?붾㈃ ??퉬??50%???젙
                fit: BoxFit.contain, // ??????????
              ),
            ),
            Spacer(flex: 10),
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
