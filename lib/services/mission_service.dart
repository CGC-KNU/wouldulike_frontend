import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// 미션 진행 상태 (스펙 5.2 UserMissionProgress.STATUS)
enum MissionStatus { locked, open, ready, claimed, expired, unknown }

MissionStatus _statusFrom(String? raw) {
  switch (raw) {
    case 'LOCKED':
      return MissionStatus.locked;
    case 'OPEN':
      return MissionStatus.open;
    case 'READY':
      return MissionStatus.ready;
    case 'CLAIMED':
      return MissionStatus.claimed;
    case 'EXPIRED':
      return MissionStatus.expired;
    default:
      return MissionStatus.unknown;
  }
}

class MissionItem {
  const MissionItem({
    required this.code,
    required this.title,
    required this.rewardText,
    required this.status,
    required this.progress,
    required this.target,
    this.deadlineAt,
  });

  factory MissionItem.fromJson(Map<String, dynamic> json) {
    return MissionItem(
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      rewardText: json['reward_text']?.toString() ?? '',
      status: _statusFrom(json['status']?.toString()),
      progress: _asInt(json['progress']),
      target: _asInt(json['target']),
      deadlineAt: _asDate(json['deadline_at']),
    );
  }

  final String code;
  final String title;
  final String rewardText;
  final MissionStatus status;
  final int progress;
  final int target;
  final DateTime? deadlineAt;

  bool get isDone =>
      status == MissionStatus.claimed || status == MissionStatus.ready;
}

class MissionTrack {
  const MissionTrack({
    required this.missions,
    required this.rewardHeadline,
    this.serverTime,
  });

  factory MissionTrack.fromJson(Map<String, dynamic> json) {
    final raw = json['missions'];
    final missions = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => MissionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <MissionItem>[];
    return MissionTrack(
      missions: missions,
      rewardHeadline: json['reward_headline']?.toString() ?? '',
      serverTime: _asDate(json['server_time']),
    );
  }

  final List<MissionItem> missions;
  final String rewardHeadline;
  final DateTime? serverTime;

  /// 아직 완료하지 않은 미션 수 (홈 배너 문구용)
  int get remainingCount => missions.where((m) => !m.isDone).length;

  bool get hasOngoing => missions.isNotEmpty && remainingCount > 0;
}

class MissionService {
  /// GET /api/missions/track/ — 미션 트랙 전체 상태.
  /// 홈 배너와 미션 트랙 화면이 같은 응답을 공유한다 (스펙 7.3).
  static Future<MissionTrack?> fetchTrack() async {
    try {
      final http.Response response = await ApiClient.get(
        '/api/missions/track/',
      ).timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      if (decoded is Map<String, dynamic>) {
        return MissionTrack.fromJson(decoded);
      }
    } catch (_) {
      // 미션은 부가 정보이므로 실패 시 섹션을 숨긴다.
    }
    return null;
  }

  /// POST /api/missions/<code>/claim/ — 리워드 수령.
  /// 성공 시 응답 맵, 실패 시 null.
  static Future<Map<String, dynamic>?> claim(String code) async {
    try {
      final response = await ApiClient.postWithoutThrow(
        '/api/missions/$code/claim/',
        body: <String, dynamic>{},
      );
      if (response.statusCode >= 400) return null;
      final decoded = _decode(response);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return null;
    }
  }
}

dynamic _decode(http.Response response) {
  if (response.bodyBytes.isEmpty) return null;
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    return null;
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
