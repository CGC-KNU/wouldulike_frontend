import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class UserService {
  static const String _guestRetrievePath =
      '/guests/retrieve/';

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

  static Future<void> updateUserTypeCode(String typeCode) async {
    if (typeCode.trim().isEmpty || !await _hasValidJwt()) {
      return;
    }

    try {
      await ApiClient.patch(
        '/api/users/me/',
        body: {'type_code': typeCode.trim()},
      );
    } catch (e) {
      debugPrint('Failed to update user type code: $e');
    }
  }

  static Future<String?> fetchGuestType(String uuid) async {
    if (uuid.trim().isEmpty) {
      return null;
    }

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}$_guestRetrievePath')
          .replace(queryParameters: {'uuid': uuid});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final dynamic data = json.decode(utf8.decode(response.bodyBytes));
      if (data is Map<String, dynamic>) {
        final remoteType = data['type_code']?.toString().trim();
        if (remoteType != null && remoteType.isNotEmpty) {
          return remoteType;
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch guest type: $e');
    }
    return null;
  }

  static Future<void> syncUserTypeFromGuest({String? guestUuid}) async {
    if (!await _hasValidJwt()) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final profile = await fetchCurrentUserProfile();
    final remoteType = profile?['type_code']?.toString().trim();

    if (remoteType != null && remoteType.isNotEmpty) {
      await prefs.setString('user_type', remoteType);
      return;
    }

    String? candidateType = (prefs.getString('user_type') ?? '').trim();

    if (candidateType.isEmpty && guestUuid != null && guestUuid.isNotEmpty) {
      candidateType = await fetchGuestType(guestUuid);
    }

    if (candidateType == null || candidateType.isEmpty) {
      return;
    }

    await prefs.setString('user_type', candidateType);
    await updateUserTypeCode(candidateType);
  }
}
