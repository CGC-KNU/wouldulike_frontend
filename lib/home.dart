import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'nearby_restaurants_screen.dart';
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';
import 'coupon_list_screen.dart';

// URL 열기 도구
class UrlLauncherUtil {
  static Future<void> launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);

    try {
      if (await canLaunchUrl(url)) {
        final bool launched = await launchUrl(
          url,
          mode: LaunchMode.platformDefault,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );

        if (!launched) {
          throw 'URL 실행 실패: $urlString';
        }
      } else {
        throw 'URL 실행 불가: $urlString';
      }
    } catch (e) {
      print('URL 실행 중 에러: $e');
      rethrow;
    }
  }
}

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});
  @override
  _HomeContentState createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  late SharedPreferences prefs;
  List<Map<String, dynamic>> recommendedFoods = [];
  List<Map<String, dynamic>> recommendedRestaurants = [];
  Map<String, bool> likedRestaurants = {};
  final PageController _bannerController = PageController();
  final ScrollController _scrollController = ScrollController();
  bool _isFetching = false;
  int _currentBannerIndex = 0;
  @override

  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializePrefs();
  }

  Future<void> _initializePrefs() async {
    prefs = await SharedPreferences.getInstance();
    await _loadRecommendedFoods();
    await _loadRestaurantsData();
    await _loadLikedRestaurants();
    final cachedFoodNames = _getCachedFoodNames();

    if (cachedFoodNames.isEmpty) {
      await _refreshFoodsAndRestaurants();
    } else if (recommendedRestaurants.isEmpty) {
      await _refreshRestaurantsOnly();
    }
  }

  void _openCouponList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CouponListScreen()),
    );
  }

  Future<void> _loadRestaurantsData() async {
    final String? savedRestaurants = prefs.getString('restaurants_data');

    if (savedRestaurants != null) {
      final List<Map<String, dynamic>> decoded = List<Map<String, dynamic>>.from(
        json.decode(savedRestaurants),
      );

      // 사용자 위치 가져오기
      final position = await LocationHelper.getLatLon();
      final userLat = position?['lat'] ?? 35.8714;
      final userLon = position?['lon'] ?? 128.6014;

      // 거리 계산 추가
      for (var restaurant in decoded) {
        final double restLat = double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
        final double restLon = double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
        final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
        restaurant['distance'] = distance;
      }

      setState(() {
        recommendedRestaurants = decoded
            .where((restaurant) => restaurant['distance'] != null && restaurant['distance'] <= 1.0)
            .map((restaurant) => {
          'name': restaurant['name'] ?? '이름 없음',
          'road_address': restaurant['road_address'] ?? '주소 없음',
          'category_2': restaurant['category_2'] ?? '카테고리 없음',
          'x': restaurant['x'],
          'y': restaurant['y'],
          'distance': restaurant['distance'],
        }).toList();
        //print('추천 음식점 로드 완료: ${recommendedRestaurants.length}개');
      });
    }
  }

  // URL 열기 함수
  Future<void> _launchURL(String url) async {
    try {
      await UrlLauncherUtil.launchURL(url);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('URL을 열 수 없습니다: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 추천 음식 로드
  Future<void> _loadRecommendedFoods() async {
    final String? savedFoodInfo = prefs.getString('recommended_foods_info');
    //print('Raw saved food info: $savedFoodInfo');

    if (savedFoodInfo != null) {
      try {
        final List<dynamic> decodedInfo = json.decode(savedFoodInfo);
        //print('Decoded food info: $decodedInfo');

        setState(() {
          recommendedFoods = List<Map<String, dynamic>>.from(decodedInfo);
        });

        // 로드된 데이터 확인

      } catch (e) {
        //print('Error decoding food info: $e');
        setState(() {
          recommendedFoods = [];
        });
      }
    }
  }

  List<String> _getCachedFoodNames() {
    final fromState = recommendedFoods
        .map((food) => food['food_name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    if (fromState.isNotEmpty) {
      return fromState;
    }

    final String? savedFoodInfo = prefs.getString('recommended_foods_info');
    if (savedFoodInfo == null) {
      return const [];
    }

    try {
      final List<dynamic> decodedInfo = json.decode(savedFoodInfo);
      return decodedInfo
          .map((item) =>
      (item as Map<String, dynamic>)['food_name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
  // 찜한 음식점 상태 로드
  Future<void> _loadLikedRestaurants() async {
    if (recommendedRestaurants.isEmpty) return;

    // 전체 찜 목록 데이터 로드
    final String? savedLikedAll = prefs.getString('liked_restaurants_all');
    Map<String, dynamic> allLikedRestaurants = {};

    if (savedLikedAll != null) {
      allLikedRestaurants = json.decode(savedLikedAll);
    }

    setState(() {
      likedRestaurants.clear();

      // 각 음식점에 대해 찜 상태 확인
      for (var restaurant in recommendedRestaurants) {
        String name = restaurant['name'] ?? '이름 없음';
        String address = restaurant['road_address'] ?? '주소 없음';
        String key = '$name|$address';

        // 이전에 찜한 적이 있는지 확인
        if (allLikedRestaurants.containsKey(key)) {
          likedRestaurants[key] = true;
          // 개별 상태도 업데이트
          prefs.setBool('liked_${name}_${address}', true);
        } else {
          // 없다면 기존 개별 상태 확인
          bool isLiked = prefs.getBool('liked_${name}_${address}') ?? false;
          if (isLiked) {
            likedRestaurants[key] = true;
          }
        }

        //print('음식점 $name의 찜 상태: ${likedRestaurants[key] ?? false}');
      }
    });

    //print('전체 찜 상태: $likedRestaurants');
  }
  // 서버에 찜 상태 동기화
  Future<void> _updateFavoriteRestaurant(String restaurantName, String action) async {
    final uuid = prefs.getString('user_uuid') ?? '';
    if (uuid.isEmpty) return;

    final url = Uri.parse(
        'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/update/favorite_restaurants/');

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

  // 찜하기 상태 저장 후 서버에 반영
  Future<void> _saveLikedStatus(String restaurantName, String address, bool isLiked) async {
    final String key = '$restaurantName|$address';
    setState(() {
      likedRestaurants[key] = isLiked;
    });
    // 개별 음식점의 찜 상태 저장
    await prefs.setBool('liked_${restaurantName}_${address}', isLiked);
    final action = isLiked ? 'add' : 'remove';
    await _updateFavoriteRestaurant(restaurantName, action);
  }

  // 음식점의 찜 상태 확인
  bool _isRestaurantLiked(String restaurantName, String address) {
    final String key = '$restaurantName|$address';
    return likedRestaurants[key] ?? false;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isFetching) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll > maxScroll - 100) {
      _refreshRestaurantsOnly();
    }
  }

  Future<void> _refreshFoodsAndRestaurants() async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      final foodNames = await _fetchFoods();
      if (foodNames.isEmpty) {
        return;
      }
      await _fetchRestaurants(foodNames);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터를 불러오지 못했어요: $e')),
        );
      }
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _refreshRestaurantsOnly() async {
    if (_isFetching) return;

    final foodNames = _getCachedFoodNames();
    if (foodNames.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('먼저 음식 추천을 새로고침 해주세요.')),
        );
      }
      return;
    }

    _isFetching = true;
    try {
      await _fetchRestaurants(foodNames);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음식점을 불러오지 못했어요: $e')),
        );
      }
    } finally {
      _isFetching = false;
    }
  }

  Future<List<String>> _fetchFoods() async {
    final userUuid = prefs.getString('user_uuid') ?? '';
    if (userUuid.isEmpty) throw Exception('사용자 UUID를 찾을 수 없습니다');
    final String? typeCode = prefs.getString('user_type');

    if (typeCode == null || typeCode.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('취향 코드가 등록되어 있지 않습니다.')),
        );
      }
      return const [];
    }

    final foodUrl =
        'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/food-by-type/random-foods/?uuid=$userUuid';
    http.Response foodResponse;
    int retry = 0;
    int delay = 1;
    do {
      foodResponse = await http.get(Uri.parse(foodUrl));
      if (foodResponse.statusCode == 200 ||
          foodResponse.statusCode == 400 ||
          foodResponse.statusCode == 404) break;
      await Future.delayed(Duration(seconds: delay));
      delay *= 2;
      retry++;
    } while (retry < 3);

    if (foodResponse.statusCode == 200) {
      final Map<String, dynamic> foodData =
      jsonDecode(utf8.decode(foodResponse.bodyBytes));
      final List<dynamic> foods = foodData['random_foods'] ?? [];

      final foodInfoList = foods
          .map<Map<String, dynamic>>((f) => {
        'food_name': f['food_name'],
        'food_image_url': f['food_image_url'],
      })
          .toList();

      final foodNames = foodInfoList
          .map((food) => food['food_name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      await prefs.setStringList('recommended_foods', foodNames);
      await prefs.setString('recommended_foods_info', json.encode(foodInfoList));

      if (mounted) {
        setState(() {
          recommendedFoods = foodInfoList
              .map<Map<String, dynamic>>((food) => {
            'food_name': food['food_name'],
            'food_image_url': food['food_image_url'],
          })
              .toList();
        });
      }

      return foodNames;
    } else if (foodResponse.statusCode == 400 ||
        foodResponse.statusCode == 404) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('취향 코드가 등록되어 있지 않습니다.')),
        );
      }
      return const [];
    } else {
      throw Exception('음식을 불러오지 못했습니다');
    }
  }

  Future<void> _fetchRestaurants(List<String> foodNames) async {
    final restaurantUrl =
        'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/';
    http.Response restResponse;
    int retry = 0;
    int delay = 1;
    do {
      restResponse = await http.post(
        Uri.parse(restaurantUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'food_names': foodNames}),
      );
      if (restResponse.statusCode == 200 ||
          restResponse.statusCode == 400 ||
          restResponse.statusCode == 404) break;
      await Future.delayed(Duration(seconds: delay));
      delay *= 2;
      retry++;
    } while (retry < 3);

    if (restResponse.statusCode == 200) {
      final restData = jsonDecode(utf8.decode(restResponse.bodyBytes));
      final List<dynamic> restaurants = restData['random_restaurants'] ?? [];
      await prefs.setString('restaurants_data', json.encode(restaurants));

      final position = await LocationHelper.getLatLon();
      final userLat = position?['lat'] ?? 35.8714;
      final userLon = position?['lon'] ?? 128.6014;
      for (var restaurant in restaurants) {
        final restLat =
            double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
        final restLon =
            double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
        final distance =
        DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
        restaurant['distance'] = distance;
      }

      if (mounted) {
        setState(() {
          recommendedRestaurants = restaurants
              .map<Map<String, dynamic>>((restaurant) => {
            'name': restaurant['name'] ?? '이름 없음',
            'road_address':
            restaurant['road_address'] ?? '주소 없음',
            'category_2':
            restaurant['category_2'] ?? '카테고리 없음',
            'x': restaurant['x'],
            'y': restaurant['y'],
            'distance': restaurant['distance'],
          })
              .toList();
        });
      }

      await _loadLikedRestaurants();
    } else if (restResponse.statusCode == 400 ||
        restResponse.statusCode == 404) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('취향 코드가 등록되어 있지 않습니다.')),
        );
      }
    } else {
      throw Exception('음식점을 불러오지 못했습니다');
    }
  }

  Widget _buildRecommendedFoodsSection(double cardWidth) {
    if (recommendedFoods.isEmpty) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildMenuCard(
              'assets/images/food_image0.png',
              '추천 음식이 아직 준비되지 않았어요',
              cardWidth,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: recommendedFoods.map<Widget>((food) =>
            _buildMenuCard(
              food['food_image_url']?.toString() ?? 'assets/images/food_image0.png',
              food['food_name']?.toString() ?? '이름 없음',
              cardWidth,
              onTap: () => _onFoodSelected(food),
            ),
        ).toList(),
      ),
    );
  }


  void _onFoodSelected(Map<String, dynamic> food) {
    final foodName = food['food_name']?.toString().trim() ?? '';
    if (foodName.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoodRestaurantListScreen(
          foodName: foodName,
          imageUrl: food['food_image_url']?.toString(),
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(Map<String, dynamic> restaurant) {
    final distance = restaurant['distance'];
    final distanceText = distance is num
        ? '거리 ${distance.toStringAsFixed(1)} km'
        : null;

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
      child: Stack(
        children: [
          Row(
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restaurant['road_address'] ?? '주소 없음',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    if (distanceText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        distanceText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      restaurant['category_2'] ?? '카테고리 없음',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Icon(
                _isRestaurantLiked(restaurant['name'], restaurant['road_address'])
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: _isRestaurantLiked(restaurant['name'], restaurant['road_address'])
                    ? Colors.red
                    : Colors.grey,
              ),
              onPressed: () async {
                final bool currentStatus =
                _isRestaurantLiked(restaurant['name'], restaurant['road_address']);
                await _saveLikedStatus(
                  restaurant['name'],
                  restaurant['road_address'],
                  !currentStatus,
                );

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      !currentStatus ? '찜 목록에 추가했어요' : '찜 목록에서 제거했습니다',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildPromotionBanner(double width) {
    final double height = width / 3.5;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerController,
            onPageChanged: (index) {
              setState(() {
                _currentBannerIndex = index % 5;
              });
            },
            itemBuilder: (context, index) {
              return Container(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                ),
              );
            },
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentBannerIndex + 1}/5',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMenuCard(String imagePath, String title, double width, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: EdgeInsets.only(right: width * 0.05),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: imagePath.startsWith('http')
                  ? Image.network(
                imagePath,
                height: width * 0.8,
                width: double.infinity,
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
                    height: width * 0.8,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  );
                },
              )
                  : Image.asset(
                imagePath,
                height: width * 0.8,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(width * 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: width * 0.08,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bannerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double padding = screenWidth * 0.04;
    final double cardWidth = screenWidth * 0.35;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Image.asset(
          'assets/images/logo1.png',
          height: 24,
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.card_giftcard_outlined,
              color: Color(0xFF312E81),
            ),
            tooltip: '내 쿠폰',
            onPressed: _openCouponList,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshFoodsAndRestaurants,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: padding * 0.8),
                _buildPromotionBanner(screenWidth),
                SizedBox(height: padding * 0.8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '이번 주 인기 있는 메뉴를 확인해보세요!',
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshFoodsAndRestaurants,
                    ),
                  ],
                ),
                SizedBox(height: padding * 0.7),
                _buildRecommendedFoodsSection(cardWidth),
                SizedBox(height: padding * 0.8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '입맛에 꼭 맞는 음식점을 추천해드릴게요.',
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshRestaurantsOnly,
                    ),
                  ],
                ),
                SizedBox(height: padding * 0.4),
                /*
              Container(
                height: screenHeight * 0.6,
                child: recommendedRestaurants.isEmpty
                    ? Center(
                  child: Text('추천 음식점이 없습니다.'),
                )
                    : ListView.builder(
                  itemCount: recommendedRestaurants.length,
                  itemBuilder: (context, index) {
                    return _buildRestaurantCard(recommendedRestaurants[index]);
                  },
                ),
              ),
              */
                Container(
                  // height 제거: 컨텐츠 크기만큼 자동으로 늘어나도록
                  child: recommendedRestaurants.isEmpty
                      ? Center(
                    child: Text('추천할 만한 음식점을 찾지 못했어요.'),
                  )
                      : ListView.builder(
                    physics: NeverScrollableScrollPhysics(), // 스크롤을 부모에게 위임
                    shrinkWrap: true, // 컨텐츠 크기만큼만 차지하도록
                    itemCount: recommendedRestaurants.length,
                    itemBuilder: (context, index) {
                      return _buildRestaurantCard(recommendedRestaurants[index]);
                    },
                  ),
                ),
                SizedBox(height: padding * 0.8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NearbyRestaurantsScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF312E81),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      '내 주변 음식점 보기',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Pretendard',
                        fontSize: screenWidth * 0.045,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class FoodRestaurantListScreen extends StatefulWidget {
  const FoodRestaurantListScreen({super.key, required this.foodName, this.imageUrl});

  final String foodName;
  final String? imageUrl;

  @override
  State<FoodRestaurantListScreen> createState() => _FoodRestaurantListScreenState();
}

class _FoodRestaurantListScreenState extends State<FoodRestaurantListScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'food_names': [widget.foodName],
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final restaurants =
        (decoded['random_restaurants'] as List<dynamic>? ?? const [])
            .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        final position = await LocationHelper.getLatLon();
        final userLat = position?['lat'] ?? 35.8714;
        final userLon = position?['lon'] ?? 128.6014;

        final mapped = restaurants.map<Map<String, dynamic>>((restaurant) {
          final restLat = double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
          final restLon = double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
          final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          return {
            'name': restaurant['name'] ?? '이름 없음',
            'road_address': restaurant['road_address'] ?? '주소 정보 없음',
            'category_2': restaurant['category_2'] ?? restaurant['category_1'] ?? '카테고리 정보 없음',
            'distance': distance,
          };
        }).toList();

        if (!mounted) return;
        setState(() {
          _restaurants = mapped;
          _isLoading = false;
        });
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _restaurants = const [];
          _errorMessage = '추천할 만한 맛집을 찾지 못했어요.';
          _isLoading = false;
        });
      } else {
        throw Exception('음식점 정보를 불러오지 못했어요. (status ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '음식점 정보를 불러오지 못했어요. 다시 시도해주세요.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: Text('${widget.foodName} 추천 맛집'),
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
              onPressed: _loadRestaurants,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_restaurants.isEmpty) {
      return const Center(child: Text('추천할 만한 맛집을 찾지 못했어요.'));
    }

    final hasHeaderImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final itemCount = _restaurants.length + (hasHeaderImage ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        int dataIndex = index;
        if (hasHeaderImage) {
          if (index == 0) {
            return _FoodHeader(imageUrl: widget.imageUrl!, foodName: widget.foodName);
          }
          dataIndex -= 1;
        }

        final restaurant = _restaurants[dataIndex];
        final distance = restaurant['distance'];
        final distanceText = distance is num ? '거리 ${distance.toStringAsFixed(1)} km' : null;

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
                if (distanceText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    distanceText,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
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

class _FoodHeader extends StatelessWidget {
  const _FoodHeader({required this.imageUrl, required this.foodName});

  final String imageUrl;
  final String foodName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: imageUrl.startsWith('http')
              ? Image.network(
            imageUrl,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/food_image0.png',
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
              : Image.asset(
            imageUrl,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          foodName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
