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

/// 지갑 배지 수치 (GET /api/wallet/overview/)
class WalletOverview {
  const WalletOverview({
    required this.mileage,
    required this.usableCoupons,
    required this.expiringSoon,
    required this.activeStampStores,
  });

  factory WalletOverview.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final raw = json[key];
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    }

    final mileage = section('mileage');
    final coupons = section('coupons');
    final stamps = section('stamps');
    return WalletOverview(
      mileage: MileageSummary(
        balance: _asInt(mileage['balance']),
        monthEarned: _asInt(mileage['month_earned']),
      ),
      usableCoupons: _asInt(coupons['usable']),
      expiringSoon: _asInt(coupons['expiring_soon']),
      activeStampStores: _asInt(stamps['active_stores']),
    );
  }

  final MileageSummary mileage;
  final int usableCoupons;
  final int expiringSoon;
  final int activeStampStores;
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
      case 'STAMP_VISIT':
        return '방문 적립';
      case 'COUPON_USE':
        return '쿠폰 사용 적립';
      case 'MISSION':
        return '미션 보상';
      case 'RAFFLE':
        return '응모 차감';
      case 'COUPON_EXCHANGE':
        return '쿠폰 교환 사용';
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
    this.myTickets = 0,
    this.allStores = true,
    this.closesAt,
  });

  factory Raffle.fromJson(Map<String, dynamic> json) {
    final myTickets = _asInt(json['my_tickets']);
    return Raffle(
      id: _asInt(json['id']),
      title: json['title']?.toString() ?? '식사권',
      prizeAmount: _asInt(json['prize_amount']),
      costMileage: _asInt(json['cost_mileage']),
      restaurantName: json['restaurant_name']?.toString() ?? '',
      entriesCount: _asInt(json['entries_count']),
      entered: json['entered'] == true || myTickets > 0,
      myTickets: myTickets,
      // 서버가 all_stores를 안 주는 구버전이면 매장명 유무로 판단한다.
      allStores: json['all_stores'] == true ||
          (json['all_stores'] == null && json['restaurant_id'] == null),
      closesAt: _asDate(json['closes_at']),
    );
  }

  final int id;
  final String title;
  final int prizeAmount;
  final int costMileage;
  final String restaurantName;
  final int entriesCount;

  /// 내가 이 대회에 1장 이상 응모했는지. 서버가 my_tickets를 안 주는 구버전과도
  /// 호환되도록 남겨 둔다 (그때는 정확한 장수 대신 이 불리언만 참고).
  final bool entered;

  /// 내가 이 대회에 산 티켓 장수. 0이면 아직 응모 전.
  final int myTickets;

  /// 전 매장에서 쓸 수 있는 식사권인지 (마일리지는 매장 구분 없이 사용)
  final bool allStores;
  final DateTime? closesAt;

  Raffle copyWith({
    int? entriesCount,
    bool? entered,
    int? myTickets,
  }) {
    return Raffle(
      id: id,
      title: title,
      prizeAmount: prizeAmount,
      costMileage: costMileage,
      restaurantName: restaurantName,
      entriesCount: entriesCount ?? this.entriesCount,
      entered: entered ?? this.entered,
      myTickets: myTickets ?? this.myTickets,
      allStores: allStores,
      closesAt: closesAt,
    );
  }
}

/// 내 응모 1건 (GET /api/raffles/my/)
class MyRaffleEntry {
  const MyRaffleEntry({
    required this.raffleId,
    required this.title,
    required this.prizeAmount,
    required this.costMileage,
    required this.status,
    required this.won,
    required this.allStores,
    this.closesAt,
    this.createdAt,
  });

  factory MyRaffleEntry.fromJson(Map<String, dynamic> json) {
    return MyRaffleEntry(
      raffleId: _asInt(json['raffle_id']),
      title: json['title']?.toString() ?? '식사권',
      prizeAmount: _asInt(json['prize_amount']),
      costMileage: _asInt(json['cost_mileage']),
      status: json['status']?.toString() ?? 'OPEN',
      won: json['won'] == true,
      allStores: json['all_stores'] != false,
      closesAt: _asDate(json['closes_at']),
      createdAt: _asDate(json['created_at']),
    );
  }

  final int raffleId;
  final String title;
  final int prizeAmount;
  final int costMileage;

  /// OPEN(진행중) · CLOSED(마감) · DRAWN(추첨완료)
  final String status;
  final bool won;
  final bool allStores;
  final DateTime? closesAt;
  final DateTime? createdAt;

  /// 추첨 전이면 결과를 확정 표기하지 않는다.
  String get resultLabel {
    if (status != 'DRAWN') return '추첨 대기';
    return won ? '당첨' : '미당첨';
  }
}

/// 아직 확인하지 않은 당첨 팝업 (GET /api/raffles/win-popups/)
class RaffleWinPopup {
  const RaffleWinPopup({
    required this.id,
    required this.raffleId,
    required this.title,
    required this.prizeAmount,
    this.won = true,
  });

  factory RaffleWinPopup.fromJson(Map<String, dynamic> json) {
    return RaffleWinPopup(
      id: _asInt(json['id'] ?? json['popup_id']),
      raffleId: _asInt(json['raffle_id']),
      title: json['title']?.toString() ?? '식사권',
      prizeAmount: _asInt(json['prize_amount']),
      won: json['won'] != false,
    );
  }

  final int id;
  final int raffleId;
  final String title;
  final int prizeAmount;
  final bool won;
}

/// 당첨자 발표 1건 (GET /api/raffles/winners/)
class RaffleWinner {
  const RaffleWinner({
    required this.raffleId,
    required this.title,
    required this.prizeAmount,
    required this.costMileage,
    required this.entriesCount,
    required this.winnerNickname,
    required this.allStores,
    required this.restaurantName,
    this.drawnAt,
  });

  factory RaffleWinner.fromJson(Map<String, dynamic> json) {
    return RaffleWinner(
      raffleId: _asInt(json['raffle_id']),
      title: json['title']?.toString() ?? '식사권',
      prizeAmount: _asInt(json['prize_amount']),
      costMileage: _asInt(json['cost_mileage']),
      entriesCount: _asInt(json['entries_count']),
      winnerNickname: json['winner_nickname']?.toString() ?? '당첨자 미정',
      allStores: json['all_stores'] != false,
      restaurantName: json['restaurant_name']?.toString() ?? '',
      drawnAt: _asDate(json['drawn_at']),
    );
  }

  final int raffleId;
  final String title;
  final int prizeAmount;
  final int costMileage;
  final int entriesCount;

  /// 서버가 첫 글자만 남기고 마스킹해 내려주는 닉네임
  final String winnerNickname;
  final bool allStores;
  final String restaurantName;
  final DateTime? drawnAt;
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
      if (!await ApiClient.hasAccessToken()) return null;
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

  /// 지갑 진입 시 탭 배지 수치 일괄 조회. 미배포면 null이라 배지를 숨긴다.
  static Future<WalletOverview?> fetchWalletOverview() async {
    try {
      if (!await ApiClient.hasAccessToken()) return null;
      final response = await ApiClient.get('/api/wallet/overview/')
          .timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      if (decoded is Map<String, dynamic>) {
        return WalletOverview.fromJson(decoded);
      }
    } catch (_) {}
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

  static Future<List<MyRaffleEntry>> fetchMyEntries() async {
    try {
      final response = await ApiClient.get('/api/raffles/my/')
          .timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      final raw = decoded is Map<String, dynamic> ? decoded['results'] : decoded;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => MyRaffleEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    if (kDebugMode) return _devMyEntries();
    return const [];
  }

  static Future<List<RaffleWinPopup>> fetchUnseenWinPopups() async {
    try {
      final response = await ApiClient.get('/api/raffles/win-popups/')
          .timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      final raw = decoded is Map<String, dynamic> ? decoded['results'] : decoded;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => RaffleWinPopup.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.id > 0)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> markWinPopupsSeen(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      await ApiClient.post(
        '/api/raffles/win-popups/',
        body: {'ids': ids},
      );
    } catch (e) {
      debugPrint('[Raffle] mark win popups failed: $e');
    }
  }
  static Future<List<RaffleWinner>> fetchWinners() async {
    try {
      final response = await ApiClient.get('/api/raffles/winners/')
          .timeout(const Duration(seconds: 8));
      final decoded = _decode(response);
      final raw = decoded is Map<String, dynamic> ? decoded['results'] : decoded;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => RaffleWinner.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    if (kDebugMode) return _devWinners();
    return const [];
  }

  /// 응모. 재시도 시 중복 차감을 막기 위해 멱등 키를 항상 보낸다 (스펙 6.2).
  /// quantity로 한 번에 여러 장 응모할 수 있다 (기본 1장).
  static Future<RaffleEnterResult> enterRaffle(
    int raffleId, {
    String? idempotencyKey,
    int quantity = 1,
  }) async {
    try {
      final response = await ApiClient.postWithoutThrow(
        '/api/raffles/$raffleId/enter/',
        body: {
          'idempotency_key': idempotencyKey ?? generateRaffleKey(raffleId),
          'quantity': quantity,
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
        prizeAmount: 5000,
        costMileage: 500,
        restaurantName: '',
        entriesCount: 1240,
        entered: false,
        closesAt: now.add(const Duration(days: 3))),
    Raffle(
        id: 2,
        title: '식사권',
        prizeAmount: 10000,
        costMileage: 1000,
        restaurantName: '',
        entriesCount: 860,
        entered: false,
        closesAt: now.add(const Duration(days: 3))),
  ];
}

List<MyRaffleEntry> _devMyEntries() {
  final now = DateTime.now();
  return [
    MyRaffleEntry(
        raffleId: 91,
        title: '식사권',
        prizeAmount: 10000,
        costMileage: 1000,
        status: 'DRAWN',
        won: true,
        allStores: true,
        closesAt: now.subtract(const Duration(days: 4)),
        createdAt: now.subtract(const Duration(days: 7))),
    MyRaffleEntry(
        raffleId: 90,
        title: '식사권',
        prizeAmount: 5000,
        costMileage: 500,
        status: 'DRAWN',
        won: false,
        allStores: true,
        closesAt: now.subtract(const Duration(days: 11)),
        createdAt: now.subtract(const Duration(days: 14))),
    MyRaffleEntry(
        raffleId: 1,
        title: '식사권',
        prizeAmount: 5000,
        costMileage: 500,
        status: 'OPEN',
        won: false,
        allStores: true,
        closesAt: now.add(const Duration(days: 3)),
        createdAt: now.subtract(const Duration(days: 1))),
  ];
}

List<RaffleWinner> _devWinners() {
  final now = DateTime.now();
  return [
    RaffleWinner(
        raffleId: 91,
        title: '식사권',
        prizeAmount: 10000,
        costMileage: 1000,
        entriesCount: 934,
        winnerNickname: '김**',
        allStores: true,
        restaurantName: '',
        drawnAt: now.subtract(const Duration(days: 4))),
    RaffleWinner(
        raffleId: 90,
        title: '식사권',
        prizeAmount: 5000,
        costMileage: 500,
        entriesCount: 1187,
        winnerNickname: '이**',
        allStores: true,
        restaurantName: '',
        drawnAt: now.subtract(const Duration(days: 11))),
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
