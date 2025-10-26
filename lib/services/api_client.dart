import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

    headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
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

    var retried = false;
    while (true) {
      http.Response response;
      try {
        response = await sendRequest();
      } on ApiAuthException {
        if (retried || !await _refreshAccessToken()) {
          await _invalidateSession();
          rethrow;
        }
        retried = true;
        continue;
      }

      if (response.statusCode != 401) {
        return response;
      }

      if (retried || !await _refreshAccessToken()) {
        await _invalidateSession();
        throw const ApiAuthException('세션이 만료되었어요. 다시 로그인해 주세요.');
      }
      retried = true;
    }
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
          break;
        }
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    await _invalidateSession(prefs: prefs);
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

      if (decoded['access'] is String) {
        accessToken = decoded['access'] as String;
      }
      if (decoded['refresh'] is String) {
        refreshToken = decoded['refresh'] as String;
      }
      if (decoded['token'] is Map) {
        final Map<String, dynamic> tokenMap =
            Map<String, dynamic>.from(decoded['token'] as Map);
        accessToken ??= tokenMap['access']?.toString();
        refreshToken ??= tokenMap['refresh']?.toString();
      }

      if (accessToken == null || accessToken.isEmpty) {
        return false;
      }

      await prefs.setString('jwt_access_token', accessToken);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString('jwt_refresh_token', refreshToken);
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
    await resolved.setBool('kakao_logged_in', false);
  }

  static void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiHttpException(response.statusCode, response.body);
    }
  }
}
