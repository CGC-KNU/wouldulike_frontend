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
}
