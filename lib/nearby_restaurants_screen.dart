import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'utils/location_helper.dart';
import 'utils/distance_calculator.dart';

class NearbyRestaurantsScreen extends StatefulWidget {
  const NearbyRestaurantsScreen({super.key});

  @override
  State<NearbyRestaurantsScreen> createState() => _NearbyRestaurantsScreenState();
}

class _NearbyRestaurantsScreenState extends State<NearbyRestaurantsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _restaurants = [];

  @override
  void initState() {
    super.initState();
    fetchNearbyRestaurants();
  }

  Future<void> fetchNearbyRestaurants() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final prefs = await SharedPreferences.getInstance();
      final foodNames = prefs.getStringList('recommended_foods') ?? [];

      final position = await LocationHelper.getLatLon();
      if (position == null) {
        throw Exception('위치 정보를 가져올 수 없습니다.');
      }

      final response = await http.post(
        Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-nearby-restaurants/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'food_names': foodNames,
          'latitude': position['lat'],
          'longitude': position['lon'],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final restList = (data['restaurants'] as List<dynamic>? ?? const [])
            .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        final userLat = position['lat'] as double;
        final userLon = position['lon'] as double;

        _restaurants = restList.map<Map<String, dynamic>>((r) {
          final restLat = double.tryParse(r['y']?.toString() ?? '') ?? userLat;
          final restLon = double.tryParse(r['x']?.toString() ?? '') ?? userLon;
          final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          return {
            'name': r['name'] ?? '이름 없음',
            'road_address': r['road_address'] ?? '주소 정보 없음',
            'category_1': r['category_1'] ?? '카테고리 정보 없음',
            'category_2': r['category_2'] ?? '카테고리 정보 없음',
            'distance': distance,
          };
        }).toList();
      } else {
        throw Exception('음식점 정보를 불러오지 못했어요.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restaurants = [];
        _errorMessage = '음식점 정보를 불러오지 못했어요: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('주변 맛집'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: fetchNearbyRestaurants,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_restaurants.isEmpty) {
      return const Center(child: Text('주변 맛집이 없습니다.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _restaurants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final restaurant = _restaurants[index];
        final distance = restaurant['distance'];
        final distanceText = distance is num
            ? '거리: ${distance.toStringAsFixed(2)} km'
            : '거리 정보 없음';

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            title: Text(restaurant['name'] ?? '이름 없음'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  restaurant['road_address'] ?? '주소 정보 없음',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 4),
                Text(
                  distanceText,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 4),
                Text(
                  restaurant['category_2'] ?? '카테고리 정보 없음',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
