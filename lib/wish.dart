import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:new1/utils/location_helper.dart';
import 'package:new1/utils/distance_calculator.dart';

class WishlistScreen extends StatefulWidget {
  @override
  _WishlistScreenState createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<Map<String, dynamic>> likedRestaurants = [];
  List<Map<String, dynamic>> filteredRestaurants = [];
  late SharedPreferences prefs;
  String? selectedDistrict;
  String? selectedCategory;
  List<String> uniqueDistricts = [];
  List<String> uniqueCategories = [];
  bool isDistrictFilter = true;

  String extractDistrict(String address) {
    try {
      final regex = RegExp(r'대구광역시\s+([^\s]+(구|군))');
      final match = regex.firstMatch(address);
      return match?.group(1) ?? '기타';
    } catch (e) {
      return '기타';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLikedRestaurants();
  }
  void _onToggleFilter(int index) {
    setState(() {
      isDistrictFilter = (index == 0);
      // 필터 초기화
      selectedDistrict = null;
      selectedCategory = null;
      // 전체 리스트로 초기화
      filteredRestaurants = likedRestaurants;
      //debugPrint('토글 변경: ${isDistrictFilter ? "지역" : "카테고리"} 필터');
      //debugPrint('필터 초기화됨: 전체 리스트 표시');
    });
  }


  Future<void> _loadLikedRestaurants() async {
    prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> likedList = [];

    // 사용자 현재 위치 받아오기
    final position = await LocationHelper.getLatLon();
    final double userLat = position?['lat'] ?? 35.8714;
    final double userLon = position?['lon'] ?? 128.6014;

    final String? savedRestaurants = prefs.getString('restaurants_data');
    if (savedRestaurants != null) {
      final List<Map<String, dynamic>> currentRestaurants =
      List<Map<String, dynamic>>.from(json.decode(savedRestaurants));

      for (var restaurant in currentRestaurants) {
        final name = restaurant['name'] ?? '이름 없음';
        final address = restaurant['road_address'] ?? '주소 없음';
        final isLiked = prefs.getBool('liked_${name}_${address}') ?? false;

        if (isLiked) {
          // 거리 계산
          final double restLat = double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
          final double restLon = double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
          final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);

          likedList.add({
            'name': name,
            'road_address': address,
            'category_1': restaurant['category_1'] ?? '카테고리 없음',
            'category_2': restaurant['category_2'] ?? '카테고리 없음',
            'x': restLon.toString(),
            'y': restLat.toString(),
            'distance': distance,
          });
        }
      }
    }

    final String? savedLikedAll = prefs.getString('liked_restaurants_all');
    if (savedLikedAll != null) {
      final Map<String, dynamic> allLikedRestaurants = json.decode(savedLikedAll);

      allLikedRestaurants.forEach((key, restaurant) {
        if (!likedList.any((r) =>
        r['name'] == restaurant['name'] &&
            r['road_address'] == restaurant['road_address'])) {
          final double restLat = double.tryParse(restaurant['y']?.toString() ?? '') ?? 35.8714;
          final double restLon = double.tryParse(restaurant['x']?.toString() ?? '') ?? 128.6014;
          final distance = DistanceCalculator.haversine(userLat, userLon, restLat, restLon);

          restaurant['category_1'] ??= '카테고리 없음';
          restaurant['distance'] = distance;
          likedList.add(restaurant);
        }
      });
    }

    setState(() {
      likedRestaurants = likedList;
      filteredRestaurants = likedList;

      uniqueDistricts = likedRestaurants
          .map((r) => extractDistrict(r['road_address']))
          .where((d) => d != '기타')
          .toSet()
          .toList()
        ..sort();

      uniqueCategories = likedRestaurants
          .map((r) => r['category_1'] ?? '카테고리 없음')
          .where((c) => c != '카테고리 없음')
          .cast<String>()
          .toSet()
          .toList()
        ..sort();
    });

    final Map<String, dynamic> updatedLikedAll = {};
    for (var restaurant in likedList) {
      final key = '${restaurant['name']}|${restaurant['road_address']}';
      updatedLikedAll[key] = restaurant;
    }
    await prefs.setString('liked_restaurants_all', json.encode(updatedLikedAll));
  }

  void _applyFilters() {
    setState(() {
      filteredRestaurants = likedRestaurants.where((restaurant) {
        bool matchesDistrict = selectedDistrict == null ||
            extractDistrict(restaurant['road_address']) == selectedDistrict;
        bool matchesCategory = selectedCategory == null ||
            restaurant['category_1'] == selectedCategory;

        return isDistrictFilter ? matchesDistrict : matchesCategory;
      }).toList();

      //debugPrint('필터 적용 후 리스트: ${filteredRestaurants.map((e) => e['name'])}');
      //debugPrint('Current filter type: ${isDistrictFilter ? "District" : "Category"}');
      //debugPrint('Selected District: $selectedDistrict');
      //debugPrint('Selected Category: $selectedCategory');
    });
  }

  void _filterRestaurants(String? district) {
    setState(() {
      selectedDistrict = district;
      if (isDistrictFilter) {
        selectedCategory = null;
      }
      _applyFilters();
    });
  }

  void _filterByCategory(String? category) {
    setState(() {
      selectedCategory = category;
      if (!isDistrictFilter) {
        selectedDistrict = null;
      }
      _applyFilters();
    });
  }

  Future<void> _removeFavorite(String name, String address) async {
    await prefs.setBool('liked_${name}_${address}', false);

    final String? savedLikedAll = prefs.getString('liked_restaurants_all');
    if (savedLikedAll != null) {
      Map<String, dynamic> allLikedRestaurants = json.decode(savedLikedAll);
      allLikedRestaurants.remove('$name|$address');
      await prefs.setString('liked_restaurants_all', json.encode(allLikedRestaurants));
    }

    setState(() {
      likedRestaurants.removeWhere(
              (restaurant) => restaurant['name'] == name && restaurant['road_address'] == address);
      _applyFilters();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('찜 목록에서 제거되었습니다.'),
        duration: const Duration  (seconds: 1),
      ),
    );
  }
  //bool isDistrictFilter = true; // true: 구/군 필터, false: 카테고리 필터

  @override
  Widget build(BuildContext context) {
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
      body: Column(
        children: [
          // 필터 전환 버튼
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ToggleButtons(
              borderRadius: BorderRadius.circular(20),
              borderColor: Colors.grey[300],
              selectedBorderColor: Color(0xFF4A55A4),
              fillColor: Color(0xFF312E81),
              selectedColor: Colors.white,
              color: Colors.black54,
              isSelected: [isDistrictFilter, !isDistrictFilter],
              onPressed: (index) {
                _onToggleFilter(index);
              },
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text("구/군"),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text("카테고리"),
                ),
              ],
            ),
          ),

          // 필터 영역
          Container(
            color: Colors.white,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), // 좌우 패딩 줄임
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 4개 칩이 들어갈 수 있도록 너비 계산
                      final double chipWidth = (constraints.maxWidth - 24) / 4; // 간격 줄임

                      return Wrap(
                        spacing: 4.0,  // 칩 사이 간격 줄임
                        runSpacing: 8.0,
                        alignment: WrapAlignment.start,
                        children: [
                          // "전체" 버튼
                          SizedBox(
                            width: chipWidth,
                            child: FilterChip(
                              selected: isDistrictFilter
                                  ? selectedDistrict == null
                                  : selectedCategory == null,
                              checkmarkColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 4.0), // 칩 내부 패딩 줄임
                              label: Text(
                                '전체(${likedRestaurants.length})',
                                style: TextStyle(
                                  color: (isDistrictFilter
                                      ? selectedDistrict == null
                                      : selectedCategory == null)
                                      ? Colors.white
                                      : Colors.black54,
                                  fontSize: 12, // 글자 크기 약간 줄임
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              backgroundColor: Colors.white,
                              selectedColor: Color(0xFF312E81),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: (isDistrictFilter
                                      ? selectedDistrict == null
                                      : selectedCategory == null)
                                      ? Color(0xFF4A55A4)
                                      : Colors.grey[300]!,
                                ),
                              ),
                              onSelected: (bool selected) {
                                if (selected) {
                                  isDistrictFilter
                                      ? _filterRestaurants(null)
                                      : _filterByCategory(null);
                                }
                              },
                            ),
                          ),

                          // 필터 리스트 (구/군 또는 카테고리)
                          ...(isDistrictFilter ? uniqueDistricts : uniqueCategories)
                              .map((item) {
                            final count = likedRestaurants
                                .where((r) => isDistrictFilter
                                ? extractDistrict(r['road_address']) == item
                                : r['category_1'] == item)
                                .length;

                            return SizedBox(
                              width: chipWidth,
                              child: FilterChip(
                                selected: isDistrictFilter
                                    ? selectedDistrict == item
                                    : selectedCategory == item,
                                checkmarkColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 4.0), // 칩 내부 패딩 줄임
                                label: Text(
                                  '$item($count)',
                                  style: TextStyle(
                                    color: (isDistrictFilter
                                        ? selectedDistrict == item
                                        : selectedCategory == item)
                                        ? Colors.white
                                        : Colors.black54,
                                    fontSize: 12, // 글자 크기 약간 줄임
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                backgroundColor: Colors.white,
                                selectedColor: Color(0xFF312E81),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: (isDistrictFilter
                                        ? selectedDistrict == item
                                        : selectedCategory == item)
                                        ? Color(0xFF4A55A4)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                onSelected: (bool selected) {
                                  if (selected) {
                                    isDistrictFilter
                                        ? _filterRestaurants(item)
                                        : _filterByCategory(item);
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: Colors.grey[300]),
              ],
            ),
          ),

          // 리스트 영역
          Expanded(
            child: filteredRestaurants.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 48,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '찜한 음식점이 없습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: EdgeInsets.all(16.0),
              itemCount: filteredRestaurants.length,
              itemBuilder: (context, index) {
                final restaurant = filteredRestaurants[index];
                return Container(
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
                                  restaurant['name'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  restaurant['road_address'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  restaurant['distance'] != null
                                      ? '거리: ${restaurant['distance'].toStringAsFixed(1)} km'
                                      : '거리 정보 없음',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
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
                            Icons.favorite,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeFavorite(
                            restaurant['name'],
                            restaurant['road_address'],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}