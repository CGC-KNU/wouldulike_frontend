import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:new1/main2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
class FoodRecommendationScreen extends StatefulWidget {
  final String resultMessage;

  const FoodRecommendationScreen({super.key, required this.resultMessage});

  @override
  State<FoodRecommendationScreen> createState() => _FoodRecommendationScreenState();
}

class _FoodRecommendationScreenState extends State<FoodRecommendationScreen> {
  List<Map<String, dynamic>> recommendedFoods = [];
  bool isLoading = true;
  final pageController = PageController();
  late String typeLabel;
  List<Map<String, dynamic>> restaurants = [];
  List<Map<String, dynamic>> recommendedRestaurants = [];
  @override
  void initState() {
    super.initState();
    //print('Received resultMessage: ${widget.resultMessage}');
    typeLabel = getTypeLabel(widget.resultMessage);

    fetchRecommendedData();
  }
  Future<void> fetchRecommendedData() async {
    await fetchRecommendedFoods(); // 음식 데이터를 먼저 가져옴
    await fetchRestaurants();      // 이후 음식점을 가져옴
  }
  //타입에 맞는 음식점 가져오기
  Future<void> fetchRestaurants() async {
    try {
      //print('[DEBUG] Starting fetchRestaurants');

      // SharedPreferences 인스턴스 가져오기
      final prefs = await SharedPreferences.getInstance();
      //print('[DEBUG] SharedPreferences instance obtained.');

      // 추천 음식 목록 가져오기
      final foodNames = prefs.getStringList('recommended_foods') ?? [];
      //print('[DEBUG] Food names from SharedPreferences: $foodNames');

      if (foodNames.isEmpty) {
        throw Exception('No recommended food names found');
      }

      // API URL 및 요청 데이터 확인
      final url = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/';
      final body = json.encode({
        'food_names': foodNames,
      });
      //print('[DEBUG] Request URL: $url');
      //print('[DEBUG] Request body: $body');

      // API 호출
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: body,
      );
      //print('[DEBUG] Response status code: ${response.statusCode}');
      //print('[DEBUG] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        //print('[DEBUG] Decoded response data: $responseData');

        // 반환된 음식점 데이터 가져오기
        final List<dynamic> restaurants = responseData['random_restaurants'] ?? [];
        //print('[DEBUG] Extracted restaurants: $restaurants');

        // SharedPreferences에 저장
        await prefs.setString('restaurants_data', json.encode(restaurants));
        //print('[DEBUG] Restaurants data saved to SharedPreferences.');

        if (!mounted) return;

        // 상태 업데이트
        setState(() {
          recommendedRestaurants = restaurants.map((restaurant) => {
          'name': restaurant['name'] ?? '이름 없음',
          'road_address': restaurant['road_address'] ?? '주소 없음',
          'category_2': restaurant['category_2'] ?? '카테고리 없음',
          'category_1': restaurant['category_1'] ?? '카테고리 없음',
          }).toList();
          isLoading = false;
        });
        //print('[DEBUG] recommendedRestaurants updated in state: $recommendedRestaurants');
      } else {
        throw Exception('Failed to fetch restaurants');
      }
    } catch (e) {
      print('[ERROR] Fetch restaurants failed: $e');

      if (!mounted) return;

      // 로딩 상태 해제 및 에러 메시지 표시
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('음식점 정보를 가져오는데 실패했습니다: ${e.toString()}')),
      );
    }
  }
  //타입에 맞는 음식 3가지 가져오기
  Future<void> fetchRecommendedFoods() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userUuid = prefs.getString('user_uuid') ?? '';

      if (userUuid.isEmpty) {
        throw Exception('User UUID not found');
      }

      final url = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/random-foods/?uuid=$userUuid';
      final response = await http.get(Uri.parse(url));

      //디버깅
      //print('URL: ${url}');
      //print('Response status code: ${response.statusCode}');
      //print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> foods = responseData['random_foods'];
        //print('foods: $foods');

        // SharedPreferences에 새로운 음식 이름들만 저장
        List<String> newFoodNames = foods
            .map((food) => food['food_name'].toString())
            .toList();
        await prefs.setStringList('recommended_foods', newFoodNames);
        //print('Saved new food names: $newFoodNames');

        List<Map<String, dynamic>> foodInfoList = foods.map((food) => {
          'food_name': food['food_name'],
          'food_image_url': food['food_image_url'],
        }).toList();
        await prefs.setString('recommended_foods_info', json.encode(foodInfoList));
        //print('Saved foodInfoList: $foodInfoList');
        if (!mounted) return;

        setState(() {
          recommendedFoods = foods.map((food) => {
            'title': food['food_name'] ?? '이름 없음',
            'description': food['description'] ?? '설명 없음',
            'image' : food['food_image_url'] ?? 'assets/images/food_image0.png',
          }).toList();
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load foods');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음식 추천을 가져오는데 실패했습니다: ${e.toString()}')),
        );
      }
    }
  }
  String getTypeLabel(String resultMessage) {
    if (resultMessage == 'IYFW') return '강렬한';
    else if (resultMessage == 'IYFE') return '활발한';
    else if (resultMessage == 'IYJW') return '자유로운';
    else if (resultMessage == 'IYJE') return '섬세한';
    else if (resultMessage == 'INFW') return '독립적인';
    else if (resultMessage == 'INFE') return '여유로운';
    else if (resultMessage == 'INJW') return '신중한';
    else if (resultMessage == 'INJE') return '감각적인';
    else if (resultMessage == 'SYFW') return '부드러운';
    else if (resultMessage == 'SYFE') return '온화한';
    else if (resultMessage == 'SYJW') return '안정적인';
    else if (resultMessage == 'SYJE') return '따뜻한';
    else if (resultMessage == 'SNFW') return '직관적인';
    else if (resultMessage == 'SNFE') return '실용적인';
    else if (resultMessage == 'SNJW') return '차분한';
    else if (resultMessage == 'SNJE') return '정돈된';
    else return '알 수 없음';
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
                  "${typeLabel} ${widget.resultMessage} 유형",
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: size.width * 0.055,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "입맛 유형을 기반으로 오늘의 메뉴를 추천해드립니다.",
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
                        // 이미지
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: food["image"]!.startsWith('http')
                              ? Image.network(
                            food["image"]!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child,
                                loadingProgress) {
                              if (loadingProgress == null) {
                                return child;
                              }
                              return Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress
                                      .expectedTotalBytes !=
                                      null
                                      ? loadingProgress
                                      .cumulativeBytesLoaded /
                                      loadingProgress
                                          .expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder:
                                (context, error, stackTrace) {
                              return Image.asset(
                                'assets/images/food_image0.png',
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              );
                            },
                          )
                              : Image.asset(
                            food["image"]!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // 그라데이션 오버레이
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
                        // 텍스트 내용
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                food["title"]!,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: size.width * 0.055,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                food["description"]!,
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
                  "홈으로 가기",
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