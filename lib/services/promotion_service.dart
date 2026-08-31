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
      startsAt: _parseDate(json['starts_at']),
      endsAt: _parseDate(json['ends_at']),
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
    final s = startsAt?.toLocal();
    final e = endsAt?.toLocal();
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
      final response = await ApiClient.getWithoutThrow(
        '/api/promotions/featured/current/',
        authenticated: false,
        queryParameters: {if (zone != null && zone.isNotEmpty) 'zone': zone},
      );
      if (response.statusCode >= 400) return null;
      final body = utf8.decode(response.bodyBytes).trim();
      if (response.statusCode == 204 || body.isEmpty) return null;
      final decoded = jsonDecode(body);
      final campaignJson = _campaignMap(decoded);
      if (campaignJson == null) return null;
      final campaign = FeaturedCampaign.fromJson(campaignJson);
      return campaign.hasItems ? campaign : null;
    } catch (e) {
      // 기획전은 부가 정보이므로 실패 시 배너를 아예 숨긴다.
      debugPrint('featured campaign API unavailable: $e');
      return null;
    }
  }
}

Map<String, dynamic>? _campaignMap(dynamic decoded) {
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  final results = map['results'];
  if (results is List) {
    for (final item in results) {
      if (item is! Map) continue;
      final campaign = Map<String, dynamic>.from(item);
      final items = campaign['items'];
      if (items is List && items.isNotEmpty) return campaign;
    }
    return null;
  }
  final nested = map['campaign'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  if (map['items'] is List ||
      (map['code']?.toString().trim().isNotEmpty ?? false)) {
    return map;
  }
  return null;
}

DateTime? _parseDate(dynamic raw) {
  if (raw is DateTime) return raw;
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text) ??
      DateTime.tryParse(text.replaceFirst(' ', 'T'));
}
