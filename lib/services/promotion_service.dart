import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// 기획전 선별 매장 항목 (스펙 6.2 items[])
class FeaturedCampaignItem {
  const FeaturedCampaignItem({
    required this.restaurantId,
    required this.badge,
    required this.benefitTitle,
    required this.benefitSub,
    required this.sortOrder,
  });

  factory FeaturedCampaignItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return FeaturedCampaignItem(
      restaurantId: parseInt(json['restaurant_id']),
      badge: json['badge']?.toString() ?? '',
      benefitTitle: json['benefit_title']?.toString() ?? '',
      benefitSub: json['benefit_sub']?.toString() ?? '',
      sortOrder: parseInt(json['sort_order']),
    );
  }

  final int restaurantId;
  final String badge;
  final String benefitTitle;
  final String benefitSub;
  final int sortOrder;
}

/// 진행 중 기획전 (스펙 6.2 GET /api/promotions/featured/current/)
class FeaturedCampaign {
  const FeaturedCampaign({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.region,
    required this.startsAt,
    required this.endsAt,
    required this.items,
  });

  factory FeaturedCampaign.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    final items = rawItems
        .whereType<Map>()
        .map((item) =>
            FeaturedCampaignItem.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return FeaturedCampaign(
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      // 스펙 6.2 응답에는 지역명이 없어 서버 확장 필드로 둔다 (히어로 지역 라벨용).
      region: json['region']?.toString() ?? '',
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? ''),
      items: items,
    );
  }

  final String code;
  final String title;
  final String subtitle;
  final String region;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<FeaturedCampaignItem> items;

  bool get hasItems => items.isNotEmpty;

  /// 예: 2026.06.01 ~ 06.30
  String get periodLabel {
    final s = startsAt;
    final e = endsAt;
    String two(int v) => v.toString().padLeft(2, '0');
    if (s == null || e == null) return '';
    final start = '${s.year}.${two(s.month)}.${two(s.day)}';
    final end = s.year == e.year
        ? '${two(e.month)}.${two(e.day)}'
        : '${e.year}.${two(e.month)}.${two(e.day)}';
    return '$start ~ $end';
  }
}

class PromotionService {
  static Future<FeaturedCampaign?> fetchCurrentFeatured({String? zone}) async {
    try {
      final response = await ApiClient.get(
        '/api/promotions/featured/current/',
        authenticated: false,
        queryParameters: {if (zone != null && zone.isNotEmpty) 'zone': zone},
      );
      final body = utf8.decode(response.bodyBytes).trim();
      if (response.statusCode == 204 || body.isEmpty) return null;
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded.isEmpty) return null;
      final campaign = FeaturedCampaign.fromJson(decoded);
      return campaign.hasItems ? campaign : null;
    } catch (e) {
      // ponytail: API 미배포 상태라 실패 시 스펙 6.2 예시 기반 mock 폴백.
      // 배포 후에는 404를 "진행 중 기획전 없음"(null)으로 바꾸고 mock 제거.
      debugPrint('featured campaign API unavailable, using mock: $e');
      return FeaturedCampaign.fromJson(_mockFeaturedJson);
    }
  }

  /// 스펙 6.2 응답 예시 + 프로토타입 FEAT 배열(식당 62·74·305) 기반 mock.
  static const Map<String, dynamic> _mockFeaturedJson = <String, dynamic>{
    'code': '2026-06-knu-north',
    'title': '6월 기획전 특집',
    'subtitle': '이번 달은 딱 3곳만.\n우주라이크가 고른 매장에서만 열리는 한정 혜택이에요.',
    'region': '경북대 북문',
    'starts_at': '2026-06-01T00:00:00+09:00',
    'ends_at': '2026-06-30T23:59:59+09:00',
    'items': <Map<String, dynamic>>[
      {
        'restaurant_id': 62,
        'badge': '우주라이크 PICK',
        'benefit_title': '기획전 한정 3,000원 쿠폰',
        'benefit_sub': '6월 한 달간 방문 시 바로 사용 가능해요',
        'sort_order': 0,
      },
      {
        'restaurant_id': 74,
        'badge': '스탬프 2배',
        'benefit_title': '방문 스탬프 2배 적립',
        'benefit_sub': '기획전 기간에만 두 배로 쌓여요',
        'sort_order': 1,
      },
      {
        'restaurant_id': 305,
        'badge': '첫 방문 혜택',
        'benefit_title': '첫 방문 시 음료 무료 증정',
        'benefit_sub': '기획전 참여 매장 단독 혜택이에요',
        'sort_order': 2,
      },
    ],
  };
}
