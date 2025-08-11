import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'match.dart';
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';

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
  @override
  _HomeContentState createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final PageController _pageController = PageController();
  late SharedPreferences prefs;
  List<Map<String, dynamic>> recommendedFoods = [];
  List<Map<String, dynamic>> recommendedRestaurants = [];
  Map<String, bool> likedRestaurants = {};

  @override
  void initState() {
    super.initState();
    _initializePrefs();
  }

  Future<void> _initializePrefs() async {
    prefs = await SharedPreferences.getInstance();
    await _loadRecommendedFoods();
    await _loadRestaurantsData();
    await _loadLikedRestaurants();
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
        for (var food in recommendedFoods) {
          //print('음식 이름: ${food['food_name']}');
          //print('이미지 URL: ${food['food_image_url']}');
        }

      } catch (e) {
        //print('Error decoding food info: $e');
        setState(() {
          recommendedFoods = [];
        });
      }
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
  // 찜하기 상태 저장하기도 수정
  Future<void> _saveLikedStatus(String restaurantName, String address, bool isLiked) async {
    final String key = '$restaurantName|$address';
    setState(() {
      likedRestaurants[key] = isLiked;
    });
    // 개별 음식점의 찜 상태 저장
    await prefs.setBool('liked_${restaurantName}_${address}', isLiked);
    //print('$restaurantName 찜 상태 저장: $isLiked');
  }

  // 음식점의 찜 상태 확인
  bool _isRestaurantLiked(String restaurantName, String address) {
    final String key = '$restaurantName|$address';
    return likedRestaurants[key] ?? false;
  }

  Widget _buildRecommendedFoodsSection(double cardWidth) {
    if (recommendedFoods.isEmpty) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildMenuCard(
              'assets/images/food_image0.png',
              '추천 음식이 없습니다',
              cardWidth,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: recommendedFoods.map<Widget>((Map<String, dynamic> food) =>
            _buildMenuCard(
              food['food_image_url'] ?? 'assets/images/food_image0.png',
              food['food_name'] ?? '이름 없음',
              cardWidth,
            ),
        ).toList(),
      ),
    );
  }

  Widget _buildRestaurantCard(Map<String, dynamic> restaurant) {
    // 사용자가 음식점 카드를 클릭했을 때 상세정보 페이지로 이동
    return GestureDetector(
      onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestaurantDetailScreen(restaurant: restaurant),
      ),
    );
  },
      child: Container(
      margin: EdgeInsets.only(bottom: 16.0),
      padding: EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: Offset(0, 2),
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
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 16.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant['name'] ?? '이름 없음',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      restaurant['road_address'] ?? '주소 없음',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (restaurant['distance'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '📍 ${restaurant['distance'].toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blueGrey,
                          ),
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
                final bool currentStatus = _isRestaurantLiked(
                    restaurant['name'], restaurant['road_address']);
                await _saveLikedStatus(
                  restaurant['name'],
                  restaurant['road_address'],
                  !currentStatus,
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      !currentStatus ? '찜 목록에 추가되었습니다.' : '찜 목록에서 제거되었습니다.',
                    ),
                    duration: const Duration(seconds: 1),
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
/*
  Widget _buildPage(String imagePath, String title, String subtitle, String url) {
    return GestureDetector(
      onTap: () => _launchURL(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          color: Colors.grey[100],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imagePath,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(minHeight: 50),
                  padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
*/
  Widget _buildPage(String imagePath, String title, String subtitle, String url) {
    return GestureDetector(
      onTap: () => _launchURL(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          color: Colors.grey[100],
          child: Stack(
            children: [
              Image.asset(
                imagePath,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.all(12),
                  color: Colors.black.withOpacity(0.4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildMenuCard(String imagePath, String title, double width) {
    return Container(
      width: width,
      margin: EdgeInsets.only(right: width * 0.05),
      decoration: BoxDecoration(
        color: Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            child: imagePath.startsWith('http')  // URL인지 확인
                ? Image.network(
              imagePath,
              height: width * 0.8,
              width: double.infinity,
              fit: BoxFit.cover,
              // 로딩 중일 때 표시할 위젯
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
              // 에러 발생시 기본 이미지 표시
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
    );
  }
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double padding = screenWidth * 0.04;
    final double cardWidth = screenWidth * 0.35;
    final double pageViewHeight = screenWidth * 0.52;

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
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '이번주 트렌드 뉴스',
                    style: TextStyle(
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: padding * 0.5),
              Container(
                height: pageViewHeight,
                child: PageView(
                  controller: _pageController,
                  children: [
                    _buildPage(
                      'assets/images/trend111.jpg',
                      '헬로키티와 크라운이 만났다!',
                      '크라운제과 공식 인스타 (@crownsns)에서 댓글 이벤트도 진행되고 있다고 하니, 놓치지 마세요! 🔥',
                      'https://m.blog.naver.com/PostView.naver?blogId=w_ouldulike&logNo=223749111277&navType=by',
                    ),
                    _buildPage(
                      'assets/images/trend112.jpg',
                      '스타들의 요아정 pick..☆',
                      '요아정, 스타들도 반한 그 매력 ✨ 스타들의 요아정 pick..☆ 궁금하다 !',
                      'https://m.blog.naver.com/PostView.naver?blogId=w_ouldulike&logNo=223693514046&navType=by',
                    ),
                    _buildPage(
                      'assets/images/trend113.jpg',
                      '교동에서 맛집을 외치다..👀✨',
                      '츄카소바 설철수, 옆구리, 오일리버거, 강산면옥, 후발대를 만나보세요!',
                      'https://m.blog.naver.com/PostView.naver?blogId=w_ouldulike&logNo=223684945450&navType=by',
                    ),
                    _buildPage(
                      'assets/images/trend114.jpg',
                      '붕어빵의 위치를 알 수 있는 어플이 있다구요?!',
                      '따끈따끈한 붕어빵과 함께 이번 겨울은 붕어빵 지도가 전해주는 소소한 행복을 누려보세요 ❄',
                      'https://m.blog.naver.com/PostView.naver?blogId=w_ouldulike&logNo=223687655192&navType=by',
                    ),
                  ],
                ),
              ),
              SizedBox(height: padding * 0.6),
              Center(
                child: SmoothPageIndicator(
                  controller: _pageController,
                  count: 4,
                  effect: WormEffect(
                    dotWidth: screenWidth * 0.02,
                    dotHeight: screenWidth * 0.02,
                    spacing: screenWidth * 0.02,
                  ),
                ),
              ),
              SizedBox(height: padding * 0.8),
              Text(
                '이번 주 인기 있는 메뉴를 확인해보세요!',
                style: TextStyle(
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: padding * 0.7),
              _buildRecommendedFoodsSection(cardWidth),
              SizedBox(height: padding * 0.8),
              Text(
                '입맛에 꼭 맞는 음식점을 추천해드릴게요.',
                style: TextStyle(
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.bold,
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}
/// 선택한 음식점의 상세 정보를 보여주는 화면
class RestaurantDetailScreen extends StatelessWidget {
  final Map<String, dynamic> restaurant;

  const RestaurantDetailScreen({Key? key, required this.restaurant}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(restaurant['name'] ?? '음식점 상세정보'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🏠 주소: ${restaurant['road_address'] ?? '정보 없음'}',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '📂 카테고리: ${restaurant['category_2'] ?? '정보 없음'}',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 8),
            if (restaurant['distance'] != null)
              Text(
                '📍 현재 거리: ${restaurant['distance'].toStringAsFixed(1)} km',
                style: TextStyle(fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}
