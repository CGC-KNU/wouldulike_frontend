import 'dart:convert';

import 'api_client.dart';

class AffiliateRestaurantSummary {
  const AffiliateRestaurantSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.category,
    required this.zone,
    required this.phoneNumber,
    required this.url,
    required this.imageUrls,
    required this.stampCurrent,
    required this.stampTarget,
  });

  factory AffiliateRestaurantSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) {
        return int.tryParse(value) ?? 0;
      }
      return 0;
    }

    int parseStampCurrent() {
      if (json['stamp_current'] != null) {
        return parseInt(json['stamp_current']);
      }
      final dynamic status = json['stamp_status'];
      if (status is Map<String, dynamic>) {
        return parseInt(status['current']);
      }
      return 0;
    }

    int parseStampTarget() {
      if (json['stamp_target'] != null) {
        return parseInt(json['stamp_target']);
      }
      final dynamic status = json['stamp_status'];
      if (status is Map<String, dynamic>) {
        return parseInt(status['target']);
      }
      return 0;
    }

    List<String> parseImages(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item?.toString() ?? '')
            .where((item) => item.isNotEmpty)
            .toList();
      }
      return const [];
    }

    return AffiliateRestaurantSummary(
      id: json['restaurant_id'] is int
          ? json['restaurant_id'] as int
          : int.tryParse(json['restaurant_id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      url: json['url']?.toString(),
      imageUrls: parseImages(json['s3_image_urls']),
      stampCurrent: parseStampCurrent(),
      stampTarget: parseStampTarget(),
    );
  }

  final int id;
  final String name;
  final String description;
  final String address;
  final String category;
  final String zone;
  final String phoneNumber;
  final String? url;
  final List<String> imageUrls;
  final int stampCurrent;
  final int stampTarget;
}

class AffiliateService {
  static Future<List<AffiliateRestaurantSummary>> fetchRestaurants() async {
    final response = await ApiClient.get('/restaurants/affiliate-restaurants/',
        authenticated: false);
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> list =
        data['restaurants'] as List<dynamic>? ?? const [];
    return list
        .map(
          (item) => AffiliateRestaurantSummary.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  static Future<AffiliateRestaurantSummary?> fetchRestaurantByName(
      String name) async {
    if (name.isEmpty) return null;
    final response = await ApiClient.get(
      '/restaurants/affiliate-restaurants/detail/',
      authenticated: false,
      queryParameters: {'name': name},
    );
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['restaurant'] is Map<String, dynamic>) {
      return AffiliateRestaurantSummary.fromJson(
        Map<String, dynamic>.from(data['restaurant'] as Map),
      );
    }
    return null;
  }
}
