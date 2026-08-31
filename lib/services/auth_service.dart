import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../onboarding/onboarding_prefs.dart';

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
    await prefs.remove('user_apple_id'); // 카카오 로그인 시 애플 변수 제거
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

  static Future<Map<String, dynamic>> loginWithApple(
    String identityToken, {
    String? authorizationCode,
    String? userIdentifier,
    String? email,
    String? guestUuid,
  }) async {
    final url = Uri.parse('$_baseUrl/api/auth/apple/login/');
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('jwt_refresh_token');
    final headers = {'Content-Type': 'application/json'};
    final payload = <String, dynamic>{
      'identity_token': identityToken,
      if (authorizationCode != null && authorizationCode.isNotEmpty)
        'authorization_code': authorizationCode,
      if (userIdentifier != null && userIdentifier.isNotEmpty)
        'user_identifier': userIdentifier,
      if (email != null && email.isNotEmpty) 'email': email,
      if (refreshToken != null && refreshToken.isNotEmpty) 'refresh': refreshToken,
      if (guestUuid != null && guestUuid.isNotEmpty) 'guest_uuid': guestUuid,
    };

    if (kDebugMode) {
      debugPrint('[Auth] POST $url (Apple login)');
    }

    final response = await http
        .post(url, headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      Map<String, dynamic>? errorData;
      try {
        errorData = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      final code = errorData?['code']?.toString();
      if (response.statusCode == 401 &&
          (errorData?['relogin_required'] == true || code == 'apple_token_invalid')) {
        await _clearLoginSession(prefs);
        throw ReloginRequiredException(
          '재로그인이 필요합니다.',
          code: code,
        );
      }
      if (kDebugMode) {
        debugPrint('[Auth] Apple login status: ${response.statusCode}');
        debugPrint('[Auth] body: ${response.body}');
      }
      throw Exception('Auth server error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await prefs.setBool('apple_logged_in', true);
    await prefs.setBool('kakao_logged_in', false);
    await prefs.remove('user_kakao_id'); // 애플 로그인 시 카카오 변수 제거

    // token이 data['token'] 또는 최상위 data에 있을 수 있음 (백엔드별 형식 대응)
    String? accessToken;
    String? newRefreshToken;
    int? accessExpiresAt;
    int? refreshExpiresAt;

    final accessVal = data['access'];
    if (accessVal is String && accessVal.isNotEmpty) accessToken = accessVal;
    final accessTokenVal = data['access_token'];
    if (accessTokenVal is String && accessTokenVal.isNotEmpty) {
      accessToken ??= accessTokenVal;
    }
    final refreshVal = data['refresh'];
    if (refreshVal is String && refreshVal.isNotEmpty) newRefreshToken = refreshVal;
    final refreshTokenVal = data['refresh_token'];
    if (refreshTokenVal is String && refreshTokenVal.isNotEmpty) {
      newRefreshToken ??= refreshTokenVal;
    }
    if (data['token'] is String) {
      final t = data['token'] as String;
      if (t.isNotEmpty) accessToken ??= t;
    }
    if (data['access_expires_at'] != null) {
      accessExpiresAt = data['access_expires_at'] as int?;
    }
    if (data['refresh_expires_at'] != null) {
      refreshExpiresAt = data['refresh_expires_at'] as int?;
    }

    final tokenData = data['token'];
    if (tokenData is Map<String, dynamic>) {
      accessToken ??= tokenData['access']?.toString();
      accessToken ??= tokenData['access_token']?.toString();
      newRefreshToken ??= tokenData['refresh']?.toString();
      newRefreshToken ??= tokenData['refresh_token']?.toString();
      accessExpiresAt ??= tokenData['access_expires_at'] as int?;
      refreshExpiresAt ??= tokenData['refresh_expires_at'] as int?;
    }

    if (accessToken == null || accessToken.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Auth] Apple login response: ${response.body}');
      }
      throw Exception('Invalid auth response: missing token payload');
    }

    await prefs.setString('jwt_access_token', accessToken);
    await prefs.setString('jwt_refresh_token', newRefreshToken ?? '');
    final userData = data['user'];
    if (userData is Map<String, dynamic>) {
      final id = userData['id'];
      await prefs.setInt('user_id',
          id is int ? id : (int.tryParse(id?.toString() ?? '') ?? 0));
      await prefs.setString(
          'user_nickname', userData['nickname']?.toString() ?? '');
      await prefs.setString(
          'user_profile_image_url',
          userData['profile_image_url']?.toString() ?? '');
      if (userData['apple_id'] != null) {
        await prefs.setString(
            'user_apple_id', userData['apple_id'].toString());
      }
    }
    if (accessExpiresAt != null) {
      await prefs.setInt('access_expires_at', accessExpiresAt);
    }
    if (refreshExpiresAt != null) {
      await prefs.setInt('refresh_expires_at', refreshExpiresAt);
    }
    return data;
  }

  static Future<void> _clearLoginSession(SharedPreferences prefs) async {
    await prefs.remove('kakao_logged_in');
    await prefs.remove('apple_logged_in');
    await prefs.remove('kakao_access_token');
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
    await prefs.remove('access_expires_at');
    await prefs.remove('refresh_expires_at');
    await prefs.remove('user_kakao_id');
    await prefs.remove('user_apple_id');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('jwt_access_token');
    final refreshToken = prefs.getString('jwt_refresh_token');

    // 서버 로그아웃 API는 토큰이 있을 때만 호출
    if (accessToken != null && refreshToken != null) {
      try {
        final url = Uri.parse('$_baseUrl/api/auth/logout');
        await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({'refresh': refreshToken}),
        );
      } catch (_) {
        // 네트워크 오류 시에도 로컬 세션은 반드시 정리
      }
    }

    // 토큰 유무와 관계없이 로컬 세션(애플/카카오 변수 포함) 항상 정리
    await prefs.remove('kakao_logged_in');
    await prefs.remove('apple_logged_in');
    await prefs.remove('kakao_access_token');
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('user_nickname');
    await prefs.remove('user_profile_image_url');
    await prefs.remove('user_kakao_id');
    await prefs.remove('user_apple_id');
    await prefs.remove('access_expires_at');
    await prefs.remove('refresh_expires_at');
    // 같은 기기에서 다른 계정으로 로그인했을 때 이전 계정의 보상 온보딩
    // 상태가 남아 튜토리얼이 안 뜨거나 잘못된 식당으로 쿠폰이 발급되지 않도록.
    await OnboardingPrefs.clearAccountScoped();
  }

  static Future<void> unlink() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('jwt_access_token');

    if (accessToken != null) {
      try {
        final url = Uri.parse('$_baseUrl/api/auth/unlink');
        await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
        );
      } catch (_) {}
    }

    // 토큰 유무와 관계없이 로컬 세션 항상 정리
    await prefs.remove('kakao_logged_in');
    await prefs.remove('apple_logged_in');
    await prefs.remove('kakao_access_token');
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('user_nickname');
    await prefs.remove('user_profile_image_url');
    await prefs.remove('user_kakao_id');
    await prefs.remove('user_apple_id');
    await prefs.remove('access_expires_at');
    await prefs.remove('refresh_expires_at');
    await OnboardingPrefs.clearAccountScoped();
  }
}
