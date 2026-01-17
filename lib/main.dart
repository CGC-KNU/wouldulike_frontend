import 'dart:async';
import 'package:flutter/material.dart';
import 'main2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/utils/user_type_helper.dart';
import 'services/user_service.dart';
import 'services/api_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login_screen.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';

const String kakaoNativeAppKey = '967525b584e9c1e2a2b5253888b42c83';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
      // ??λ?UUID???쑝?type ?뺤씤
      print('Stored UUID found: $storedUUID');
      await _checkType(storedUUID);
    } else {
      // ??λ?UUID???쑝???쾭?? ??줈??UUID ??꽦
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

  Future<String?> _resolveRemoteType(
      SharedPreferences prefs, String uuid) async {
    if (uuid.trim().isEmpty) {
      return null;
    }

    final bool isLoggedIn = (prefs.getBool('kakao_logged_in') ?? false) &&
        ((prefs.getString('jwt_access_token') ?? '').isNotEmpty);

    try {
      final remoteType = await UserService.fetchGuestType(uuid);
      final normalizedRemote = remoteType?.trim().toUpperCase() ?? '';
      if (normalizedRemote.isNotEmpty) {
        await prefs.setString('user_type', normalizedRemote);
        if (isLoggedIn) {
          await UserService.updateUserTypeCode(normalizedRemote);
        }
        return normalizedRemote;
      }
    } catch (e) {
      print('Guest type lookup failed: ' + e.toString());
    }

    return null;
  }

  Future<void> _checkType(String uuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      print('Checking type for UUID: ' + uuid);

      final remoteType = await _resolveRemoteType(prefs, uuid);

      final localType = (prefs.getString('user_type') ?? '').trim();

      if (remoteType != null && remoteType.isNotEmpty) {
        print('Type found: ' + remoteType);
        await prefs.setString('user_type', remoteType);
      } else if (localType.isNotEmpty) {
        print('Using cached type: ' + localType);
      } else {
        await ensureUserTypeCode(
          prefs,
          uuid: uuid,
          forceDefault: true,
        );
      }

      final bool recommendationsReady = await _populateRecommendations(uuid);
      if (!recommendationsReady) {
        await _assignFallbackType(
            force: remoteType == null &&
                (prefs.getString('user_type') ?? '').trim().isEmpty);
      }

      _navigateToMainScreen();
    } catch (e) {
      print('Error checking type: ' + e.toString());
      _showErrorDialog();
    }
  }

  Future<bool> _populateRecommendations(String uuid) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final foodUrl =
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/random-foods/?uuid=' +
              uuid;
      http.Response foodResponse;
      int retry = 0;
      int delay = 1;

      do {
        foodResponse = await http.get(Uri.parse(foodUrl));
        if (foodResponse.statusCode == 200 ||
            foodResponse.statusCode == 400 ||
            foodResponse.statusCode == 404) {
          break;
        }
        await Future.delayed(Duration(seconds: delay));
        delay *= 2;
        retry++;
      } while (retry < 3);

      if (foodResponse.statusCode == 200) {
        final foodData = json.decode(utf8.decode(foodResponse.bodyBytes))
            as Map<String, dynamic>;
        final List<dynamic> foods = foodData['random_foods'] ?? [];

        final List<String> foodNames =
            foods.map<String>((food) => food['food_name'].toString()).toList();
        await prefs.setStringList('recommended_foods', foodNames);

        final foodInfoList = foods
            .map<Map<String, dynamic>>((food) => {
                  'food_name': food['food_name'],
                  'food_image_url': food['food_image_url'],
                })
            .toList();
        await prefs.setString(
            'recommended_foods_info', json.encode(foodInfoList));

        final restaurantUrl =
            'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/';
        http.Response restaurantResponse;
        retry = 0;
        delay = 1;

        do {
          restaurantResponse = await http.post(
            Uri.parse(restaurantUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'food_names': foodNames}),
          );
          if (restaurantResponse.statusCode == 200 ||
              restaurantResponse.statusCode == 400 ||
              restaurantResponse.statusCode == 404) {
            break;
          }
          await Future.delayed(Duration(seconds: delay));
          delay *= 2;
          retry++;
        } while (retry < 3);

        if (restaurantResponse.statusCode == 200) {
          final restaurantData =
              json.decode(utf8.decode(restaurantResponse.bodyBytes))
                  as Map<String, dynamic>;
          await prefs.setString('restaurants_data',
              json.encode(restaurantData['random_restaurants']));
          return true;
        } else if (restaurantResponse.statusCode == 400 ||
            restaurantResponse.statusCode == 404) {
          _showTypeError();
          return false;
        } else {
          throw Exception('Failed to fetch restaurants');
        }
      } else if (foodResponse.statusCode == 400 ||
          foodResponse.statusCode == 404) {
        _showTypeError();
        return false;
      } else {
        throw Exception('Failed to fetch foods');
      }
    } catch (e) {
      print('Error preparing recommendations: ' + e.toString());
      return false;
    }
  }

  Future<void> _assignFallbackType({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();

    await ensureUserTypeCode(
      prefs,
      uuid: prefs.getString(_uuidKey),
      forceDefault: force,
    );

    const fallbackFoods = [
      {
        'food_name': '추천 ?식??준?중이?요',
        'food_image_url': 'assets/images/food_image0.png',
      },
    ];

    await prefs.setStringList(
      'recommended_foods',
      fallbackFoods.map((food) => food['food_name'] as String).toList(),
    );
    await prefs.setString(
      'recommended_foods_info',
      json.encode(fallbackFoods),
    );

    const fallbackRestaurants = [
      {
        'name': '추천 ?당??준?중이?요',
        'road_address': '맞춤 메뉴??정?면 ??많? ?보?????어??',
        'category_2': '?내',
        'x': '0',
        'y': '0',
        'distance': 0,
      },
    ];

    await prefs.setString(
      'restaurants_data',
      json.encode(fallbackRestaurants),
    );
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

          if (data['type_code'] != null) {
            await prefs.setString('user_type', data['type_code']);
          } else {
            await _assignFallbackType(force: true);
          }

          await _checkType(fetchedUuid);
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

          await _assignFallbackType(force: true);
          await _checkType(newUuid);
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

  void _showTypeError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Type information is missing.')),
    );
    setState(() {
      _isLoading = false;
    });
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
