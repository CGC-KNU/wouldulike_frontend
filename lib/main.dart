import 'dart:async';
import 'package:flutter/material.dart';
import 'main2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
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

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: isLoggedIn ? const MainScreen() : const LoginScreen(),
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

    // ?㎛ ?꾩튂 沅뚰븳 ?붿껌 諛??섏쭛
    await _getAndSaveUserLocation();

    final storedUUID = prefs.getString(_uuidKey);
    //final storedUUID = null;
    if (storedUUID != null) {
      // ??λ맂 UUID媛 ?덉쑝硫?type ?뺤씤
      print('Stored UUID found: $storedUUID');
      await _checkType(storedUUID);
    } else {
      // ??λ맂 UUID媛 ?놁쑝硫??쒕쾭?먯꽌 ?덈줈??UUID ?앹꽦
      print('No UUID found in SharedPreferences. Generating a new UUID...');
      await _createUUID();
    }
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
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

  Future<void> _getAndSaveUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permission denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permission permanently denied');
      return;
    }

    // ???꾩튂 媛?몄삤湲?
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    print('Current location: ${position.latitude}, ${position.longitude}');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('user_lat', position.latitude);
    await prefs.setDouble('user_lon', position.longitude);
  }

  Future<void> _checkType(String uuid) async {
    try {
      final checkUrl = Uri.parse(
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/?uuid=$uuid');
      print('Checking type for UUID: $uuid');
      final checkResponse = await http.get(checkUrl);

      if (checkResponse.statusCode == 200) {
        final data = json.decode(checkResponse.body);

        if (data['type_code'] != null) {
          // Type??議댁옱?섎㈃ ?뚯떇怨??뚯떇???곗씠?곕? 癒쇱? 媛?몄샂
          print('Type found: ${data['type_code']}');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_type', data['type_code']);

          // 1. ??낆뿉 留욌뒗 ?뚯떇 5媛吏 媛?몄삤湲?
          final foodUrl =
              'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/random-foods/?uuid=$uuid';
          http.Response foodResponse;
          int retry = 0;
          int delay = 1;
          do {
            foodResponse = await http.get(Uri.parse(foodUrl));
            if (foodResponse.statusCode == 200 ||
                foodResponse.statusCode == 400 ||
                foodResponse.statusCode == 404) break;
            await Future.delayed(Duration(seconds: delay));
            delay *= 2;
            retry++;
          } while (retry < 3);
          if (foodResponse.statusCode == 200) {
            final foodData = json.decode(foodResponse.body);
            final foods = foodData['random_foods'];

            // ?뚯떇 ?대쫫?????
            List<String> foodNames = foods
                .map<String>((food) => food['food_name'].toString())
                .toList();
            await prefs.setStringList('recommended_foods', foodNames);

            // 2. ?뚯떇???곗씠??媛?몄삤湲?
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
                  restaurantResponse.statusCode == 404) break;
              await Future.delayed(Duration(seconds: delay));
              delay *= 2;
              retry++;
            } while (retry < 3);

            if (restaurantResponse.statusCode == 200) {
              final restaurantData = json.decode(restaurantResponse.body);
              await prefs.setString('restaurants_data',
                  json.encode(restaurantData['random_restaurants']));
            } else if (restaurantResponse.statusCode == 400 ||
                restaurantResponse.statusCode == 404) {
              _showTypeError();
            }
          } else if (foodResponse.statusCode == 400 ||
              foodResponse.statusCode == 404) {
            _showTypeError();
          }

          // ?곗씠?곕? 紐⑤몢 媛?몄삩 ??硫붿씤 ?붾㈃?쇰줈 ?대룞
          _navigateToMainScreen();
        } else {
          _navigateToMainScreen();
        }
      } else {
        throw Exception('Failed to check type');
      }
    } catch (e) {
      print('Error checking type: $e');
      _showErrorDialog();
    }
  }

  Future<void> _checkUUID() async {
    try {
      final checkUrl = Uri.parse(
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final checkResponse = await http.get(checkUrl);

      if (checkResponse.statusCode == 200) {
        final data = json.decode(checkResponse.body);

        if (data['uuid'] != null) {
          // UUID瑜?SharedPreferences?????
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_uuidKey, data['uuid']);

          if (data['type_code'] != null) {
            _navigateToMainScreen();
          } else {
            _navigateToMainScreen();
          }
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
    try {
      final url = Uri.parse(
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['uuid'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_uuidKey, data['uuid']);
          print('New UUID created and saved: ${data['uuid']}');

          // ?덈줈??UUID ?앹꽦 ??諛붾줈 ?ㅻЦ ?붾㈃?쇰줈 ?대룞
          _navigateToMainScreen();
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
                'assets/images/Logo-Final.png', // 濡쒓퀬 ?대?吏 寃쎈줈
                width: MediaQuery.of(context).size.width *
                    0.6, // ?붾㈃ ?덈퉬??50%濡??ㅼ젙
                fit: BoxFit.contain, // ?대?吏 鍮꾩쑉 ?좎?
              ),
            ),
            Spacer(flex: 10),
          ],
        ),
      );
    }
    // 濡쒕뵫???꾨땺 ?뚯쓽 ?붾㈃
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
