import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app';

  static Future<Map<String, dynamic>> loginWithKakao(
      String kakaoAccessToken,
      {String? guestUuid}) async {
    final url = Uri.parse('$_baseUrl/api/auth/kakao');
    // 이 엔드포인트는 JWT 인증이 아닌 카카오 액세스 토큰을 바디로 받도록 설계되어야 합니다.
    // Authorization 헤더에 카카오 토큰을 넣으면 서버의 JWT 인증기에 걸려 401이 납니다.
    final headers = {
      'Content-Type': 'application/json',
    };
    final payload = {
      'access_token': kakaoAccessToken,
      if (guestUuid != null && guestUuid.isNotEmpty) 'guest_uuid': guestUuid,
    };

    if (kDebugMode) {
      debugPrint('[Auth] POST $url');
      debugPrint('[Auth] headers: ${jsonEncode(headers)}');
      final dbgPayload = Map<String, dynamic>.from(payload);
      dbgPayload['access_token'] = '***';
      debugPrint('[Auth] body: ${jsonEncode(dbgPayload)}');
    }

    late http.Response response;
    try {
      response = await http
          .post(url, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('Auth server unreachable: $e');
    }

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('[Auth] status: ${response.statusCode}');
        debugPrint('[Auth] body: ${response.body}');
      }
      throw Exception('Auth server error: ${response.statusCode}');
    }

    late final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] JSON parse error: $e');
      throw Exception('Invalid auth response');
    }
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
