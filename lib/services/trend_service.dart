import 'dart:convert';

import 'api_client.dart';

class TrendItem {
  const TrendItem({
    required this.imageUrl,
    this.blogLink,
    this.title,
    this.description,
  });

  factory TrendItem.fromJson(Map<String, dynamic> json) {
    String? normalize(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return TrendItem(
      imageUrl: normalize(json['image_url']) ?? '',
      blogLink: normalize(json['blog_link']),
      title: normalize(json['title']),
      description: normalize(json['description']),
    );
  }

  final String imageUrl;
  final String? blogLink;
  final String? title;
  final String? description;

  bool get hasImage => imageUrl.trim().isNotEmpty;
  bool get hasBlogLink => blogLink != null && blogLink!.trim().isNotEmpty;
}

class TrendService {
  static Future<List<TrendItem>> fetchTrends() async {
    final response = await ApiClient.get('/trends/', authenticated: false)
        .timeout(const Duration(seconds: 1));
    final body = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(body);

    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final dynamic results = decoded['results'];
      if (results is List) {
        items = results;
      } else {
        items = const [];
      }
    } else {
      items = const [];
    }

    return items
        .whereType<Map>()
        .map<Map<String, dynamic>>(
          (item) => Map<String, dynamic>.from(item),
        )
        .map(TrendItem.fromJson)
        .where((item) => item.hasImage)
        .toList();
  }
}
