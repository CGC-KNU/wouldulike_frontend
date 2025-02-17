import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class WishlistScreen extends StatefulWidget {
  @override
  _WishlistScreenState createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<Map<String, dynamic>> likedRestaurants = [];
  List<Map<String, dynamic>> filteredRestaurants = [];
  late SharedPreferences prefs;
  String? selectedDistrict;
  List<String> uniqueDistricts = [];

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

  Future<void> _loadLikedRestaurants() async {
    prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> likedList = [];

    // 1. 현재 restaurants_data 확인
    final String? savedRestaurants = prefs.getString('restaurants_data');
    if (savedRestaurants != null) {
      final List<Map<String, dynamic>> currentRestaurants = List<Map<String, dynamic>>.from(
          json.decode(savedRestaurants).map((restaurant) => {
            'name': restaurant['name'] ?? '이름 없음',
            'road_address': restaurant['road_address'] ?? '주소 없음',
            'category_2': restaurant['category_2'] ?? '카테고리 없음',
          })
      );

      // 현재 음식점들 중 찜한 것들 확인
      for (var restaurant in currentRestaurants) {
        String name = restaurant['name'];
        String address = restaurant['road_address'];
        bool isLiked = prefs.getBool('liked_${name}_${address}') ?? false;

        if (isLiked) {
          likedList.add(restaurant);
        }
      }
    }

    // 2. 이전에 찜한 목록 확인
    final String? savedLikedAll = prefs.getString('liked_restaurants_all');
    if (savedLikedAll != null) {
      Map<String, dynamic> allLikedRestaurants = json.decode(savedLikedAll);

      // 이전 찜 목록에서 현재 리스트에 없는 것들 추가
      allLikedRestaurants.forEach((key, restaurant) {
        if (!likedList.any((r) =>
        r['name'] == restaurant['name'] &&
            r['road_address'] == restaurant['road_address'])) {
          likedList.add(restaurant);
        }
      });
    }

    setState(() {
      likedRestaurants = likedList;
      filteredRestaurants = likedList;  // 여기서 filteredRestaurants도 같이 초기화

      // 구 목록 업데이트
      uniqueDistricts = likedRestaurants
          .map((restaurant) => extractDistrict(restaurant['road_address']))
          .where((district) => district != '기타')
          .toSet()
          .toList()
        ..sort();
    });

    // 전체 찜 목록 업데이트
    Map<String, dynamic> updatedLikedAll = {};
    for (var restaurant in likedList) {
      String key = '${restaurant['name']}|${restaurant['road_address']}';
      updatedLikedAll[key] = restaurant;
    }
    await prefs.setString('liked_restaurants_all', json.encode(updatedLikedAll));

    //print('찜한 음식점 목록: $likedRestaurants');
  }
  void _filterRestaurants(String? district) {
    setState(() {
      selectedDistrict = district;
      if (district == null || district.isEmpty) {
        filteredRestaurants = likedRestaurants;
      } else {
        filteredRestaurants = likedRestaurants
            .where((restaurant) => extractDistrict(restaurant['road_address']) == district)
            .toList();
      }
    });
  }
  Future<void> _removeFavorite(String name, String address) async {
    // 개별 찜하기 상태 제거
    await prefs.setBool('liked_${name}_${address}', false);

    // 전체 찜 목록에서도 제거
    final String? savedLikedAll = prefs.getString('liked_restaurants_all');
    if (savedLikedAll != null) {
      Map<String, dynamic> allLikedRestaurants = json.decode(savedLikedAll);
      allLikedRestaurants.remove('$name|$address');
      await prefs.setString('liked_restaurants_all', json.encode(allLikedRestaurants));
    }

    setState(() {
      likedRestaurants.removeWhere(
              (restaurant) =>
          restaurant['name'] == name &&
              restaurant['road_address'] == address
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('찜 목록에서 제거되었습니다.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

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
          // 필터 영역
          Container(
            color: Colors.white,
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Wrap(
                    spacing: 8.0,
                    children: [
                      FilterChip(
                        selected: selectedDistrict == null,
                        checkmarkColor: Colors.white,
                        label: Text(
                          '전체(${likedRestaurants.length})',
                          style: TextStyle(
                            color: selectedDistrict == null ? Colors.white : Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        backgroundColor: Colors.white,
                        selectedColor: Color(0xFF312E81),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: selectedDistrict == null ? Color(0xFF4A55A4) : Colors.grey[300]!,
                          ),
                        ),
                        onSelected: (bool selected) {
                          if (selected) {
                            _filterRestaurants(null);
                          }
                        },
                      ),
                      ...uniqueDistricts.map((district) {
                        final count = likedRestaurants
                            .where((r) => extractDistrict(r['road_address']) == district)
                            .length;
                        return FilterChip(
                          selected: selectedDistrict == district,
                          checkmarkColor: Colors.white,
                          label: Text(
                            '$district($count)',
                            style: TextStyle(
                              color: selectedDistrict == district ? Colors.white : Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                          backgroundColor: Colors.white,
                          selectedColor: Color(0xFF312E81),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: selectedDistrict == district ? Color(0xFF4A55A4) : Colors.grey[300]!,
                            ),
                          ),
                          onSelected: (bool selected) {
                            if (selected) {
                              _filterRestaurants(district);
                            }
                          },
                        );
                      }).toList(),
                    ],
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
                              restaurant['road_address']
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