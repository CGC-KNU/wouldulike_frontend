import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ReloginRequiredException implements Exception {
  final String message;
  final String? code;

  const ReloginRequiredException(
    this.message, {
    this.code,
  });

  @override
  String toString() =>
      'ReloginRequiredException(message: $message, code: $code)';
}

class AuthService {
  static const String _baseUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app';

  static Future<Map<String, dynamic>> loginWithKakao(
      String kakaoAccessToken,
      {String? guestUuid}) async {
    final url = Uri.parse('$_baseUrl/api/auth/kakao');
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('jwt_refresh_token');
    // 이 엔드포인트는 JWT 인증이 아닌 카카오 액세스 토큰을 바디로 받도록 설계되어야 합니다.
    // Authorization 헤더에 카카오 토큰을 넣으면 서버의 JWT 인증기에 걸려 401이 납니다.
    final headers = {
      'Content-Type': 'application/json',
    };
    final payload = {
      'access_token': kakaoAccessToken,
      // refresh-first 로그인 경로: refresh가 있으면 반드시 함께 전송
      if (refreshToken != null && refreshToken.isNotEmpty) 'refresh': refreshToken,
      if (guestUuid != null && guestUuid.isNotEmpty) 'guest_uuid': guestUuid,
    };

    if (kDebugMode) {
      debugPrint('[Auth] POST $url');
      debugPrint('[Auth] headers: ${jsonEncode(headers)}');
      final dbgPayload = Map<String, dynamic>.from(payload);
      dbgPayload['access_token'] = '***';
      if (dbgPayload['refresh'] != null) {
        dbgPayload['refresh'] = '***';
      }
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
      Map<String, dynamic>? errorData;
      try {
        errorData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      final code = errorData?['code']?.toString();
      final reloginRequired = errorData?['relogin_required'] == true;
      final requiresReloginByCode = code == 'kakao_token_expired';

      if (response.statusCode == 401 &&
          (reloginRequired || requiresReloginByCode)) {
        await _clearLoginSession(prefs);
        throw ReloginRequiredException(
          '재로그인이 필요합니다.',
          code: code,
        );
      }

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

    await prefs.setBool('kakao_logged_in', true);
    final tokenData = data['token'];
    if (tokenData is! Map<String, dynamic>) {
      throw Exception('Invalid auth response: missing token payload');
    }
    await prefs.setString('jwt_access_token', tokenData['access'] as String);
    await prefs.setString('jwt_refresh_token', tokenData['refresh'] as String);
    await prefs.setInt('user_id', data['user']['id']);
    await prefs.setString(
        'user_nickname', data['user']['nickname'] ?? '');
    await prefs.setString('user_profile_image_url',
        data['user']['profile_image_url'] ?? '');
    // 카카오 ID 저장 (BigInteger이므로 String으로 저장)
    if (data['user']['kakao_id'] != null) {
      await prefs.setString('user_kakao_id', data['user']['kakao_id'].toString());
    }
    // 토큰 만료 시간 저장 (token 내부 또는 top-level 어느 쪽이든 반영)
    final accessExpiresAt = tokenData['access_expires_at'] ?? data['access_expires_at'];
    final refreshExpiresAt = tokenData['refresh_expires_at'] ?? data['refresh_expires_at'];
    if (accessExpiresAt is int) {
      await prefs.setInt('access_expires_at', accessExpiresAt);
    }
    if (refreshExpiresAt is int) {
      await prefs.setInt('refresh_expires_at', refreshExpiresAt);
    }

    if (kDebugMode) {
      final method = data['auth_method']?.toString();
      if (method == 'refresh') {
        debugPrint('[Auth] refresh-first reauthentication succeeded');
      }
    }
    return data;
  }

  static Future<void> _clearLoginSession(SharedPreferences prefs) async {
    await prefs.remove('kakao_logged_in');
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
    await prefs.remove('access_expires_at');
    await prefs.remove('refresh_expires_at');
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
    await prefs.remove('user_id');
    await prefs.remove('user_nickname');
    await prefs.remove('user_profile_image_url');
    await prefs.remove('user_kakao_id');
    await prefs.remove('access_expires_at');
    await prefs.remove('refresh_expires_at');
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
    await prefs.remove('user_id');
    await prefs.remove('user_nickname');
    await prefs.remove('user_profile_image_url');
    await prefs.remove('user_kakao_id');
    await prefs.remove('access_expires_at');
    await prefs.remove('refresh_expires_at');
  }
}
