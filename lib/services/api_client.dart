import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/jwt_helper.dart';

class ApiAuthException implements Exception {
  const ApiAuthException(this.message);
  final String message;

  @override
  String toString() => 'ApiAuthException: $message';
}

class ApiHttpException implements Exception {
  ApiHttpException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiHttpException(status: $statusCode, body: $body)';
}

class ApiNetworkException implements Exception {
  ApiNetworkException(this.cause);

  final Object cause;

  @override
  String toString() => 'ApiNetworkException($cause)';
}

class ApiClient {
  static const String baseUrl =
      'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app';

  static final http.Client _http = http.Client();
  static Completer<bool>? _refreshCompleter;

  static Uri _resolve(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath').replace(
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  /// 토큰이 곧 만료될 것 같으면 미리 갱신합니다.
  /// 외부에서도 호출 가능한 공개 메서드입니다.
  /// 서버에서 제공하는 만료 시간을 우선 사용합니다.
  static Future<bool> ensureTokenValid() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_access_token');
    
    if (token == null || token.isEmpty) {
      return false;
    }

    // 서버에서 제공하는 만료 시간을 우선 사용하여 확인
    final isExpiringSoon = await JwtHelper.isAccessTokenExpiringSoon(bufferMinutes: 5);
    if (isExpiringSoon) {
      return await _refreshAccessToken();
    }

    return true;
  }

  /// 내부에서만 사용하는 private 메서드
  static Future<bool> _ensureTokenValid() async {
    return ensureTokenValid();
  }

  static Future<Map<String, String>> _headers({
    bool authenticated = true,
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      HttpHeaders.acceptHeader: 'application/json',
    };

    if (extra != null && extra.isNotEmpty) {
      headers.addAll(extra);
    }

    if (!authenticated) {
      return headers;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_access_token');
    if (token == null || token.isEmpty) {
      throw const ApiAuthException('로그인이 필요해요. 다시 로그인해 주세요.');
    }

    // 토큰이 곧 만료될 것 같으면 미리 갱신 시도
    await _ensureTokenValid();

    // 갱신 후 최신 토큰 가져오기
    final latestToken = prefs.getString('jwt_access_token');
    if (latestToken == null || latestToken.isEmpty) {
      throw const ApiAuthException('로그인이 필요해요. 다시 로그인해 주세요.');
    }

    headers[HttpHeaders.authorizationHeader] = 'Bearer $latestToken';
    return headers;
  }

  static Future<http.Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path, queryParameters);
    Future<http.Response> sendRequest() async {
      final requestHeaders =
          await _headers(authenticated: authenticated, extra: headers);
      try {
        return await _http.get(uri, headers: requestHeaders);
      } on http.ClientException catch (e) {
        throw ApiNetworkException(e);
      }
    }

    final response = await _sendWithAuthRetry(
      authenticated: authenticated,
      sendRequest: sendRequest,
    );
    _throwIfFailed(response);
    return response;
  }

  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? body,
    bool authenticated = true,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path, queryParameters);
    final payload = body == null || body is String ? body : jsonEncode(body);
    Future<http.Response> sendRequest() async {
      final requestHeaders =
          await _headers(authenticated: authenticated, extra: headers);
      try {
        return await _http.post(uri, headers: requestHeaders, body: payload);
      } on http.ClientException catch (e) {
        throw ApiNetworkException(e);
      }
    }

    final response = await _sendWithAuthRetry(
      authenticated: authenticated,
      sendRequest: sendRequest,
    );
    _throwIfFailed(response);
    return response;
  }

  static Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? body,
    bool authenticated = true,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path, queryParameters);
    final payload = body == null || body is String ? body : jsonEncode(body);
    Future<http.Response> sendRequest() async {
      final requestHeaders =
          await _headers(authenticated: authenticated, extra: headers);
      try {
        return await _http.patch(uri, headers: requestHeaders, body: payload);
      } on http.ClientException catch (e) {
        throw ApiNetworkException(e);
      }
    }

    final response = await _sendWithAuthRetry(
      authenticated: authenticated,
      sendRequest: sendRequest,
    );
    _throwIfFailed(response);
    return response;
  }

  static Future<http.Response> _sendWithAuthRetry({
    required bool authenticated,
    required Future<http.Response> Function() sendRequest,
  }) async {
    if (!authenticated) {
      return sendRequest();
    }

    // 요청 전에 토큰이 유효한지 확인하고 필요시 갱신
    await _ensureTokenValid();

    const maxRetries = 2;
    var retryCount = 0;
    
    while (retryCount <= maxRetries) {
      http.Response response;
      try {
        response = await sendRequest();
      } on ApiAuthException {
        // ApiAuthException이 발생한 경우 (토큰이 없는 경우)
        if (retryCount >= maxRetries) {
          await _invalidateSession();
          rethrow;
        }
        // 토큰 갱신 시도
        final refreshSuccess = await _refreshAccessToken();
        if (!refreshSuccess) {
          final prefs = await SharedPreferences.getInstance();
          final refreshToken = prefs.getString('jwt_refresh_token');
          // refresh token이 만료된 경우에만 로그아웃
          if (refreshToken == null || refreshToken.isEmpty) {
            await _invalidateSession();
            rethrow;
          }
          final isRefreshExpired = await JwtHelper.isRefreshTokenExpired();
          if (isRefreshExpired) {
            await _invalidateSession();
            rethrow;
          }
        }
        retryCount++;
        continue;
      }

      // 401 에러 처리
      if (response.statusCode == 401) {
        if (retryCount >= maxRetries) {
          final prefs = await SharedPreferences.getInstance();
          final refreshToken = prefs.getString('jwt_refresh_token');
          // refresh token이 만료되었는지 확인 (서버 제공 만료 시간 우선 사용)
          if (refreshToken == null || refreshToken.isEmpty) {
            await _invalidateSession();
            throw const ApiAuthException('세션이 만료되었어요. 다시 로그인해 주세요.');
          }
          final isRefreshExpired = await JwtHelper.isRefreshTokenExpired();
          if (isRefreshExpired) {
            await _invalidateSession();
            throw const ApiAuthException('세션이 만료되었어요. 다시 로그인해 주세요.');
          }
          // refresh token이 유효한데도 401이면 서버 문제일 수 있음
          throw ApiHttpException(401, response.body);
        }

        // 토큰 갱신 시도
        final refreshSuccess = await _refreshAccessToken();
        if (!refreshSuccess) {
          final prefs = await SharedPreferences.getInstance();
          final refreshToken = prefs.getString('jwt_refresh_token');
          // refresh token이 만료되었는지 확인 (서버 제공 만료 시간 우선 사용)
          if (refreshToken == null || refreshToken.isEmpty) {
            await _invalidateSession();
            throw const ApiAuthException('세션이 만료되었어요. 다시 로그인해 주세요.');
          }
          final isRefreshExpired = await JwtHelper.isRefreshTokenExpired();
          if (isRefreshExpired) {
            await _invalidateSession();
            throw const ApiAuthException('세션이 만료되었어요. 다시 로그인해 주세요.');
          }
          // 네트워크 문제일 수 있으므로 잠시 대기 후 재시도
          await Future.delayed(const Duration(milliseconds: 500));
        }
        retryCount++;
        continue;
      }

      // 성공적인 응답 반환
      return response;
    }

    // 최대 재시도 횟수 초과
    throw const ApiAuthException('인증에 실패했어요. 다시 시도해 주세요.');
  }

  static Future<bool> _refreshAccessToken() async {
    final inFlight = _refreshCompleter;
    if (inFlight != null) {
      return inFlight.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    _performTokenRefresh().then((success) {
      completer.complete(success);
    }).catchError((_) {
      completer.complete(false);
    }).whenComplete(() {
      _refreshCompleter = null;
    });

    return completer.future;
  }

  static Future<bool> _performTokenRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('jwt_refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    // refresh token이 만료되었는지 확인 (서버 제공 만료 시간 우선 사용)
    final isRefreshExpired = await JwtHelper.isRefreshTokenExpired();
    if (isRefreshExpired) {
      // refresh token이 만료되었으면 세션 무효화하지 않고 false만 반환
      // 호출자가 세션 무효화를 결정하도록 함
      return false;
    }

    const candidates = <String>[
      '/api/auth/token/refresh/',
      '/api/auth/refresh/',
    ];

    for (final path in candidates) {
      final url = Uri.parse('$baseUrl$path');
      try {
        final response = await _http
            .post(
              url,
              headers: const {
                HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
                HttpHeaders.acceptHeader: 'application/json',
              },
              body: jsonEncode({'refresh': refreshToken}),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          return _storeRefreshedTokens(prefs, response.body);
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          // 서버에서 401/403을 반환하면 refresh token이 만료된 것으로 간주
          break;
        }
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    // 토큰 갱신 실패 - 하지만 세션을 즉시 무효화하지 않음
    // 호출자가 결정하도록 false만 반환
    return false;
  }

  static Future<bool> _storeRefreshedTokens(
      SharedPreferences prefs, String body) async {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      String? accessToken;
      String? refreshToken;
      int? accessExpiresAt;
      int? refreshExpiresAt;

      // 직접 access, refresh 필드 확인
      if (decoded['access'] is String) {
        accessToken = decoded['access'] as String;
      }
      if (decoded['refresh'] is String) {
        refreshToken = decoded['refresh'] as String;
      }
      if (decoded['access_expires_at'] != null) {
        accessExpiresAt = decoded['access_expires_at'] as int?;
      }
      if (decoded['refresh_expires_at'] != null) {
        refreshExpiresAt = decoded['refresh_expires_at'] as int?;
      }

      // token 객체 내부 확인
      if (decoded['token'] is Map) {
        final Map<String, dynamic> tokenMap =
            Map<String, dynamic>.from(decoded['token'] as Map);
        accessToken ??= tokenMap['access']?.toString();
        refreshToken ??= tokenMap['refresh']?.toString();
        if (tokenMap['access_expires_at'] != null) {
          accessExpiresAt ??= tokenMap['access_expires_at'] as int?;
        }
        if (tokenMap['refresh_expires_at'] != null) {
          refreshExpiresAt ??= tokenMap['refresh_expires_at'] as int?;
        }
      }

      if (accessToken == null || accessToken.isEmpty) {
        return false;
      }

      await prefs.setString('jwt_access_token', accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString('jwt_refresh_token', refreshToken);
      }
      // 토큰 만료 시간 저장
      if (accessExpiresAt != null) {
        await prefs.setInt('access_expires_at', accessExpiresAt);
      }
      if (refreshExpiresAt != null) {
        await prefs.setInt('refresh_expires_at', refreshExpiresAt);
      }
      await prefs.setBool('kakao_logged_in', true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _invalidateSession({SharedPreferences? prefs}) async {
    final resolved = prefs ?? await SharedPreferences.getInstance();
    await resolved.remove('jwt_access_token');
    await resolved.remove('jwt_refresh_token');
    await resolved.remove('access_expires_at');
    await resolved.remove('refresh_expires_at');
    await resolved.setBool('kakao_logged_in', false);
    // 타이머 취소
    _cancelTokenRefreshTimer();
  }

  static void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiHttpException(response.statusCode, response.body);
    }
  }

  /// 토큰 검증 API를 호출하여 현재 ACCESS_TOKEN의 유효성을 확인합니다.
  /// 응답 예시: {"valid": true, "expires_at": 1735689600, "expires_in": 86400, "user_id": 123}
  /// 또는: {"valid": false, "detail": "Token is invalid or expired", "code": "token_not_valid"}
  static Future<Map<String, dynamic>?> verifyToken() async {
    try {
      final response = await get(
        '/api/auth/verify',
        authenticated: true,
      );
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        
        // 서버에서 제공하는 만료 시간 업데이트
        if (decoded['expires_at'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('access_expires_at', decoded['expires_at'] as int);
        }
        
        return decoded;
      }
      return null;
    } catch (e) {
      // 토큰 검증 실패는 에러로 처리하지 않음
      return null;
    }
  }

  // 타이머 기반 자동 갱신
  static Timer? _tokenRefreshTimer;

  /// 토큰 만료 5분 전에 자동 갱신하도록 타이머를 설정합니다.
  /// 서버에서 제공하는 만료 시간을 사용합니다.
  static Future<void> scheduleTokenRefresh() async {
    // 기존 타이머 취소
    _cancelTokenRefreshTimer();

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('jwt_access_token');
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    // 서버에서 제공하는 만료 시간 우선 사용
    final expiresAt = await JwtHelper.getAccessTokenExpirationTime();
    if (expiresAt == null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresIn = expiresAt - now;
    const bufferSeconds = 5 * 60; // 5분
    final refreshIn = expiresIn - bufferSeconds;

    // 이미 만료되었거나 곧 만료되면 즉시 갱신
    if (refreshIn <= 0) {
      await ensureTokenValid();
      // 갱신 후 새 타이머 설정
      await scheduleTokenRefresh();
      return;
    }

    // 타이머 설정 (밀리초 단위)
    _tokenRefreshTimer = Timer(
      Duration(seconds: refreshIn),
      () async {
        await ensureTokenValid();
        // 갱신 후 새 타이머 설정
        await scheduleTokenRefresh();
      },
    );
  }

  /// 토큰 갱신 타이머를 취소합니다.
  static void _cancelTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  /// 토큰 갱신 타이머를 취소합니다 (외부에서 호출 가능).
  static void cancelTokenRefreshTimer() {
    _cancelTokenRefreshTimer();
  }
}


