import 'dart:convert';

import 'api_client.dart';

class AffiliateRestaurantSummary {
  const AffiliateRestaurantSummary({
    required this.id,
    required this.name,
    required this.address,
    required this.category,
    required this.zone,
    required this.phoneNumber,
    required this.url,
    required this.imageUrls,
  });

  factory AffiliateRestaurantSummary.fromJson(Map<String, dynamic> json) {
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
      address: json['address']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      phoneNumber: json['phone_number']?.toString() ?? '',
      url: json['url']?.toString(),
      imageUrls: parseImages(json['s3_image_urls']),
    );
  }

  final int id;
  final String name;
  final String address;
  final String category;
  final String zone;
  final String phoneNumber;
  final String? url;
  final List<String> imageUrls;
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
