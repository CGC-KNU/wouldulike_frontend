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

List<MissionItem> _parseItems(dynamic raw) => raw is List
    ? raw
        .whereType<Map>()
        .map((e) => MissionItem.fromJson(Map<String, dynamic>.from(e)))
        .toList()
    : const <MissionItem>[];

/// 미션 트랙 전체 상태. 미션은 환영 미션 하나뿐이고,
/// 그게 끝나면 친구 초대(stage == invite)만 남는다.
class MissionTrack {
  const MissionTrack({
    required this.stage,
    this.welcome,
    this.promoBlock,
    this.serverTime,
  });

  factory MissionTrack.fromJson(Map<String, dynamic> json) {
    final welcomeRaw = json['welcome'];
    final promoRaw = json['promo_block'];
    return MissionTrack(
      stage: _stageFrom(json['stage'], hasWelcome: welcomeRaw is Map),
      welcome: welcomeRaw is Map
          ? WelcomeMissions.fromJson(Map<String, dynamic>.from(welcomeRaw))
          : null,
      promoBlock: promoRaw is Map
          ? PromoBlock.fromJson(Map<String, dynamic>.from(promoRaw))
          : null,
      serverTime: _asDate(json['server_time']),
    );
  }

  final MissionStage stage;

  /// 환영 미션 (stage == welcome일 때만 유효)
  final WelcomeMissions? welcome;

  /// 운영이 켰을 때만 내려오는 프로모 블록. null이면 홈에 렌더링하지 않는다.
  final PromoBlock? promoBlock;
  final DateTime? serverTime;

  /// 수령 대기 중인 리워드 개수 (배지용)
  int get claimableCount =>
      (welcome?.rewardReady ?? false) && !(welcome?.rewardClaimed ?? false)
          ? 1
          : 0;
}

class MissionService {
  /// GET /api/missions/track/ — 미션 트랙 전체 상태.
  /// 홈 배너와 미션 트랙 화면이 같은 응답을 공유한다 (스펙 7.3).
  static Future<MissionTrack?> fetchTrack() async {
    try {
      if (!await ApiClient.hasAccessToken()) {
        return null;
      }
      final http.Response response = await ApiClient.getWithoutThrow(
        '/api/missions/track/',
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400) return null;
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

/// ===== 미션 개편 (환영 미션 → 스탬프북) =====

/// 미션 단계. 환영 미션이 끝나면 친구 초대만 남는다.
enum MissionStage { welcome, invite }

MissionStage _stageFrom(dynamic raw, {required bool hasWelcome}) {
  switch (raw?.toString().toUpperCase()) {
    case 'WELCOME':
      return MissionStage.welcome;
    case 'INVITE':
      return MissionStage.invite;
  }
  // stage를 안 내려주면 환영 미션 데이터 유무로 판별한다.
  return hasWelcome ? MissionStage.welcome : MissionStage.invite;
}

/// 튜토리얼 직후 최대 3일간 열리는 환영 미션.
/// 2개를 모두 끝내거나 기간이 지나면 스탬프북으로 넘어간다.
class WelcomeMissions {
  const WelcomeMissions({
    required this.missions,
    this.reward,
    this.endsAt,
  });

  factory WelcomeMissions.fromJson(Map<String, dynamic> json) {
    final rewardRaw = json['reward'];
    return WelcomeMissions(
      missions: _parseItems(json['missions']),
      reward: rewardRaw is Map
          ? MissionItem.fromJson(Map<String, dynamic>.from(rewardRaw))
          : null,
      endsAt: _asDate(json['ends_at']),
    );
  }

  final List<MissionItem> missions;

  /// 완주 리워드 노드. 서버가 안 내려주면 안내만 표시한다.
  final MissionItem? reward;

  /// 환영 미션 종료 시각(발급 + 3일).
  final DateTime? endsAt;

  bool get allCleared => missions.isNotEmpty && missions.every((m) => m.isDone);

  /// 리워드 수령 버튼을 열어줄지. 서버 status를 우선하고,
  /// 아직 안 내려줄 때만 클라이언트 판단으로 대체한다.
  bool get rewardReady =>
      reward == null ? allCleared : reward!.status == MissionStatus.ready;

  bool get rewardClaimed => reward?.status == MissionStatus.claimed;

  int get remainingCount => missions.where((m) => !m.isDone).length;

  /// 발급 후 3일이 지났고 받을 리워드도 없으면 환영 미션은 닫힌 것으로 본다.
  /// 서버가 stage를 아직 invite로 안 넘겼어도 화면은 친구 초대로 넘어간다.
  /// [now]는 기기 시간이 아닌 서버 보정 시각을 넘겨받는다.
  bool isClosedAt(DateTime now) {
    final at = endsAt;
    return at != null && now.isAfter(at) && !rewardReady;
  }
}

/// 홈 상단 프로모 블록. 운영이 켰을 때만 내려온다.
/// 링크는 https + 허용 도메인만 연다 (앱 내에서 임의 스킴 실행 차단).
class PromoBlock {
  const PromoBlock({
    required this.active,
    required this.title,
    this.subtitle = '',
    this.ctaText = '',
    this.note = '',
    this.imageUrl,
    this.link,
    this.startsAt,
    this.endsAt,
  });

  factory PromoBlock.fromJson(Map<String, dynamic> json) {
    final image = json['image_url']?.toString();
    return PromoBlock(
      active: json['active'] == true,
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      ctaText: json['cta_text']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      imageUrl: _isSafeImageUrl(image) ? image : null,
      link: sanitizeLink(json['link_url']?.toString()),
      startsAt: _asDate(json['starts_at']),
      endsAt: _asDate(json['ends_at']),
    );
  }

  final bool active;
  final String title;
  final String subtitle;
  final String ctaText;
  final String note;

  /// null이면 텍스트형으로 렌더링한다.
  final String? imageUrl;

  /// 검증을 통과한 링크만 담긴다. null이면 탭 비활성.
  final Uri? link;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// 프로모 블록 링크로 허용하는 호스트. 서브도메인까지 허용한다.
  static const Set<String> allowedLinkHosts = <String>{
    'wouldulike.com',
    'deliberate-lenette-coggiri-5ee7b85e.koyeb.app',
  };

  /// https + 허용 도메인만 통과시킨다.
  /// intent:// · javascript: · 외부 도메인은 전부 null로 떨어뜨린다.
  static Uri? sanitizeLink(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    for (final allowed in allowedLinkHosts) {
      if (host == allowed || host.endsWith('.$allowed')) return uri;
    }
    return null;
  }

  static bool _isSafeImageUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final uri = Uri.tryParse(raw.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// 켜져 있고 노출 기간 안이며 보여줄 내용이 있는지.
  /// 기준 시각은 기기 시간이 아니라 서버 보정 시각을 넘겨받는다.
  bool isVisibleAt(DateTime now) {
    if (!active || title.trim().isEmpty) return false;
    final from = startsAt;
    final to = endsAt;
    if (from != null && now.isBefore(from)) return false;
    if (to != null && now.isAfter(to)) return false;
    return true;
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
