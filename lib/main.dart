import 'package:flutter/material.dart';
import 'start_survey.dart';
import 'home.dart';
import 'main2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'login_screen.dart';
import 'package:kakao_flutter_sdk_common/kakao_flutter_sdk_common.dart';

const String kakaoNativeAppKey = '967525b584e9c1e2a2b5253888b42c83';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  final prefs = await SharedPreferences.getInstance();
  final loggedIn = prefs.getBool('kakao_logged_in') ?? false;
  runApp(MyApp(isLoggedIn: loggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: isLoggedIn ? MainScreen() : const LoginScreen(),
      routes: {
        '/main': (context) => MainScreen(),
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isLoading = true;
  static const String _uuidKey = 'user_uuid'; // SharedPreferences 키

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    await _initFirebaseMessaging();

    // 🧭 위치 권한 요청 및 수집
    await _getAndSaveUserLocation();

    final storedUUID = prefs.getString(_uuidKey);
    //final storedUUID = null;
    if (storedUUID != null) {
      // 저장된 UUID가 있으면 type 확인
      print('Stored UUID found: $storedUUID');
      await _checkType(storedUUID);
    } else {
      // 저장된 UUID가 없으면 서버에서 새로운 UUID 생성
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

    final url = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/update/fcm_token/');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uuid': uuid, 'fcm_token': token}),
      );

      if (response.statusCode == 200) {
        print('✅ FCM token updated successfully');
      } else {
        print('❌ Failed to update FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('🚨 Error updating FCM token: $e');
    }
  }


  Future<void> _getAndSaveUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ 위치 서비스 꺼짐');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('❌ 위치 권한 거부됨');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ 위치 권한 영구 거부됨');
      return;
    }

    // ✅ 위치 가져오기
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    print('📍 현재 위치: ${position.latitude}, ${position.longitude}');

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
          // Type이 존재하면 음식과 음식점 데이터를 먼저 가져옴
         print('Type found: ${data['type_code']}');

          // FoodRecommendationScreen의 fetchRecommendedData 로직을 여기서 실행
          final prefs = await SharedPreferences.getInstance();

          // 1. 타입에 맞는 음식 5가지 가져오기
          final foodUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/random-foods/?uuid=$uuid';
          final foodResponse = await http.get(Uri.parse(foodUrl));
          if (foodResponse.statusCode == 200) {
            final foodData = json.decode(foodResponse.body);
            final foods = foodData['random_foods'];

            // 음식 이름들 저장
            List<String> foodNames = foods
                .map<String>((food) => food['food_name'].toString())
                .toList();
            await prefs.setStringList('recommended_foods', foodNames);

            // 2. 음식점 데이터 가져오기
            final restaurantUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/';
            final restaurantResponse = await http.post(
              Uri.parse(restaurantUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'food_names': foodNames}),
            );

            if (restaurantResponse.statusCode == 200) {
              final restaurantData = json.decode(restaurantResponse.body);
              await prefs.setString('restaurants_data', json.encode(restaurantData['random_restaurants']));
            }
          }

          // 데이터를 모두 가져온 후 메인 화면으로 이동
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainAppScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => StartSurveyScreen()),
          );
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
      final checkUrl = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final checkResponse = await http.get(checkUrl);

      if (checkResponse.statusCode == 200) {
        final data = json.decode(checkResponse.body);

        if (data['uuid'] != null) {
          // UUID를 SharedPreferences에 저장
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_uuidKey, data['uuid']);

          if (data['type_code'] != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => MainAppScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => StartSurveyScreen()),
            );
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

          // 새로운 UUID 생성 후 바로 설문 화면으로 이동
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => StartSurveyScreen()),
          );
        } else {
          throw Exception('UUID creation failed: Response does not contain UUID');
        }
      } else {
        throw Exception('Failed to create UUID');
      }
    } catch (e) {
      print('Error creating UUID: $e');
      _showErrorDialog();
    }
  }
/*
  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUUID = prefs.getString(_uuidKey);

    if (storedUUID != null) {
      // 저장된 UUID가 있으면 type 확인
      await _checkType(storedUUID);
    } else {
      // 저장된 UUID가 없으면 서버에서 확인
      await _checkUUID();
    }
  }

  Future<void> _checkType(String uuid) async {
    try {
      final checkUrl = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      print('Checking type for UUID: $uuid'); // UUID 값 확인
      print('Request URL: $checkUrl'); // URL 확인

      final checkResponse = await http.get(checkUrl);
      print('Response status code: ${checkResponse.statusCode}'); // 상태 코드 확인
      print('Response body: ${checkResponse.body}'); // 응답 데이터 확인

      if (checkResponse.statusCode == 200) {
        final data = json.decode(checkResponse.body);
        print('Parsed data: $data'); // 파싱된 데이터 확인

        if (data['type'] != null) {
          print('Type found: ${data['type']}');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MainAppScreen()),
          );
        } else {
          print('Type is null, redirecting to survey');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => StartSurveyScreen()),
          );
        }
      } else {
        throw Exception('Failed to check type: ${checkResponse.statusCode}');
      }
    } catch (e) {
      print('Error checking type: $e');
      _showErrorDialog();
    }
  }

  Future<void> _checkUUID() async {
    try {
      final checkUrl = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final checkResponse = await http.get(checkUrl);

      if (checkResponse.statusCode == 200) {
        final data = json.decode(checkResponse.body);

        if (data['uuid'] != null) {
          // UUID를 SharedPreferences에 저장
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_uuidKey, data['uuid']);

          if (data['type'] != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => MainAppScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => StartSurveyScreen()),
            );
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
      final url = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/');
      final response = await http.post(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('UUID 생성 성공: ${data['uuid']}');

        // 새로 생성된 UUID를 SharedPreferences에 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_uuidKey, data['uuid']);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => StartSurveyScreen()),
        );
      } else {
        throw Exception('Failed to create UUID');
      }
    } catch (e) {
      print('Error creating UUID: $e');
      _showErrorDialog();
    }
  }
*/
  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: const Text('UUID를 확인하거나 생성하는 데 문제가 발생했습니다.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _isLoading = false;
              });
            },
            child: const Text('확인'),
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
                'assets/images/Logo-Final.png', // 로고 이미지 경로
                width: MediaQuery.of(context).size.width * 0.6, // 화면 너비의 50%로 설정
                fit: BoxFit.contain, // 이미지 비율 유지
              ),
            ),
            Spacer(flex: 10),
          ],
        ),
      );
    }
    // 로딩이 아닐 때의 화면
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ElevatedButton(
          onPressed: _checkUUID,
          child: const Text('다시 시도'),
        ),
      ),
    );
  }
}
