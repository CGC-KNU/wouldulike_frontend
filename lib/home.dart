import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';
import 'coupon_list_screen.dart';
import 'services/coupon_service.dart';
import 'services/trend_service.dart';

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
  static const String _kWelcomeCouponDismissedKey =
      'welcome_coupon_dialog_dismissed';
  static const List<String> _kWelcomeCouponKeywords = <String>[
    '신규가입',
    '회원가입',
    '가입축하',
    '환영',
    'welcome',
    'new member',
    '가입 축하',
  ];
  static const String _defaultPromotionTitle = '우주라이크 사용 가이드';
  static const String _defaultPromotionDescription = '앱 사용 가이드를 바로 만나보세요.';
  static const String _defaultPromotionImage = 'https://placehold.co/345x220';
  late SharedPreferences prefs;
  List<Map<String, dynamic>> recommendedFoods = [];
  List<Map<String, dynamic>> recommendedRestaurants = [];
  Map<String, bool> likedRestaurants = {};
  List<TrendItem> _trends = [];
  final PageController _bannerController = PageController();
  final ScrollController _scrollController = ScrollController();
  bool _isFetching = false;
  int _currentBannerIndex = 0;
  bool _isTrendLoading = false;
  bool _isCheckingWelcomeCoupon = false;
  bool _welcomeDialogVisible = false;
  bool _welcomePromptScheduled = false;
  bool _suppressWelcomeCoupon = false;
  bool _showNearby = false;
  bool _isNearbyLoading = false;
  String? _nearbyError;
  List<Map<String, dynamic>> _nearbyRestaurants = [];
  bool _scrollFetchArmed = true;
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializePrefs();
    _loadTrends();
  }

  Future<void> _initializePrefs() async {
    prefs = await SharedPreferences.getInstance();
    _suppressWelcomeCoupon =
        prefs.getBool(_kWelcomeCouponDismissedKey) ?? false;
    await _loadRecommendedFoods();
    await _loadRestaurantsData();
    await _loadLikedRestaurants(recommendedRestaurants);
    final cachedFoodNames = _getCachedFoodNames();

    if (cachedFoodNames.isEmpty) {
      await _refreshFoodsAndRestaurants();
    } else if (recommendedRestaurants.isEmpty) {
      await _refreshRestaurantsOnly();
    }
    if (!_suppressWelcomeCoupon) {
      await _checkWelcomeCouponStatus();
    }
  }

  Future<void> _loadTrends() async {
    if (_isTrendLoading) return;
    if (!mounted) return;
    setState(() {
      _isTrendLoading = true;
    });
    try {
      final items = await TrendService.fetchTrends();
      if (!mounted) return;
      setState(() {
        _trends = items;
        _currentBannerIndex = 0;
      });
      if (_bannerController.hasClients && items.isNotEmpty) {
        _bannerController.jumpToPage(0);
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to load promotion banners: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('프로모션 배너를 불러오지 못했어요.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTrendLoading = false;
        });
      }
    }
  }

  Future<void> _checkWelcomeCouponStatus() async {
    if (_suppressWelcomeCoupon || _isCheckingWelcomeCoupon) return;
    _isCheckingWelcomeCoupon = true;
    try {
      final coupons =
          await CouponService.fetchMyCoupons(status: CouponStatus.issued);
      if (!mounted) return;
      final hasWelcomeCoupon = coupons.any(_isWelcomeCoupon);
      if (!hasWelcomeCoupon ||
          _welcomeDialogVisible ||
          _welcomePromptScheduled) {
        return;
      }
      _welcomePromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _welcomePromptScheduled = false;
          return;
        }
        _showWelcomeCouponDialog();
      });
    } catch (_) {
      // Ignore coupon fetch failures for the welcome dialog.
    } finally {
      _isCheckingWelcomeCoupon = false;
    }
  }

  bool _isWelcomeCoupon(UserCoupon coupon) {
    final benefit = coupon.benefit;
    final candidates = <String>[
      coupon.code,
      benefit?.title ?? '',
      benefit?.subtitle ?? '',
      benefit?.descriptionText ?? '',
    ];
    for (final value in candidates) {
      if (value.isEmpty) continue;
      final lower = value.toLowerCase();
      for (final keyword in _kWelcomeCouponKeywords) {
        if (lower.contains(keyword.toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _showWelcomeCouponDialog() async {
    if (!mounted || _welcomeDialogVisible) {
      _welcomePromptScheduled = false;
      return;
    }
    _welcomeDialogVisible = true;
    bool dontShowAgain = false;
    final bool? shouldSuppress = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                '신규가입 쿠폰이 도착했어요',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              content: const Text(
                '회원가입을 축하드려요! 신규가입 쿠폰이 발급되었어요.\n쿠폰함에서 확인하고 사용해 보세요.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Color(0xFF374151),
                ),
              ),
              actionsPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              dontShowAgain = !dontShowAgain;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: dontShowAgain,
                                  onChanged: (value) {
                                    setState(() {
                                      dontShowAgain = value ?? false;
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '다시 보지 않기',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(dontShowAgain),
                        child: const Text(
                          '확인',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    _welcomeDialogVisible = false;
    _welcomePromptScheduled = false;
    if (shouldSuppress == true) {
      _suppressWelcomeCoupon = true;
      await prefs.setBool(_kWelcomeCouponDismissedKey, true);
    }
  }

  void _handleTrendTap(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _launchURL(trimmed);
  }

  void _openCouponList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CouponListScreen()),
    );
  }

  Future<void> _loadRestaurantsData() async {
    final String? savedRestaurants = prefs.getString('restaurants_data');

    if (savedRestaurants != null) {
      final List<Map<String, dynamic>> decoded =
          List<Map<String, dynamic>>.from(
        json.decode(savedRestaurants),
      );

      // 사용자 위치 가져오기
      final position = await LocationHelper.getLatLon();
      final userLat = position?['lat'] ?? 35.8714;
      final userLon = position?['lon'] ?? 128.6014;

      // 거리 계산 추가
      for (var restaurant in decoded) {
        final double restLat =
            double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
        final double restLon =
            double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
        final distance =
            DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
        restaurant['distance'] = distance;
      }

      setState(() {
        recommendedRestaurants = decoded
            .where((restaurant) =>
                restaurant['distance'] != null && restaurant['distance'] <= 1.0)
            .map((restaurant) => {
                  'name': restaurant['name'] ?? '이름 없음',
                  'road_address': restaurant['road_address'] ?? '주소 없음',
                  'category_2': restaurant['category_2'] ?? '카테고리 없음',
                  'x': restaurant['x'],
                  'y': restaurant['y'],
                  'distance': restaurant['distance'],
                })
            .toList();
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
              (item as Map<String, dynamic>)['food_name']?.toString().trim() ??
              '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // 찜한 음식점 상태 로드
  Future<void> _loadLikedRestaurants([List<Map<String, dynamic>>? restaurants]) async {
    final targets = restaurants ??
        (_showNearby ? _nearbyRestaurants : recommendedRestaurants);
    if (targets.isEmpty) return;

    final String? savedLikedAll = prefs.getString('liked_restaurants_all');
    Map<String, dynamic> allLikedRestaurants = {};

    if (savedLikedAll != null) {
      allLikedRestaurants = json.decode(savedLikedAll);
    }

    setState(() {
      likedRestaurants.clear();

      for (var restaurant in targets) {
        final String name = restaurant['name'] ?? 'Unknown name';
        final String address = restaurant['road_address'] ?? 'No address';
        final String key = '$name|$address';

        if (allLikedRestaurants.containsKey(key)) {
          likedRestaurants[key] = true;
          prefs.setBool('liked_${name}_${address}', true);
        } else {
          final bool isLiked =
              prefs.getBool('liked_${name}_${address}') ?? false;
          if (isLiked) {
            likedRestaurants[key] = true;
          }
        }
      }
    });
  }

Future<void> _updateFavoriteRestaurant(
      String restaurantName, String action) async {
    final uuid = prefs.getString('user_uuid') ?? '';
    if (uuid.isEmpty) return;

    final url = Uri.parse(
        'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/update/favorite_restaurants/');

    try {
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(
            {'uuid': uuid, 'restaurant': restaurantName, 'action': action}),
      );
    } catch (e) {
      print('찜한 음식점 정보를 업데이트하는 중 오류가 발생했습니다: $e');
    }
  }

  // 찜하기 상태 저장 후 서버에 반영
  Future<void> _saveLikedStatus(
      String restaurantName, String address, bool isLiked) async {
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
    if (_showNearby || !_scrollController.hasClients || _isFetching) return;
    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    if (maxScroll <= 0) return;
    final currentScroll = position.pixels;
    final triggerOffset = maxScroll > 100 ? maxScroll - 100 : maxScroll;
    final rearmOffset = math.max(0.0, triggerOffset - 200);
    if (currentScroll >= triggerOffset) {
      if (!_scrollFetchArmed) return;
      _scrollFetchArmed = false;
      _refreshRestaurantsOnly(triggeredByScroll: true);
    } else if (currentScroll <= rearmOffset) {
      _scrollFetchArmed = true;
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
      if (!_suppressWelcomeCoupon) {
        await _checkWelcomeCouponStatus();
      }
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

  Future<void> _refreshRestaurantsOnly({bool triggeredByScroll = false}) async {
    if (_isFetching) return;

    final foodNames = _getCachedFoodNames();
    if (foodNames.isEmpty) {
      if (triggeredByScroll) {
        _scrollFetchArmed = true;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please refresh food recommendations first.')),
        );
      }
      return;
    }

    _isFetching = true;
    try {
      await _fetchRestaurants(foodNames);
      if (!_suppressWelcomeCoupon) {
        await _checkWelcomeCouponStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load restaurants: $e')),
        );
      }
    } finally {
      _isFetching = false;
    }
  }

Future<void> _loadNearbyRestaurants() async {
    if (_isNearbyLoading) return;

    final foodNames = _getCachedFoodNames();
    if (foodNames.isEmpty) {
      if (mounted) {
        setState(() {
          _nearbyRestaurants = [];
          _nearbyError = 'Please refresh food recommendations first.';
        });
      }
      return;
    }

    final position = await LocationHelper.getLatLon();
    if (position == null) {
      if (mounted) {
        setState(() {
          _nearbyRestaurants = [];
          _nearbyError = 'Unable to access your location.';
        });
      }
      return;
    }

    setState(() {
      _isNearbyLoading = true;
      _nearbyError = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
            'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-nearby-restaurants/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'food_names': foodNames,
          'latitude': position['lat'],
          'longitude': position['lon'],
        }),
      );

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final rawRestaurants =
            (decoded['restaurants'] as List<dynamic>? ?? const [])
                .map<Map<String, dynamic>>(
                    (item) => Map<String, dynamic>.from(item as Map))
                .toList();

        final double userLat =
            (position['lat'] as num?)?.toDouble() ?? 35.8714;
        final double userLon =
            (position['lon'] as num?)?.toDouble() ?? 128.6014;

        final mapped = rawRestaurants.map<Map<String, dynamic>>((restaurant) {
          final restLat =
              double.tryParse(restaurant['y']?.toString() ?? '') ?? userLat;
          final restLon =
              double.tryParse(restaurant['x']?.toString() ?? '') ?? userLon;
          final distance =
              DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          return {
            'name': restaurant['name'] ?? 'Unknown name',
            'road_address': restaurant['road_address'] ?? 'No address',
            'category_2': restaurant['category_2'] ?? 'No category',
            'x': restaurant['x'],
            'y': restaurant['y'],
            'distance': distance,
          };
        }).toList();

        if (!mounted) return;
        setState(() {
          _nearbyRestaurants = mapped;
        });
        await _loadLikedRestaurants(_nearbyRestaurants);
      } else if (response.statusCode == 400 || response.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _nearbyRestaurants = [];
          _nearbyError = 'No nearby recommendations available.';
        });
      } else {
        throw Exception('Failed to fetch nearby restaurants.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nearbyRestaurants = [];
        _nearbyError = 'Failed to load nearby restaurants: ' + e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isNearbyLoading = false;
        });
      }
    }
  }

  void _onNearbyToggle() {
    if (_showNearby) {
      setState(() {
        _showNearby = false;
        _nearbyError = null;
      });
      _loadLikedRestaurants(recommendedRestaurants);
    } else {
      setState(() {
        _showNearby = true;
        _nearbyError = null;
      });
      if (_nearbyRestaurants.isEmpty) {
        _loadNearbyRestaurants();
      } else {
        _loadLikedRestaurants(_nearbyRestaurants);
      }
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
      await prefs.setString(
          'recommended_foods_info', json.encode(foodInfoList));

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
                    'road_address': restaurant['road_address'] ?? '주소 없음',
                    'category_2': restaurant['category_2'] ?? '카테고리 없음',
                    'x': restaurant['x'],
                    'y': restaurant['y'],
                    'distance': restaurant['distance'],
                  })
              .toList();
        });
      }

      await _loadLikedRestaurants(recommendedRestaurants);
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
        children: recommendedFoods
            .map<Widget>(
              (food) => _buildMenuCard(
                food['food_image_url']?.toString() ??
                    'assets/images/food_image0.png',
                food['food_name']?.toString() ?? '이름 없음',
                cardWidth,
                onTap: () => _onFoodSelected(food),
              ),
            )
            .toList(),
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
    final distanceText =
        distance is num ? '거리 ${distance.toStringAsFixed(1)} km' : null;

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
                _isRestaurantLiked(
                        restaurant['name'], restaurant['road_address'])
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: _isRestaurantLiked(
                        restaurant['name'], restaurant['road_address'])
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

  List<TrendItem> get _promotionItems =>
      _trends.isNotEmpty ? _trends : _defaultPromotionItems;

  List<TrendItem> get _defaultPromotionItems => const <TrendItem>[
        TrendItem(
          imageUrl: _defaultPromotionImage,
          title: _defaultPromotionTitle,
          description: _defaultPromotionDescription,
          blogLink: 'https://example.com/guides/get-started',
        ),
        TrendItem(
          imageUrl: 'https://placehold.co/345x220?text=Promo',
          title: '제휴 매장 혜택 모음',
          description: '주변 제휴 매장의 신규 쿠폰과 이벤트를 확인해보세요.',
          blogLink: 'https://example.com/promotions/benefits',
        ),
      ];

  Widget _buildPromotionBanner(double width) {
    final List<TrendItem> items = _promotionItems;
    final int itemCount = items.isNotEmpty ? items.length : 1;
    final bool hasRemoteData = _trends.isNotEmpty;
    final double bannerHeight =
        width <= 0 ? 0 : width * (219.53 / 345.0);

    return SizedBox(
      height: bannerHeight,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: PageView.builder(
              key: ValueKey('${hasRemoteData ? 'remote' : 'fallback'}-$itemCount'),
              controller: _bannerController,
              itemCount: itemCount,
              physics: itemCount > 1
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                if (_currentBannerIndex != index) {
                  setState(() {
                    _currentBannerIndex = index;
                  });
                }
              },
              itemBuilder: (context, index) {
                final TrendItem item = items[index];
                return _buildPromotionSlide(item);
              },
            ),
          ),
          if (itemCount > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: _buildBannerIndicators(itemCount),
            ),
          if (_isTrendLoading && !hasRemoteData)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: Colors.black.withOpacity(0.05),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPromotionSlide(TrendItem item) {
    final bool hasLink = item.hasBlogLink;
    final String title =
        (item.title != null && item.title!.trim().isNotEmpty)
            ? item.title!.trim()
            : _defaultPromotionTitle;
    final String description =
        (item.description != null && item.description!.trim().isNotEmpty)
            ? item.description!.trim()
            : _defaultPromotionDescription;

    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasLink ? () => _handleTrendTap(item.blogLink!) : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildTrendImage(item.imageUrl),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0.5, 0.0),
                      end: Alignment(0.5, 1.0),
                      colors: [
                        Color(0xFFEEEFF1),
                        Color(0xFFEDEEF0),
                        Color(0xFFEBECEE),
                        Color(0xFFEEEFF1),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(15),
                      bottomRight: Radius.circular(15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: const TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildTrendArrowButton(
                        hasLink ? () => _handleTrendTap(item.blogLink!) : null,
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

  Widget _buildTrendArrowButton(VoidCallback? onPressed) {
    final bool isEnabled = onPressed != null;
    return SizedBox(
      width: 39.7,
      height: 40.99,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                right: 6,
                child: Text(
                  '->',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isEnabled ? Colors.black : Colors.black26,
                    fontSize: 26,
                    fontFamily: 'Pretendard Variable',
                    fontWeight: FontWeight.w600,
                    height: 2.31,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerIndicators(int itemCount) {
    if (itemCount <= 1) {
      return const SizedBox.shrink();
    }

    final int activeIndex = _currentBannerIndex % itemCount;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(itemCount, (index) {
        final bool isActive = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 12 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF312E81)
                : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  Widget _buildTrendImage(String imageUrl) {
    final String resolvedUrl =
        imageUrl.trim().isNotEmpty ? imageUrl : _defaultPromotionImage;
    return Image.network(
      resolvedUrl,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, __, ___) => Image.network(
        _defaultPromotionImage,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFE5E7EB),
        ),
      ),
    );
  }

  Widget _buildMenuCard(String imagePath, String title, double width,
      {VoidCallback? onTap}) {
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: padding,
        toolbarHeight: 56,
        title: SizedBox(
          width: 130,
          height: 47,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Would',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.87),
                      fontSize: 23,
                      fontFamily: 'Alkatra',
                      fontWeight: FontWeight.w400,
                      height: 2.61,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'U',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.87),
                      fontSize: 27,
                      fontFamily: 'Alkatra',
                      fontWeight: FontWeight.w500,
                      height: 2.22,
                      letterSpacing: -0.5,
                    ),
                  ),
                  TextSpan(
                    text: 'Like',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.87),
                      fontSize: 23,
                      fontFamily: 'Alkatra',
                      fontWeight: FontWeight.w500,
                      height: 2.61,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: padding),
            child: Tooltip(
              message: 'My coupons',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openCouponList,
                child: Container(
                  width: 29,
                  height: 32,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage('https://placehold.co/29x32'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _showNearby
            ? _loadNearbyRestaurants
            : _refreshFoodsAndRestaurants,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class FoodRestaurantListScreen extends StatefulWidget {
  const FoodRestaurantListScreen(
      {super.key, required this.foodName, this.imageUrl});

  final String foodName;
  final String? imageUrl;

  @override
  State<FoodRestaurantListScreen> createState() =>
      _FoodRestaurantListScreenState();
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
        Uri.parse(
            'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/restaurants/get-random-restaurants/'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'food_names': [widget.foodName],
        }),
      );

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final restaurants =
            (decoded['random_restaurants'] as List<dynamic>? ?? const [])
                .map<Map<String, dynamic>>(
                    (item) => Map<String, dynamic>.from(item as Map))
                .toList();

        final position = await LocationHelper.getLatLon();
        final userLat = position?['lat'] ?? 35.8714;
        final userLon = position?['lon'] ?? 128.6014;

        final mapped = restaurants.map<Map<String, dynamic>>((restaurant) {
          final restLat =
              double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
          final restLon =
              double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
          final distance =
              DistanceCalculator.haversine(userLat, userLon, restLat, restLon);
          return {
            'name': restaurant['name'] ?? '이름 없음',
            'road_address': restaurant['road_address'] ?? '주소 정보 없음',
            'category_2': restaurant['category_2'] ??
                restaurant['category_1'] ??
                '카테고리 정보 없음',
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

    final hasHeaderImage =
        widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final itemCount = _restaurants.length + (hasHeaderImage ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        int dataIndex = index;
        if (hasHeaderImage) {
          if (index == 0) {
            return _FoodHeader(
                imageUrl: widget.imageUrl!, foodName: widget.foodName);
          }
          dataIndex -= 1;
        }

        final restaurant = _restaurants[dataIndex];
        final distance = restaurant['distance'];
        final distanceText =
            distance is num ? '거리 ${distance.toStringAsFixed(1)} km' : null;

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            title: Text(restaurant['name'] ?? '이름 없음'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  restaurant['road_address'] ?? '주소 정보 없음',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                if (distanceText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    distanceText,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  restaurant['category_2'] ?? '카테고리 정보 없음',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
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

