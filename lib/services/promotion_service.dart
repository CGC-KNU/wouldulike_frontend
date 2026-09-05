import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// 기획전 참여 항목 (스펙 6.2 items[]).
/// 식당 연결형(restaurantId)과 독립형 배너(imageUrl/linkUrl) 두 종류가 있다.
class FeaturedCampaignItem {
  const FeaturedCampaignItem({
    required this.restaurantId,
    required this.badge,
    required this.benefitTitle,
    required this.benefitSub,
    required this.imageUrl,
    required this.linkUrl,
    required this.sortOrder,
  });

  factory FeaturedCampaignItem.fromJson(Map<String, dynamic> json) {
    int? parseIntOrNull(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    int parseInt(dynamic value) => parseIntOrNull(value) ?? 0;

    final image = json['image_url']?.toString();

    return FeaturedCampaignItem(
      restaurantId: parseIntOrNull(json['restaurant_id']),
      badge: json['badge']?.toString() ?? '',
      benefitTitle: json['benefit_title']?.toString() ?? '',
      benefitSub: json['benefit_sub']?.toString() ?? '',
      imageUrl: _isSafeBannerUrl(image) ? image : null,
      linkUrl: sanitizeBannerLink(json['link_url']?.toString()),
      sortOrder: parseInt(json['sort_order']),
    );
  }

  /// null이면 식당 연결형 아이템 (기존 동작대로 restaurant 사진을 조회해서 쓴다).
  final int? restaurantId;
  final String badge;
  final String benefitTitle;
  final String benefitSub;

  /// 독립형 배너용 자체 이미지. null이면 restaurantId로 조회한 사진을 대신 쓴다.
  final String? imageUrl;

  /// 독립형 배너용 탭 링크. null이면 기존처럼 기획전 상세 화면을 연다.
  final Uri? linkUrl;
  final int sortOrder;

  bool get isStandaloneBanner => restaurantId == null;
}

/// https 스킴만 통과시킨다 (mission_service.dart의 PromoBlock 검증 패턴과 동일).
bool _isSafeBannerUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  final uri = Uri.tryParse(raw.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

/// https 링크만 통과시킨다. intent:// · javascript: 등은 null로 떨어뜨린다.
Uri? sanitizeBannerLink(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
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
