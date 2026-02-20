import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class UserService {
  static Future<bool> _hasValidJwt() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('kakao_logged_in') ?? false;
    final token = prefs.getString('jwt_access_token');
    return loggedIn && token != null && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>?> fetchCurrentUserProfile() async {
    if (!await _hasValidJwt()) {
      return null;
    }

    try {
      final response = await ApiClient.get('/api/users/me/');
      final dynamic data = json.decode(utf8.decode(response.bodyBytes));
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
    return _isBlank(profile['nickname']) ||
        _isBlank(profile['school']) ||
        _isBlank(profile['student_id']) ||
        _isBlank(profile['department']);
  }

  static Future<Map<String, dynamic>> updateCurrentUserProfile({
    required String nickname,
    required String school,
    required String studentId,
    required String department,
  }) async {
    final response = await ApiClient.patch(
      '/api/users/me/',
      body: {
        'nickname': nickname,
        'school': school,
        'student_id': studentId,
        'department': department,
      },
    );

    final dynamic data = json.decode(utf8.decode(response.bodyBytes));
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw const FormatException('사용자 프로필 응답 형식이 올바르지 않아요.');
  }

  static bool _isBlank(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    return false;
  }
}
