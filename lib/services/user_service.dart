import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class NicknameAvailabilityResult {
  const NicknameAvailabilityResult({
    required this.available,
    this.code,
  });

  final bool available;
  final String? code;
}

class UserService {
  static Future<bool> _hasValidJwt() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_access_token');
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>?> fetchCurrentUserProfile() async {
    if (!await _hasValidJwt()) {
      return null;
    }

    try {
      final response = await ApiClient.get('/api/users/me/');
      final text = utf8.decode(response.bodyBytes).trimLeft();
      if (text.isEmpty || text.startsWith('<')) {
        return null;
      }
      final dynamic data = json.decode(text);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (e) {
      debugPrint('Failed to fetch user profile: $e');
    }
    return null;
  }

  static bool isRequiredProfileIncomplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    return _isBlank(profile['nickname']) || _isBlank(profile['campus']);
  }

  static Future<Map<String, dynamic>> updateCurrentUserProfile({
    required String nickname,
    required String campus,
  }) async {
    final payload = <String, dynamic>{
      'nickname': nickname,
      'campus': campus,
    };
    final response = await ApiClient.patch('/api/users/me/', body: payload);

    final dynamic data = json.decode(utf8.decode(response.bodyBytes));
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw const FormatException('사용자 프로필 응답 형식이 올바르지 않아요.');
  }

  static Future<Map<String, dynamic>> deleteMyAccount() async {
    final response = await ApiClient.delete('/api/users/me/');
    final dynamic data = json.decode(utf8.decode(response.bodyBytes));
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw const FormatException('계정 삭제 응답 형식이 올바르지 않아요.');
  }

  static Future<NicknameAvailabilityResult> checkNicknameAvailability(
    String nickname,
  ) async {
    try {
      final response = await ApiClient.get(
        '/api/users/nickname-availability',
        queryParameters: <String, dynamic>{'nickname': nickname},
      );
      final dynamic data = json.decode(utf8.decode(response.bodyBytes));
      if (data is Map<String, dynamic>) {
        final dynamic availableRaw = data['available'] ?? data['is_available'];
        if (availableRaw is! bool) {
          return const NicknameAvailabilityResult(
            available: false,
            code: 'availability_check_failed',
          );
        }
        final available = availableRaw;
        return NicknameAvailabilityResult(
          available: available,
          code: data['code']?.toString(),
        );
      }
      return const NicknameAvailabilityResult(
        available: false,
        code: 'availability_check_failed',
      );
    } on ApiHttpException catch (e) {
      final code = parseErrorCode(e.body);
      return NicknameAvailabilityResult(
        available: false,
        code: code ?? 'availability_check_failed',
      );
    } catch (_) {
      return const NicknameAvailabilityResult(
        available: false,
        code: 'availability_check_failed',
      );
    }
  }

  static String? parseErrorCode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['code'] is String) {
          return decoded['code'].toString();
        }
        if (decoded['detail'] is Map<String, dynamic> &&
            decoded['detail']['code'] is String) {
          return decoded['detail']['code'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isBlank(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    return false;
  }

}
