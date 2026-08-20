import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    this.completionBonus,
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
    // 완주 보너스는 서버가 completion_bonus로 내려주거나 ALL_CLEAR 미션으로 내려준다.
    final bonusRaw = json['completion_bonus'];
    final bonus = bonusRaw is Map
        ? MissionItem.fromJson(Map<String, dynamic>.from(bonusRaw))
        : null;
    return MissionTrack(
      missions: missions.where((m) => m.code != 'ALL_CLEAR').toList(),
      rewardHeadline: json['reward_headline']?.toString() ?? '',
      completionBonus: bonus ??
          missions.where((m) => m.code == 'ALL_CLEAR').firstOrNull,
      serverTime: _asDate(json['server_time']),
    );
  }

  final List<MissionItem> missions;
  final String rewardHeadline;

  /// 4단계 완주 보너스 노드. 서버가 안 내려주면 null (화면은 안내만 표시)
  final MissionItem? completionBonus;
  final DateTime? serverTime;

  /// 4단계를 모두 수령했는지 (완주 보너스 노드 활성 표기용)
  bool get allCleared =>
      missions.isNotEmpty && missions.every((m) => m.status == MissionStatus.claimed);

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
    // API 미배포 구간의 UI 확인용. 릴리스 빌드에서는 동작하지 않는다.
    // 배포 후 이 블록과 _devSampleJson을 삭제할 것.
    if (kDebugMode) return MissionTrack.fromJson(_devSampleJson());
    return null;
  }

  /// 스펙 6.2 응답 예시 기반 디버그 샘플 (배포 후 삭제)
  static Map<String, dynamic> _devSampleJson() {
    final now = DateTime.now();
    return <String, dynamic>{
      'server_time': now.toIso8601String(),
      'reward_headline': '2개만 더 완료하면 랜덤 쿠폰이 열려요',
      'missions': [
        {
          'code': 'SIGNUP',
          'title': '회원가입 하기',
          'reward_text': '첫 쿠폰 1장',
          'status': 'CLAIMED',
          'progress': 1,
          'target': 1,
          'deadline_at': null,
        },
        {
          'code': 'FIRST_COUPON',
          'title': '첫 쿠폰 받기',
          'reward_text': '제휴 매장 2,000원 할인 쿠폰',
          'status': 'READY',
          'progress': 1,
          'target': 1,
          'deadline_at':
              now.add(const Duration(days: 2, hours: 5)).toIso8601String(),
        },
        {
          'code': 'FIRST_USE',
          'title': '쿠폰 한 번 사용하기',
          'reward_text': '마일리지 500 M',
          'status': 'OPEN',
          'progress': 0,
          'target': 1,
          'deadline_at': now.add(const Duration(hours: 7)).toIso8601String(),
        },
        {
          'code': 'STAMP_5',
          'title': '스탬프 5개 모으기',
          'reward_text': '제휴 매장 랜덤 쿠폰 1종 지급',
          'status': 'OPEN',
          'progress': 2,
          'target': 5,
          'deadline_at': now.add(const Duration(days: 5)).toIso8601String(),
        },
      ],
    };
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
