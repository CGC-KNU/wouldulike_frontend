import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:new1/main2.dart';
import 'package:new1/utils/distance_calculator.dart';
import 'package:new1/utils/location_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class FoodRecommendationScreen extends StatefulWidget {
  const FoodRecommendationScreen({super.key});

  @override
  State<FoodRecommendationScreen> createState() => _FoodRecommendationScreenState();
}

class _FoodRecommendationScreenState extends State<FoodRecommendationScreen> {
  List<Map<String, dynamic>> recommendedFoods = [];
  bool isLoading = true;
  final pageController = PageController();
  List<Map<String, dynamic>> recommendedRestaurants = [];

  @override
  void initState() {
    super.initState();
    fetchRecommendedData();
  }

  Future<void> fetchRecommendedData() async {
    await fetchRecommendedFoods();
    await fetchRestaurants();
  }

  Future<void> fetchRestaurants() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foodNames = prefs.getStringList('recommended_foods') ?? [];

      if (foodNames.isEmpty) {
        throw Exception('추천 음식 이름을 찾을 수 없습니다.');
      }

      final position = await LocationHelper.getLatLon();
      if (position == null) {
        print('[WARN] 위치 정보 없음. 기본 위치 없이 요청합니다.');
      }

      final url =
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/';
      final body = json.encode({
        'food_names': foodNames,
        if (position != null) ...{
          'lat': position['lat'],
          'lon': position['lon'],
        },
      });

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final List<dynamic> restaurants = responseData['random_restaurants'] ?? [];

        await prefs.setString('restaurants_data', json.encode(restaurants));

        if (!mounted) return;

        if (position != null) {
          final double userLat = position['lat'] ?? 0.0;
          final double userLon = position['lon'] ?? 0.0;

          for (var restaurant in restaurants) {
            if (restaurant['x'] != null && restaurant['y'] != null) {
              final double restLon = double.tryParse(restaurant['x'].toString()) ?? 0;
              final double restLat = double.tryParse(restaurant['y'].toString()) ?? 0;

              final distance =
              DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
              restaurant['distance'] = distance;

              print('📍 ${restaurant['name']}까지 거리: ${distance.toStringAsFixed(2)} km');
            } else {
              restaurant['distance'] = null;
            }
          }
        }

        setState(() {
          recommendedRestaurants = restaurants
              .map((restaurant) => {
            'name': restaurant['name'] ?? '이름 없음',
            'road_address': restaurant['road_address'] ?? '주소 없음',
            'category_2': restaurant['category_2'] ?? '카테고리 없음',
            'category_1': restaurant['category_1'] ?? '카테고리 없음',
          })
              .toList();
          isLoading = false;
        });
      } else {
        throw Exception('음식점 정보를 불러오지 못했습니다.');
      }
    } catch (e) {
      print('[ERROR] Fetch restaurants failed: $e');

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('음식점 정보를 가져오는 데 실패했습니다: ${e.toString()}')),
      );
    }
  }

  Future<void> fetchRecommendedFoods() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUuid = prefs.getString('user_uuid') ?? '';
      if (userUuid.isEmpty) {
        throw Exception('User UUID is missing.');
      }

      final url =
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/random-foods/?uuid=$userUuid';
      http.Response response;
      int retry = 0;
      int delay = 1;
      do {
        response = await http.get(Uri.parse(url));
        if (response.statusCode == 200 ||
            response.statusCode == 400 ||
            response.statusCode == 404) {
          break;
        }
        await Future.delayed(Duration(seconds: delay));
        delay *= 2;
        retry++;
      } while (retry < 3);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> foods = responseData['random_foods'] ?? [];

        final List<String> newFoodNames =
            foods.map((food) => food['food_name'].toString()).toList();
        await prefs.setStringList('recommended_foods', newFoodNames);

        final List<Map<String, dynamic>> foodInfoList = foods
            .map((food) => {
                  'food_name': food['food_name'],
                  'food_image_url': food['food_image_url'],
                })
            .toList();
        await prefs.setString(
          'recommended_foods_info',
          json.encode(foodInfoList),
        );

        if (!mounted) return;

        setState(() {
          recommendedFoods = foods
              .map((food) => {
                    'title': food['food_name'] ?? '?? ??',
                    'description': food['description'] ?? '?? ??',
                    'image': food['food_image_url'] ?? 'assets/images/food_image0.png',
                  })
              .toList();
          isLoading = false;
        });
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('추천 음식을 불러오지 못했어요.')),
          );
        }
        setState(() {
          isLoading = false;
        });
      } else {
        throw Exception('Failed to fetch recommended foods.');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load food recommendations: ${e.toString()}',
          ),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: screenHeight * 0.1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '오늘의 메뉴 추천',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: size.width * 0.055,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '지금 추천되는 메뉴를 확인해 보세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: size.width * 0.032,
                    color: Colors.grey,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : recommendedFoods.isEmpty
                ? const Center(child: Text('추천 음식이 없습니다.'))
                : PageView.builder(
              controller: pageController,
              itemCount: recommendedFoods.length,
              itemBuilder: (context, index) {
                final food = recommendedFoods[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: food['image']!.startsWith('http')
                              ? Image.network(
                            food['image']!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder:
                                (context, child, loadingProgress) {
                              if (loadingProgress == null) {
                                return child;
                              }
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                      null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset(
                                'assets/images/food_image0.png',
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              );
                            },
                          )
                              : Image.asset(
                            food['image']!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: size.height * 0.25,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                food['title']!,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: size.width * 0.055,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                food['description']!,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: size.width * 0.035,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Center(
              child: SmoothPageIndicator(
                controller: pageController,
                count: recommendedFoods.length,
                effect: const WormEffect(
                  dotColor: Colors.grey,
                  activeDotColor: Color(0xFF312E81),
                  dotHeight: 8,
                  dotWidth: 8,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => MainAppScreen()),
                        (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF312E81),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '홈으로 가기',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
