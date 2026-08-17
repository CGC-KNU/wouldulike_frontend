import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'api_client.dart';

/// 마일리지 잔액 요약 (GET /api/mileage/summary/)
class MileageSummary {
  const MileageSummary({required this.balance, required this.monthEarned});

  factory MileageSummary.fromJson(Map<String, dynamic> json) {
    return MileageSummary(
      balance: _asInt(json['balance']),
      monthEarned: _asInt(json['month_earned']),
    );
  }

  final int balance;
  final int monthEarned;
}

/// 마일리지 원장 1건 (GET /api/mileage/history/)
class MileageEvent {
  const MileageEvent({
    required this.delta,
    required this.reason,
    required this.memo,
    this.createdAt,
  });

  factory MileageEvent.fromJson(Map<String, dynamic> json) {
    return MileageEvent(
      delta: _asInt(json['delta']),
      reason: json['reason']?.toString() ?? '',
      memo: json['memo']?.toString() ?? '',
      createdAt: _asDate(json['created_at']),
    );
  }

  final int delta;
  final String reason;
  final String memo;
  final DateTime? createdAt;

  bool get isEarn => delta > 0;

  /// 메모가 비어 있을 때 사유 코드로 대체 표기 (스펙 5.1 REASON)
  String get label {
    if (memo.isNotEmpty) return memo;
    switch (reason) {
      case 'VISIT':
        return '방문 적립';
      case 'MISSION':
        return '미션 보상';
      case 'RAFFLE':
        return '응모 차감';
      case 'ADMIN':
        return '운영 조정';
      default:
        return '마일리지 변동';
    }
  }
}

class MileageHistoryPage {
  const MileageHistoryPage({required this.events, this.nextCursor});

  final List<MileageEvent> events;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

/// 응모 가능한 식사권 (GET /api/raffles/)
class Raffle {
  const Raffle({
    required this.id,
    required this.title,
    required this.prizeAmount,
    required this.costMileage,
    required this.restaurantName,
    required this.entriesCount,
    required this.entered,
    this.closesAt,
  });

  factory Raffle.fromJson(Map<String, dynamic> json) {
    return Raffle(
      id: _asInt(json['id']),
      title: json['title']?.toString() ?? '식사권',
      prizeAmount: _asInt(json['prize_amount']),
      costMileage: _asInt(json['cost_mileage']),
      restaurantName: json['restaurant_name']?.toString() ?? '',
      entriesCount: _asInt(json['entries_count']),
      entered: json['entered'] == true,
      closesAt: _asDate(json['closes_at']),
    );
  }

  final int id;
  final String title;
  final int prizeAmount;
  final int costMileage;
  final String restaurantName;
  final int entriesCount;
  final bool entered;
  final DateTime? closesAt;
}

/// 응모 결과. 실패 시 code로 사유 구분 (스펙 6.2)
class RaffleEnterResult {
  const RaffleEnterResult({
    required this.ok,
    this.balanceAfter,
    this.entriesCount,
    this.code,
    this.message,
    this.balance,
  });

  final bool ok;
  final int? balanceAfter;
  final int? entriesCount;

  /// INSUFFICIENT_MILEAGE · ALREADY_ENTERED · RAFFLE_CLOSED
  final String? code;
  final String? message;

  /// 잔액 부족 시 서버가 알려주는 현재 잔액
  final int? balance;

  bool get isAlreadyEntered => code == 'ALREADY_ENTERED';
}

class MileageService {
  static Future<MileageSummary?> fetchSummary() async {
    try {
      final response = await ApiClient.get('/api/mileage/summary/')
          .timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      if (decoded is Map<String, dynamic>) {
        return MileageSummary.fromJson(decoded);
      }
    } catch (_) {}
    // API 미배포 구간의 UI 확인용. 릴리스 빌드에서는 동작하지 않는다. (배포 후 삭제)
    if (kDebugMode) return const MileageSummary(balance: 12400, monthEarned: 1800);
    return null;
  }

  /// 커서 페이지네이션 20건 (스펙 7.1)
  static Future<MileageHistoryPage> fetchHistory({String? cursor}) async {
    try {
      final response = await ApiClient.get(
        '/api/mileage/history/',
        queryParameters: cursor != null ? {'cursor': cursor} : null,
      ).timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['results'];
        final events = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => MileageEvent.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : <MileageEvent>[];
        return MileageHistoryPage(
          events: events,
          nextCursor: _cursorFrom(decoded['next']),
        );
      }
    } catch (_) {}
    if (kDebugMode && cursor == null) {
      return MileageHistoryPage(events: _devEvents());
    }
    return const MileageHistoryPage(events: []);
  }

  static Future<List<Raffle>> fetchRaffles() async {
    try {
      final response =
          await ApiClient.get('/api/raffles/').timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      final raw = decoded is Map<String, dynamic> ? decoded['results'] : decoded;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Raffle.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    if (kDebugMode) return _devRaffles();
    return const [];
  }

  /// 응모. 재시도 시 중복 차감을 막기 위해 멱등 키를 항상 보낸다 (스펙 6.2).
  static Future<RaffleEnterResult> enterRaffle(
    int raffleId, {
    String? idempotencyKey,
  }) async {
    try {
      final response = await ApiClient.postWithoutThrow(
        '/api/raffles/$raffleId/enter/',
        body: {
          'idempotency_key': idempotencyKey ?? generateRaffleKey(raffleId),
        },
      );
      final decoded = _decode(response);
      final map =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      if (response.statusCode >= 400) {
        return RaffleEnterResult(
          ok: false,
          code: map['code']?.toString(),
          message: map['message']?.toString(),
          balance: map['balance'] == null ? null : _asInt(map['balance']),
          entriesCount: map['entries_count'] == null
              ? null
              : _asInt(map['entries_count']),
        );
      }
      return RaffleEnterResult(
        ok: true,
        balanceAfter: _asInt(map['balance_after']),
        entriesCount: _asInt(map['entries_count']),
      );
    } catch (_) {
      return const RaffleEnterResult(
        ok: false,
        message: '네트워크 오류로 응모하지 못했어요.',
      );
    }
  }
}

/// 디버그 전용 샘플 (프로토타입 화면 11 기준). 배포 후 아래 두 함수를 삭제할 것.
List<MileageEvent> _devEvents() {
  final now = DateTime.now();
  return [
    MileageEvent(delta: 500, reason: 'VISIT', memo: '고니식탁 방문 적립', createdAt: now),
    MileageEvent(
        delta: -500,
        reason: 'RAFFLE',
        memo: '식사권 응모',
        createdAt: now.subtract(const Duration(days: 1))),
    MileageEvent(
        delta: 300,
        reason: 'MISSION',
        memo: '미션 보상',
        createdAt: now.subtract(const Duration(days: 2))),
    MileageEvent(
        delta: 500,
        reason: 'VISIT',
        memo: '혜화문식당 방문 적립',
        createdAt: now.subtract(const Duration(days: 3))),
  ];
}

List<Raffle> _devRaffles() {
  final now = DateTime.now();
  return [
    Raffle(
        id: 1,
        title: '식사권',
        prizeAmount: 30000,
        costMileage: 500,
        restaurantName: '고니식탁',
        entriesCount: 1240,
        entered: false,
        closesAt: now.add(const Duration(days: 3))),
    Raffle(
        id: 2,
        title: '식사권',
        prizeAmount: 20000,
        costMileage: 300,
        restaurantName: '구구포차',
        entriesCount: 860,
        entered: false,
        closesAt: now.add(const Duration(days: 5))),
    Raffle(
        id: 3,
        title: '식사권',
        prizeAmount: 50000,
        costMileage: 800,
        restaurantName: '마름모식당',
        entriesCount: 2100,
        entered: false,
        closesAt: now.add(const Duration(days: 1))),
    Raffle(
        id: 4,
        title: '식사권',
        prizeAmount: 30000,
        costMileage: 500,
        restaurantName: '다이와스시',
        entriesCount: 540,
        entered: true,
        closesAt: now.add(const Duration(days: 7))),
  ];
}

/// raffle-<id>-<난수>. 한 번의 응모 시도에 대해 호출부가 키를 보관했다가
/// 재시도 시 같은 키를 넘겨야 중복 차감이 막힌다.
String generateRaffleKey(int raffleId) {
  final random = Random.secure();
  final suffix =
      List.generate(12, (_) => '0123456789abcdef'[random.nextInt(16)]).join();
  return 'raffle-$raffleId-$suffix';
}

String? _cursorFrom(dynamic next) {
  if (next is String && next.isNotEmpty) {
    return Uri.tryParse(next)?.queryParameters['cursor'];
  }
  return null;
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
