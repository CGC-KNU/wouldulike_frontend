import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'master_content.dart';

/// GET /api/config/policy/, /app/, /server-time/ 캐시.
/// 앱 시작 시 한 번 받아 두고, 실패하면 기존 하드코딩 기본값을 쓴다.
class AppConfigService {
  AppConfigService._();

  static const int fallbackStampMaxPerScan = 4;
  static const int fallbackStampDailyLimit = 5;
  static const int fallbackStampCycleTarget = 10;
  static const int fallbackPinLength = 4;
  static const int fallbackNicknameMaxLength = 15;
  static const String fallbackNicknamePattern = r'^[A-Za-z0-9가-힣]+$';
  static const double fallbackRegionLat = 35.8714;
  static const double fallbackRegionLng = 128.6014;
  static const String fallbackRegionName = '경북대학교';
  static const String fallbackDashboardUrl =
      'https://wouldulike-dashboard.vercel.app/';

  static Map<String, dynamic> _policy = const {};
  static Map<String, dynamic> _app = const {};
  static Duration _serverOffset = Duration.zero;
  static bool _loaded = false;

  static bool get isLoaded => _loaded;

  static Future<void> prefetch() async {
    await Future.wait([
      _loadPolicy(),
      _loadApp(),
      _loadServerTime(),
      MasterContent.prefetch(),
    ]);
    _loaded = true;
  }

  static Future<void> _loadPolicy() async {
    try {
      final response = await ApiClient.get(
        '/api/config/policy/',
        authenticated: false,
      );
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        _policy = decoded;
      }
    } catch (e) {
      debugPrint('[AppConfig] policy fetch failed: $e');
    }
  }

  static Future<void> _loadApp() async {
    try {
      final response = await ApiClient.get(
        '/api/config/app/',
        authenticated: false,
      );
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        _app = decoded;
      }
    } catch (e) {
      debugPrint('[AppConfig] app fetch failed: $e');
    }
  }

  static Future<void> _loadServerTime() async {
    try {
      final response = await ApiClient.get(
        '/api/config/server-time/',
        authenticated: false,
      );
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final epochMs = decoded['epoch_ms'];
        if (epochMs is num) {
          final server =
              DateTime.fromMillisecondsSinceEpoch(epochMs.toInt(), isUtc: true);
          _serverOffset = server.difference(DateTime.now().toUtc());
          return;
        }
        final iso = decoded['iso']?.toString();
        if (iso != null && iso.isNotEmpty) {
          final parsed = DateTime.tryParse(iso);
          if (parsed != null) {
            _serverOffset = parsed.toUtc().difference(DateTime.now().toUtc());
          }
        }
      }
    } catch (e) {
      debugPrint('[AppConfig] server-time fetch failed: $e');
    }
  }

  static DateTime now() => DateTime.now().add(_serverOffset);

  static Duration get serverOffset => _serverOffset;

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static int _int(dynamic raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  static double _double(dynamic raw, double fallback) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  static Map<String, dynamic> get _stamp => _map(_policy['stamp']);
  static Map<String, dynamic> get _pin => _map(_policy['pin']);
  static Map<String, dynamic> get _nickname => _map(_policy['nickname']);
  static Map<String, dynamic> get _links => _map(_app['links']);
  static Map<String, dynamic> get _versionRoot => _map(_app['version']);
  static Map<String, dynamic> get _defaultRegion => _map(_app['default_region']);

  static int get stampMaxPerScan =>
      _int(_stamp['max_per_scan'], fallbackStampMaxPerScan).clamp(1, 20);

  static int get stampDailyLimitPerRestaurant =>
      _int(_stamp['daily_limit_per_restaurant'], fallbackStampDailyLimit)
          .clamp(1, 99);

  static int get stampDefaultCycleTarget =>
      _int(_stamp['default_cycle_target'], fallbackStampCycleTarget)
          .clamp(1, 50);

  static int get pinLength =>
      _int(_pin['length'], fallbackPinLength).clamp(1, 12);

  static int get nicknameMaxLength =>
      _int(_nickname['max_length'], fallbackNicknameMaxLength).clamp(1, 50);

  static String get nicknamePattern {
    final raw = _nickname['pattern']?.toString().trim();
    if (raw == null || raw.isEmpty) return fallbackNicknamePattern;
    return raw;
  }

  static double get defaultLat =>
      _double(_defaultRegion['lat'], fallbackRegionLat);

  static double get defaultLng =>
      _double(_defaultRegion['lng'] ?? _defaultRegion['lon'], fallbackRegionLng);

  static String get defaultRegionName {
    final raw = _defaultRegion['name']?.toString().trim();
    if (raw == null || raw.isEmpty) return fallbackRegionName;
    return raw;
  }

  static String get kakaoChannelUrl =>
      _links['kakao_channel_url']?.toString().trim() ?? '';

  static String get csUrl => _links['cs_url']?.toString().trim() ?? '';

  static String get dashboardUrl {
    final raw = _links['dashboard_url']?.toString().trim() ?? '';
    return raw.isNotEmpty ? raw : fallbackDashboardUrl;
  }

  static String get appleAppId =>
      _links['apple_app_id']?.toString().trim() ?? '';

  static Map<String, dynamic> platformVersionConfig() {
    if (kIsWeb) return const {};
    if (Platform.isIOS) return _map(_versionRoot['ios']);
    if (Platform.isAndroid) return _map(_versionRoot['android']);
    return const {};
  }

  static String minSupportedVersion() =>
      platformVersionConfig()['min_supported']?.toString().trim() ?? '';

  static bool forceUpdateFlag() => platformVersionConfig()['force_update'] == true;

  static String storeUrl() =>
      platformVersionConfig()['store_url']?.toString().trim() ?? '';

  static int compareVersions(String a, String b) {
    List<int> normalize(String version) {
      return version
          .split('.')
          .map((part) =>
              int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final left = normalize(a);
    final right = normalize(b);
    final maxLen = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxLen; i++) {
      final lv = i < left.length ? left[i] : 0;
      final rv = i < right.length ? right[i] : 0;
      if (lv != rv) return lv.compareTo(rv);
    }
    return 0;
  }

  static bool isBelowMinSupported(String currentVersion) {
    final min = minSupportedVersion();
    if (min.isEmpty) return false;
    return compareVersions(currentVersion, min) < 0;
  }
}
