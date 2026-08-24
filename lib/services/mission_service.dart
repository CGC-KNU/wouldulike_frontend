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
    this.daily = const <MissionItem>[],
    this.weekly = const <MissionItem>[],
    this.completionBonus,
    this.serverTime,
  });

  factory MissionTrack.fromJson(Map<String, dynamic> json) {
    final missions = _parseItems(json['missions']);
    // 완주 보너스는 서버가 completion_bonus로 내려주거나 ALL_CLEAR 미션으로 내려준다.
    final bonusRaw = json['completion_bonus'];
    final bonus = bonusRaw is Map
        ? MissionItem.fromJson(Map<String, dynamic>.from(bonusRaw))
        : null;
    return MissionTrack(
      missions: missions.where((m) => m.code != 'ALL_CLEAR').toList(),
      rewardHeadline: json['reward_headline']?.toString() ?? '',
      daily: _parseItems(json['daily']),
      weekly: _parseItems(json['weekly']),
      completionBonus:
          bonus ?? missions.where((m) => m.code == 'ALL_CLEAR').firstOrNull,
      serverTime: _asDate(json['server_time']),
    );
  }

  static List<MissionItem> _parseItems(dynamic raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((e) => MissionItem.fromJson(Map<String, dynamic>.from(e)))
          .toList()
      : const <MissionItem>[];

  /// 초보자 미션 (회원가입 → 스탬프 5개). 계정당 1회.
  final List<MissionItem> missions;
  final String rewardHeadline;

  /// 초보자 미션을 끝낸 뒤 열리는 반복 미션. 마감(deadline_at)이 곧 초기화 시각.
  final List<MissionItem> daily;
  final List<MissionItem> weekly;

  /// 4단계 완주 보너스 노드. 서버가 안 내려주면 null (화면은 안내만 표시)
  final MissionItem? completionBonus;
  final DateTime? serverTime;

  /// 4단계를 모두 수령했는지 (완주 보너스 노드 활성 표기용)
  bool get allCleared =>
      missions.isNotEmpty && missions.every((m) => m.status == MissionStatus.claimed);

  /// 아직 완료하지 않은 미션 수 (홈 배너 문구용)
  int get remainingCount => missions.where((m) => !m.isDone).length;

  bool get hasOngoing => missions.isNotEmpty && remainingCount > 0;

  /// 일간·주간 미션 보유 여부.
  bool get hasRoutine => daily.isNotEmpty || weekly.isNotEmpty;

  /// 초보자 미션을 전부 소진(수령 완료 또는 만료)했는지.
  /// true면 홈 배너·미션 화면이 일간/주간 미션으로 전환된다.
  bool get beginnerDone =>
      missions.isEmpty ||
      missions.every((m) =>
          m.status == MissionStatus.claimed ||
          m.status == MissionStatus.expired);

  /// 지금 화면에 띄울 반복 미션 중 아직 못 끝낸 개수 (배너 문구용)
  int get routineRemaining =>
      daily.where((m) => !m.isDone).length +
      weekly.where((m) => !m.isDone).length;

  /// 수령 대기 중인 리워드 개수 (배지용)
  int get claimableCount => [...missions, ...daily, ...weekly]
      .where((m) => m.status == MissionStatus.ready)
      .length;
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

  /// 디버그 샘플에서 초보자 미션을 모두 끝낸 상태로 볼지 여부.
  /// true면 홈 배너·미션 화면이 일간/주간 미션으로 바뀐다 (배포 후 삭제).
  static const bool _devBeginnerDone = true;

  /// 스펙 6.2 응답 예시 기반 디버그 샘플 (배포 후 삭제)
  static Map<String, dynamic> _devSampleJson() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    // 다음 주 월요일 0시 = 주간 미션 초기화 시각
    final nextMonday = DateTime(now.year, now.month, now.day)
        .add(Duration(days: 8 - now.weekday));
    String beginner(String fallback) => _devBeginnerDone ? 'CLAIMED' : fallback;
    return <String, dynamic>{
      'server_time': now.toIso8601String(),
      'reward_headline': _devBeginnerDone
          ? '오늘의 미션을 끝내고 마일리지를 받아가세요'
          : '2개만 더 완료하면 랜덤 쿠폰이 열려요',
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
          'status': beginner('READY'),
          'progress': 1,
          'target': 1,
          'deadline_at':
              now.add(const Duration(days: 2, hours: 5)).toIso8601String(),
        },
        {
          'code': 'FIRST_USE',
          'title': '쿠폰 한 번 사용하기',
          'reward_text': '마일리지 500 M',
          'status': beginner('OPEN'),
          'progress': _devBeginnerDone ? 1 : 0,
          'target': 1,
          'deadline_at': now.add(const Duration(hours: 7)).toIso8601String(),
        },
        {
          'code': 'STAMP_5',
          'title': '스탬프 5개 모으기',
          'reward_text': '제휴 매장 랜덤 쿠폰 1종 지급',
          'status': beginner('OPEN'),
          'progress': _devBeginnerDone ? 5 : 2,
          'target': 5,
          'deadline_at': now.add(const Duration(days: 5)).toIso8601String(),
        },
      ],
      // 초보자 미션 완료 후 열리는 반복 미션. deadline_at = 다음 초기화 시각.
      'daily': !_devBeginnerDone
          ? const <Map<String, dynamic>>[]
          : [
              {
                'code': 'DAILY_STAMP_1',
                'title': '스탬프 1회 적립하기',
                'reward_text': '마일리지 50 M',
                'status': 'READY',
                'progress': 1,
                'target': 1,
                'deadline_at': midnight.toIso8601String(),
              },
              {
                'code': 'DAILY_COUPON_USE_1',
                'title': '쿠폰 1회 사용하기',
                'reward_text': '마일리지 50 M',
                'status': 'OPEN',
                'progress': 0,
                'target': 1,
                'deadline_at': midnight.toIso8601String(),
              },
            ],
      'weekly': !_devBeginnerDone
          ? const <Map<String, dynamic>>[]
          : [
              {
                'code': 'WEEKLY_STAMP_3',
                'title': '스탬프 3회 적립하기',
                'reward_text': '제휴 매장 랜덤 쿠폰 1장',
                'status': 'OPEN',
                'progress': 1,
                'target': 3,
                'deadline_at': nextMonday.toIso8601String(),
              },
              {
                'code': 'WEEKLY_COUPON_USE_3',
                'title': '쿠폰 3회 사용하기',
                'reward_text': '제휴 매장 랜덤 쿠폰 1장',
                'status': 'OPEN',
                'progress': 0,
                'target': 3,
                'deadline_at': nextMonday.toIso8601String(),
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
