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

  bool get hasRequiredFields =>
      id > 0 && imageUrl.isNotEmpty && instagramUrl.isNotEmpty;

  bool isVisibleAt(DateTime now) {
    if (!isActive) return false;
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }
}

class PopupService {
  static const String listEndpoint = '/trends/popup_campaigns/';
  static String detailEndpoint(int id) => '/trends/popup_campaigns/$id/';

  static Future<List<HomePopupItem>> fetchVisiblePopups() async {
    final now = DateTime.now();
    final response = await ApiClient.get(listEndpoint, authenticated: false);
    final text = utf8.decode(response.bodyBytes).trimLeft();
    if (text.isEmpty || text.startsWith('<')) {
      return const <HomePopupItem>[];
    }
    final dynamic decoded = jsonDecode(text);
    final List<HomePopupItem> parsed = _parseItems(decoded);

    final visible = parsed
        .where((item) => item.hasRequiredFields && item.isVisibleAt(now))
        .toList();

    return visible;
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
