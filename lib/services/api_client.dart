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
      throw const ApiAuthException('로그인이 필요합니다. 다시 로그인해 주세요.');
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
    final requestHeaders =
        await _headers(authenticated: authenticated, extra: headers);

    try {
      final response = await _http.get(uri, headers: requestHeaders);
      _throwIfFailed(response);
      return response;
    } on http.ClientException catch (e) {
      throw ApiNetworkException(e);
    }
  }

  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? body,
    bool authenticated = true,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path, queryParameters);
    final requestHeaders =
        await _headers(authenticated: authenticated, extra: headers);
    final payload = body == null || body is String ? body : jsonEncode(body);

    try {
      final response =
          await _http.post(uri, headers: requestHeaders, body: payload);
      _throwIfFailed(response);
      return response;
    } on http.ClientException catch (e) {
      throw ApiNetworkException(e);
    }
  }

  static void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 400) {
      throw ApiHttpException(response.statusCode, response.body);
    }
  }
}
