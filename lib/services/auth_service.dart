import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app';

  static Future<Map<String, dynamic>> loginWithKakao(String kakaoAccessToken,
      {String? guestUuid}) async {
    final url = Uri.parse('$_baseUrl/api/auth/kakao');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'access_token': kakaoAccessToken,
        if (guestUuid != null && guestUuid.isNotEmpty) 'guest_uuid': guestUuid,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to login: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('kakao_logged_in', true);
    await prefs.setString('jwt_access_token', data['token']['access']);
    await prefs.setString('jwt_refresh_token', data['token']['refresh']);
    await prefs.setInt('user_id', data['user']['id']);
    await prefs.setString(
        'user_nickname', data['user']['nickname'] ?? '');
    await prefs.setString('user_profile_image_url',
        data['user']['profile_image_url'] ?? '');
    return data;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('jwt_access_token');
    final refreshToken = prefs.getString('jwt_refresh_token');
    if (accessToken == null || refreshToken == null) return;

    final url = Uri.parse('$_baseUrl/api/auth/logout');
    await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'refresh': refreshToken}),
    );

    await prefs.remove('kakao_logged_in');
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
  }

  static Future<void> unlink() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('jwt_access_token');
    if (accessToken == null) return;

    final url = Uri.parse('$_baseUrl/api/auth/unlink');
    await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );

    await prefs.remove('kakao_logged_in');
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
  }
}
