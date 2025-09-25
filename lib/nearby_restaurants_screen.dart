import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'utils/location_helper.dart';
import 'utils/distance_calculator.dart';

class NearbyRestaurantsScreen extends StatefulWidget {
  @override
  _NearbyRestaurantsScreenState createState() => _NearbyRestaurantsScreenState();
}

class _NearbyRestaurantsScreenState extends State<NearbyRestaurantsScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> restaurants = [];

  @override
  void initState() {
    super.initState();
    fetchNearbyRestaurants();
  }

  Future<void> fetchNearbyRestaurants() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foodNames = prefs.getStringList('recommended_foods') ?? [];

      final position = await LocationHelper.getLatLon();
      if (position == null) {
        throw Exception('위치 정보를 가져올 수 없습니다.');
      }

      final url = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-nearby-restaurants/';
      final body = json.encode({
        'food_names': foodNames,
        'latitude': position['lat'],
        'longitude': position['lon'],
      });

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> restList = data['restaurants'] ?? [];
        final double? userLat = position['lat'];
        final double? userLon = position['lon'];

        if (userLat == null || userLon == null) {
          throw Exception('사용자 좌표가 null입니다.');
        }

        restaurants = restList.map<Map<String, dynamic>>((r) {
          final restLat = double.tryParse(r['y']?.toString() ?? '') ?? 0.0;
          final restLon = double.tryParse(r['x']?.toString() ?? '') ?? 0.0;
          final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          return {
            'name': r['name'] ?? '이름 없음',
            'road_address': r['road_address'] ?? '주소 없음',
            'category_1': r['category_1'] ?? '카테고리 없음',
            'category_2': r['category_2'] ?? '카테고리 없음',
            'distance': distance,
          };
        }).toList();
      } else {
        throw Exception('Failed to fetch restaurants');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음식점 정보를 가져오는데 실패했습니다: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('내 주변 음식점')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('내 주변 음식점')),
      body: restaurants.isEmpty
          ? const Center(child: Text('주변에 음식점이 없습니다.'))
          : ListView.builder(
        itemCount: restaurants.length,
        itemBuilder: (context, index) {
          final r = restaurants[index];
          final distanceText = r['distance'] != null
              ? '거리: ${r['distance'].toStringAsFixed(2)} km'
              : '거리 정보 없음';
          return ListTile(
            title: Text(r['name']),
            subtitle: Text('${r['road_address']}\n$distanceText'),
          );
        },
      ),
    );
  }
}