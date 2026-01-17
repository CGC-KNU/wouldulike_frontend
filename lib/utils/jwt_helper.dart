import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// JWT 토큰 파싱 및 검증을 위한 헬퍼 클래스
class JwtHelper {
  /// 서버에서 제공하는 만료 시간을 우선 사용하고, 없으면 JWT에서 추출합니다.
  /// 만료 시간이 없거나 파싱에 실패하면 null을 반환합니다.
  static Future<int?> getAccessTokenExpirationTime() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 서버에서 제공하는 만료 시간 우선 사용
    final serverExpiresAt = prefs.getInt('access_expires_at');
    if (serverExpiresAt != null && serverExpiresAt > 0) {
      return serverExpiresAt;
    }
    
    // 2. JWT 토큰에서 만료 시간 추출
    final token = prefs.getString('jwt_access_token');
    if (token != null && token.isNotEmpty) {
      return getExpirationTime(token);
    }
    
    return null;
  }

  /// JWT 토큰에서 만료 시간(exp)을 추출합니다.
  /// 만료 시간이 없거나 파싱에 실패하면 null을 반환합니다.
  static int? getExpirationTime(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }

      // JWT 페이로드 디코딩
      final payload = parts[1];
      // Base64 URL 디코딩 (패딩 추가)
      var normalized = base64.normalize(payload);
      final decodedBytes = base64.decode(normalized);
      final decoded = utf8.decode(decodedBytes);
      final payloadMap = jsonDecode(decoded) as Map<String, dynamic>;

      // exp (만료 시간) 추출
      if (payloadMap.containsKey('exp')) {
        return payloadMap['exp'] as int?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Access Token이 만료되었는지 확인합니다.
  /// 서버에서 제공하는 만료 시간을 우선 사용합니다.
  static Future<bool> isAccessTokenExpired() async {
    final exp = await getAccessTokenExpirationTime();
    if (exp == null) {
      return true; // 만료 시간을 확인할 수 없으면 만료된 것으로 간주
    }

    // 현재 시간(초 단위)이 만료 시간보다 크면 만료됨
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  /// JWT 토큰이 만료되었는지 확인합니다.
  /// 토큰이 없거나 파싱에 실패하면 true를 반환합니다 (안전한 기본값).
  static bool isTokenExpired(String? token) {
    if (token == null || token.isEmpty) {
      return true;
    }

    final exp = getExpirationTime(token);
    if (exp == null) {
      return true; // 만료 시간을 확인할 수 없으면 만료된 것으로 간주
    }

    // 현재 시간(초 단위)이 만료 시간보다 크면 만료됨
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  /// Access Token이 곧 만료될 것인지 확인합니다.
  /// 서버에서 제공하는 만료 시간을 우선 사용합니다.
  /// [bufferMinutes] 분 이내에 만료되면 true를 반환합니다.
  static Future<bool> isAccessTokenExpiringSoon({int bufferMinutes = 5}) async {
    final exp = await getAccessTokenExpirationTime();
    if (exp == null) {
      return true; // 만료 시간을 확인할 수 없으면 곧 만료되는 것으로 간주
    }

    // 현재 시간(초 단위)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 버퍼 시간(초 단위)
    final bufferSeconds = bufferMinutes * 60;
    // 만료 시간까지 남은 시간
    final timeUntilExpiry = exp - now;

    return timeUntilExpiry <= bufferSeconds;
  }

  /// JWT 토큰이 곧 만료될 것인지 확인합니다.
  /// [bufferMinutes] 분 이내에 만료되면 true를 반환합니다.
  static bool isTokenExpiringSoon(String? token, {int bufferMinutes = 5}) {
    if (token == null || token.isEmpty) {
      return true;
    }

    final exp = getExpirationTime(token);
    if (exp == null) {
      return true; // 만료 시간을 확인할 수 없으면 곧 만료되는 것으로 간주
    }

    // 현재 시간(초 단위)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 버퍼 시간(초 단위)
    final bufferSeconds = bufferMinutes * 60;
    // 만료 시간까지 남은 시간
    final timeUntilExpiry = exp - now;

    return timeUntilExpiry <= bufferSeconds;
  }

  /// Refresh Token이 만료되었는지 확인합니다.
  /// 서버에서 제공하는 만료 시간을 우선 사용합니다.
  static Future<bool> isRefreshTokenExpired() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 서버에서 제공하는 만료 시간 우선 사용
    final serverExpiresAt = prefs.getInt('refresh_expires_at');
    if (serverExpiresAt != null && serverExpiresAt > 0) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return now >= serverExpiresAt;
    }
    
    // 2. JWT 토큰에서 만료 시간 추출
    final token = prefs.getString('jwt_refresh_token');
    if (token != null && token.isNotEmpty) {
      return isTokenExpired(token);
    }
    
    return true;
  }

  /// JWT 토큰에서 사용자 ID를 추출합니다.
  static int? getUserId(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }

      final payload = parts[1];
      var normalized = base64.normalize(payload);
      final decodedBytes = base64.decode(normalized);
      final decoded = utf8.decode(decodedBytes);
      final payloadMap = jsonDecode(decoded) as Map<String, dynamic>;

      if (payloadMap.containsKey('user_id')) {
        return payloadMap['user_id'] as int?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}


