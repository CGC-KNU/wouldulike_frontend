import 'dart:convert';

import 'api_client.dart';

class HomePopupItem {
  const HomePopupItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.instagramUrl,
    required this.startAt,
    required this.endAt,
    required this.isActive,
    required this.displayOrder,
    required this.createdAt,
  });

  factory HomePopupItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    String normalize(dynamic value) => value?.toString().trim() ?? '';

    return HomePopupItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? -1,
      title: normalize(json['title']),
      imageUrl: normalize(json['image_url']),
      instagramUrl: normalize(json['instagram_url']),
      startAt: parseDate(json['start_at']),
      endAt: parseDate(json['end_at']),
      isActive: json['is_active'] == true,
      displayOrder: int.tryParse(json['display_order']?.toString() ?? '') ?? 999999,
      createdAt: parseDate(json['created_at']),
    );
  }

  final int id;
  final String title;
  final String imageUrl;
  final String instagramUrl;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isActive;
  final int displayOrder;
  final DateTime? createdAt;

  /// 그릴 수 있는 최소 조건. 링크는 없어도 이미지만 있으면 노출한다.
  bool get isRenderable => id > 0 && imageUrl.isNotEmpty;

  /// 링크가 있을 때만 탭이 동작한다.
  bool get hasLink => instagramUrl.isNotEmpty;
}

class PopupService {
  static const String listEndpoint = '/trends/popup_campaigns/';
  static String detailEndpoint(int id) => '/trends/popup_campaigns/$id/';

  /// 활성 여부·노출 기간·정렬은 **서버가 이미 처리해서** 내려준다.
  /// 여기서 기기 시각으로 다시 거르면, 기기 시계가 틀어졌을 때 멀쩡한 배너가
  /// 조용히 사라진다. 순서도 그대로 쓴다 (display_order는 서버 정렬 기준).
  static Future<List<HomePopupItem>> fetchVisiblePopups() async {
    final response = await ApiClient.get(listEndpoint, authenticated: false);
    final text = utf8.decode(response.bodyBytes).trimLeft();
    if (text.isEmpty || text.startsWith('<')) {
      return const <HomePopupItem>[];
    }
    final dynamic decoded = jsonDecode(text);
    final List<HomePopupItem> parsed = _parseItems(decoded);

    return parsed.where((item) => item.isRenderable).toList();
  }

  static List<HomePopupItem> _parseItems(dynamic decoded) {
    final List<dynamic> rawItems;
    if (decoded is List) {
      rawItems = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final dynamic results = decoded['results'] ?? decoded['data'] ?? decoded['items'];
      if (results is List) {
        rawItems = results;
      } else {
        rawItems = const <dynamic>[];
      }
    } else {
      rawItems = const <dynamic>[];
    }

    return rawItems
        .whereType<Map>()
        .map((raw) => HomePopupItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
  }
}
