import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/knu_profile_options.dart';
import 'api_client.dart';
import 'master_content.dart';

class NicknameAvailabilityResult {
  const NicknameAvailabilityResult({
    required this.available,
    this.code,
  });

  final bool available;
  final String? code;
}

class ProfileSetupOptions {
  const ProfileSetupOptions({
    required this.schools,
    required this.colleges,
    required this.departments,
  });

  final List<SchoolOption> schools;
  final List<CollegeOption> colleges;
  final List<DepartmentOption> departments;
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
    final hasSchool = !_isBlank(profile['school_code']) || !_isBlank(profile['school']);
    final hasCollege = !_isBlank(profile['college_code']);
    final hasDepartment =
        !_isBlank(profile['department_code']) || !_isBlank(profile['department']);
    return _isBlank(profile['nickname']) || !hasSchool || !hasCollege || !hasDepartment;
  }

  static Future<Map<String, dynamic>> updateCurrentUserProfile({
    required String nickname,
    required String schoolCode,
    required String collegeCode,
    required String departmentCode,
    required String schoolName,
    required String departmentName,
  }) async {
    final payload = <String, dynamic>{
      'nickname': nickname,
      'school_code': schoolCode,
      'college_code': collegeCode,
      'department_code': departmentCode,
      // 구버전 백엔드 호환을 위해 이름 필드도 함께 전송
      'school': schoolName,
      'department': departmentName,
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

  static ProfileSetupOptions resolveProfileSetupOptions(
    Map<String, dynamic>? profile,
  ) {
    final schools = _parseSchools(profile?['schools']);
    final colleges = _parseColleges(profile?['colleges']);
    final departments = _parseDepartments(profile?['departments']);
    return ProfileSetupOptions(
      schools: schools.isNotEmpty ? schools : MasterContent.schools,
      colleges: colleges.isNotEmpty ? colleges : MasterContent.colleges,
      departments:
          departments.isNotEmpty ? departments : MasterContent.departments,
    );
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

  static List<SchoolOption> _parseSchools(dynamic raw) {
    if (raw is! List) return const <SchoolOption>[];
    return raw
        .whereType<Map>()
        .map((Map item) => SchoolOption(
              code: item['code']?.toString() ?? '',
              name: item['name']?.toString() ?? '',
            ))
        .where((SchoolOption e) => e.code.isNotEmpty && e.name.isNotEmpty)
        .toList();
  }

  static List<CollegeOption> _parseColleges(dynamic raw) {
    if (raw is! List) return const <CollegeOption>[];
    return raw
        .whereType<Map>()
        .map((Map item) => CollegeOption(
              code: item['code']?.toString() ?? '',
              name: item['name']?.toString() ?? '',
            ))
        .where((CollegeOption e) => e.code.isNotEmpty && e.name.isNotEmpty)
        .toList();
  }

  static List<DepartmentOption> _parseDepartments(dynamic raw) {
    if (raw is! List) return const <DepartmentOption>[];
    return raw
        .whereType<Map>()
        .map((Map item) => DepartmentOption(
              code: item['code']?.toString() ?? '',
              collegeCode: item['collegeCode']?.toString() ??
                  item['college_code']?.toString() ??
                  '',
              name: item['name']?.toString() ?? '',
            ))
        .where((DepartmentOption e) =>
            e.code.isNotEmpty && e.collegeCode.isNotEmpty && e.name.isNotEmpty)
        .toList();
  }
}
