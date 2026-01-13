import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';
import 'package:new1/utils/user_type_helper.dart';

class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key});
  @override
  _MatchingScreenState createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> with SingleTickerProviderStateMixin {

  static const int FETCH_THRESHOLD = 3; // 몇 장 남기고 미리 불러올지
  bool isFetching = false;              // 중복 요청 방지용 플래그

  List<Map<String, dynamic>> recommendedFoods = [];
  Map<String, List<Map<String, dynamic>>> foodToRestaurants = {};
  bool isLoading = true;
  bool isBack = false;
  late AnimationController _controller;
  late Animation<double> _animation;
  int currentFoodIndex = 0;
  final PageController pageController = PageController();
  static const String _matchingFoodCacheKey = 'matching_foods_cache';
  static const String _fallbackDescription =
      '취향 데이터를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';

  List<Map<String, dynamic>> _buildDefaultFallbackFoods() {
    return [
      {
        'title': '추천 메뉴가 준비 중이에요',
        'description': _fallbackDescription,
        'image': 'assets/images/food_image0.png',
      },
    ];
  }

  List<Map<String, dynamic>> _loadFallbackFoods(SharedPreferences prefs) {
    final cachedJson = prefs.getString(_matchingFoodCacheKey);
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is List) {
          final normalized = <Map<String, dynamic>>[];
          for (final element in decoded) {
            if (element is Map) {
              final title = element['title']?.toString() ?? '';
              final description =
                  element['description']?.toString() ?? _fallbackDescription;
              final image =
                  element['image']?.toString() ?? 'assets/images/food_image0.png';
              if (title.trim().isEmpty) continue;
              normalized.add({
                'title': title,
                'description': description,
                'image': image,
              });
            }
          }
          if (normalized.isNotEmpty) {
            return normalized;
          }
        }
      } catch (_) {}
    }

    final savedHome = prefs.getString('recommended_foods_info');
    if (savedHome != null && savedHome.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedHome);
        if (decoded is List) {
          final normalized = <Map<String, dynamic>>[];
          for (final element in decoded) {
            if (element is Map) {
              final title = element['food_name']?.toString() ?? '';
              final image =
                  element['food_image_url']?.toString() ?? 'assets/images/food_image0.png';
              if (title.trim().isEmpty) continue;
              normalized.add({
                'title': title,
                'description': _fallbackDescription,
                'image': image,
              });
            }
          }
          if (normalized.isNotEmpty) {
            return normalized;
          }
        }
      } catch (_) {}
    }

    return _buildDefaultFallbackFoods();
  }

  Future<void> _handleRecommendationFailure(
    SharedPreferences prefs, {
    bool append = false,
    String? message,
  }) async {
    final fallbackFoods = _loadFallbackFoods(prefs);
    await prefs.setString(
      _matchingFoodCacheKey,
      jsonEncode(fallbackFoods),
    );
    if (!mounted) return;
    setState(() {
      if (!append || recommendedFoods.isEmpty) {
        recommendedFoods = fallbackFoods;
        currentFoodIndex = 0;
      }
      isLoading = false;
    });
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }


  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    )..addListener(() {
      setState(() {});
    });

    _fetchFoodRecommendations();
  }

  @override
  void dispose() {
    _controller.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _toggleCard() {
    if (_controller.isAnimating) return;

    if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
      setState(() {
        isBack = true;
      });
    } else {
      _controller.reverse();
      setState(() {
        isBack = false;
      });
    }
  }

  Future<void> _fetchFoodRecommendations({bool append = false}) async {
    if (isFetching) return;
    isFetching = true;

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final userUUID = prefs.getString('user_uuid') ?? '';

      if (userUUID.isEmpty) {
        throw Exception('??? UUID? ?? ? ????');
      }
      await ensureUserTypeCode(
        prefs,
        uuid: userUUID,
      );

      final url =
          'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/unique-random-foods/?uuid=$userUUID';
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
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final List<dynamic> foods = responseData['random_foods'];

        if (foods.isEmpty) {
          throw Exception('?? ?? ??? ?? ?????');
        }

        final currentTitles = recommendedFoods.map((f) => f['title']).toSet();

        final newItems = foods
            .where((food) => !currentTitles.contains(food['food_name']))
            .map((food) => {
                  'title': food['food_name'] ?? '?? ??',
                  'description': food['description'] ?? '?? ??',
                  'image': food['food_image_url'] ?? 'assets/images/food_image0.png',
                })
            .toList();

        final updatedFoods =
            append ? [...recommendedFoods, ...newItems] : newItems;

        await prefs.setString(
          _matchingFoodCacheKey,
          jsonEncode(updatedFoods),
        );
        await prefs.setStringList(
          'recommended_foods',
          updatedFoods
              .map((f) => f['title']?.toString() ?? '')
              .where((title) => title.trim().isNotEmpty)
              .toList(),
        );

        if (!mounted) return;

        setState(() {
          recommendedFoods = updatedFoods;
          isLoading = false;
        });
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        await _handleRecommendationFailure(
          prefs,
          append: append,
          message: '?? ??? ???? ?? ????.',
        );
      } else {
        throw Exception('?? ??? ???? ?????');
      }
    } catch (e) {
      final fallbackPrefs = prefs ?? await SharedPreferences.getInstance();
      print('Error fetching matching foods: $e');
      await _handleRecommendationFailure(
        fallbackPrefs,
        append: append,
        message: append
            ? '??? ??? ???? ????. ?? ? ?? ??? ???.'
            : '?? ???? ???? ????. ?? ??? ??????.',
      );
    } finally {
      isFetching = false;
    }
  }

  Future<void> fetchRestaurants(String foodName) async {
    try {
      print('1. 요청 시작 - 음식 이름: $foodName');

      final url = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/';
      final requestBody = json.encode({
        'food_names': [foodName],
      });

      print('2. API 요청 정보:');
      print('URL: $url');
      print('Request Body: $requestBody');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      print('3. API 응답 정보:');
      print('Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('4. 응답 디코딩 시작');
        final responseData = json.decode(response.body);
        final List<dynamic> restaurants = responseData['random_restaurants'] ?? [];
        print('5. 추출된 음식점 수: ${restaurants.length}');

        final position = await LocationHelper.getLatLon();
        final userLat = position?['lat'] ?? 35.8714;
        final userLon = position?['lon'] ?? 128.6014;

        print('6. 음식점 데이터 매핑 시작');
        final prefs = await SharedPreferences.getInstance();

        final mappedRestaurants = restaurants.map<Map<String, dynamic>>((restaurant) {
          final restLat = double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
          final restLon = double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;

          final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          final name = restaurant['name'] ?? '이름 없음';
          final address = restaurant['road_address'] ?? '주소 없음';
          final isLiked = prefs.getBool('liked_${name}_$address') ?? false;

          final mapped = {
            'name': name,
            'road_address': address,
            'category_1': restaurant['category_1'] ?? '카테고리 없음',
            'category_2': restaurant['category_2'] ?? '카테고리 없음',
            'x': restaurant['x']?.toString(),
            'y': restaurant['y']?.toString(),
            'distance': distance,
            'isLiked': isLiked,
          };
          print('매핑된 음식점: $mapped');
          return mapped;
        }).toList();

        if (!mounted) return;

        setState(() {
          foodToRestaurants[foodName] = mappedRestaurants;
        });
        print('7. 상태 업데이트 완료');
      } else {
        print('8. API 오류 응답: ${response.statusCode}');
        throw Exception('음식점 정보를 불러오지 못했습니다: ${response.body}');
      }
    } catch (e) {
      print('9. 에러 발생: ${e.toString()}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('음식점 정보를 불러오는 중 오류가 발생했습니다: ${e.toString()}')),
      );
    }
  }

  Future<void> _toggleRestaurantLike(String foodName, int restaurantIndex) async {
    final restaurants = foodToRestaurants[foodName];
    if (restaurants == null || restaurantIndex < 0 || restaurantIndex >= restaurants.length) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final restaurant = restaurants[restaurantIndex];
    final name = restaurant['name']?.toString() ?? '';
    final address = restaurant['road_address']?.toString() ?? '';
    if (name.isEmpty || address.isEmpty) {
      return;
    }

    final currentlyLiked = restaurant['isLiked'] == true;
    final newLiked = !currentlyLiked;

    if (!mounted) return;
    setState(() {
      restaurants[restaurantIndex]['isLiked'] = newLiked;
    });

    await prefs.setBool('liked_${name}_$address', newLiked);

    Map<String, dynamic> allLiked = {};
    final savedLikedAll = prefs.getString('liked_restaurants_all');
    if (savedLikedAll != null && savedLikedAll.isNotEmpty) {
      try {
        allLiked = Map<String, dynamic>.from(json.decode(savedLikedAll));
      } catch (_) {
        allLiked = {};
      }
    }

    final compositeKey = '$name|$address';
    if (newLiked) {
      final storedRestaurant = Map<String, dynamic>.from(restaurants[restaurantIndex]);
      allLiked[compositeKey] = storedRestaurant;
    } else {
      allLiked.remove(compositeKey);
    }
    await prefs.setString('liked_restaurants_all', json.encode(allLiked));

    final uuid = prefs.getString('user_uuid') ?? '';
    if (uuid.isEmpty) {
      return;
    }

    await _updateFavoriteRestaurant(uuid, name, newLiked ? 'add' : 'remove');
  }

  Future<void> _updateFavoriteRestaurant(String uuid, String restaurantName, String action) async {
    if (restaurantName.isEmpty) return;

    final url = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/update/favorite_restaurants/');
    try {
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'uuid': uuid, 'restaurant': restaurantName, 'action': action}),
      );
    } catch (e) {
      print('찜한 음식점 정보를 업데이트하는 중 오류가 발생했습니다: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = size.width * 0.05;

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF312E81),
          ),
        ),
      );
    }

    if (recommendedFoods.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('추천 음식이 없습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Image.asset(
          'assets/images/logo1.png',
          height: 24,
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          controller: pageController,
          onPageChanged: (index) {
            setState(() {
              currentFoodIndex = index;
              if (isBack) {
                _toggleCard();
              }
            });

            // ⭐ 음식이 3개 이하로 남으면 자동으로 추가 요청
            if (index >= recommendedFoods.length - FETCH_THRESHOLD) {
              _fetchFoodRecommendations(append: true);
            }
          },
          itemBuilder: (context, index) {
            final actualIndex = index % recommendedFoods.length;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.01),
                  Text(
                    '입맛을 제대로 저격할 메뉴!',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: size.width * 0.055,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  SizedBox(height: size.height * 0.005),
                  Text(
                    '당신에게 꼭 맞는 음식을 찾아보세요!',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: size.width * 0.032,
                      fontWeight: FontWeight.w300,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  SizedBox(height: size.height * 0.02),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!isBack) {
                          // 앞면일 때 탭하면 음식점 정보를 먼저 가져옴
                          final food = recommendedFoods[actualIndex];
                          final foodName = food['title'];
                          if (foodToRestaurants[foodName] == null) {
                            fetchRestaurants(foodName).then((_) {
                              _toggleCard();
                            });
                          } else {
                            _toggleCard();
                          }
                        } else {
                          // 뒷면일 때는 바로 뒤집기
                          _toggleCard();
                        }
                      },
                      child: Transform(
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(math.pi * _animation.value),
                        alignment: Alignment.center,
                        child: _animation.value < 0.5
                            ? _buildFrontCard(size, padding, actualIndex)
                            : Transform(
                          transform: Matrix4.identity()..rotateY(math.pi),
                          alignment: Alignment.center,
                          child: _buildBackCard(size, padding, actualIndex),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: size.height * 0.035),
                  Text(
                    "카드를 터치하여 관련 음식점을 확인하세요!",
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: size.width * 0.04,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: size.height * 0.03),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFrontCard(Size size, double padding, int index) {
    final food = recommendedFoods[index];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: food["image"]!.startsWith('http')
                  ? Image.network(
                food["image"]!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Image.asset(
                    'assets/images/food_image0.png',
                    fit: BoxFit.cover,
                  );
                },
              )
                  : Image.asset(
                food["image"]!,
                fit: BoxFit.cover,
              ),
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
                  bottom: Radius.circular(24),
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
            left: padding,
            right: padding,
            bottom: padding * 1.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  food["title"]!,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: size.width * 0.055,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: size.height * 0.01),
                Text(
                  food["description"]!,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: size.width * 0.035,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackCard(Size size, double padding, int index) {
    final food = recommendedFoods[index];
    final foodName = food['title'];
    final restaurants = foodToRestaurants[foodName] ?? [];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: restaurants.isEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                foodName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '주변에 해당 음식점이 없습니다.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$foodName 관련 음식점',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: restaurants.length,
                itemBuilder: (context, restaurantIndex) {
                  final restaurant = restaurants[restaurantIndex];
                  final distance = restaurant['distance'];
                  final distanceText = distance != null
                      ? '거리: ${distance.toStringAsFixed(1)} km'
                      : '거리 정보 없음';
                  final isLiked = restaurant['isLiked'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12.0),
                          child: Container(
                            height: 60,
                            width: 60,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                restaurant['name'] ?? '이름 없음',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                restaurant['road_address'] ?? '주소 없음',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                distanceText,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border),
                          color: isLiked ? Colors.red : Colors.grey,
                          onPressed: () => _toggleRestaurantLike(foodName, restaurantIndex),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}
