import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:new1/main2.dart';

class MatchRecommendationScreen extends StatelessWidget {
  final String resultType;

  const MatchRecommendationScreen({super.key, required this.resultType});

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

    // 유형별 추천 음식 데이터 정의
    List<List<Map<String, String>>> foodData = [
      [
        {"image": "assets/images/food_image0.png", "title": "한방 닭 백숙", "description": "한약재의 깊은 풍미가 더해져 건강에 좋고, 특히 체력 회복과 면역력 강화에 효과적입니다! 담백하고 진한 국물로 몸을 녹여보아요."},
        {"image": "assets/images/food_image0.png", "title": "영양 고추장 불고기", "description": "매콤달콤한 양념이 입맛을 돋구며 고단백질로 영양을 채워줍니다."},
        {"image": "assets/images/food_image0.png", "title": "김치 볶음밥", "description": "한국인의 소울푸드, 고소한 참기름과 김치의 만남! 간단하지만 맛있는 한 끼 식사입니다."}
      ],
      // 다른 유형의 데이터들 추가
      [
        {"image": "assets/images/food_image0.png", "title": "한방 닭 백숙", "description": "한약재의 깊은 풍미가 더해져 건강에 좋고, 특히 체력 회복과 면역력 강화에 효과적입니다! 담백하고 진한 국물로 몸을 녹여보아요."},
        {"image": "assets/images/food_image0.png", "title": "영양 고추장 불고기", "description": "매콤달콤한 양념이 입맛을 돋구며 고단백질로 영양을 채워줍니다."},
        {"image": "assets/images/food_image0.png", "title": "김치 볶음밥", "description": "한국인의 소울푸드, 고소한 참기름과 김치의 만남! 간단하지만 맛있는 한 끼 식사입니다."}
      ],
      [
        {"image": "assets/images/food_image0.png", "title": "한방 닭 백숙", "description": "한약재의 깊은 풍미가 더해져 건강에 좋고, 특히 체력 회복과 면역력 강화에 효과적입니다! 담백하고 진한 국물로 몸을 녹여보아요."},
        {"image": "assets/images/food_image0.png", "title": "영양 고추장 불고기", "description": "매콤달콤한 양념이 입맛을 돋구며 고단백질로 영양을 채워줍니다."},
        {"image": "assets/images/food_image0.png", "title": "김치 볶음밥", "description": "한국인의 소울푸드, 고소한 참기름과 김치의 만남! 간단하지만 맛있는 한 끼 식사입니다."}
      ]
    ];

    // 결과 유형에 따른 데이터 선택
    List<Map<String, String>> selectedFoods = foodData[resultType == "1형" ? 0 : 1];
    final pageController = PageController();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: screenHeight * 0.1),
          // 상단 텍스트
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "예민한 $resultType 유형",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "입맛 유형을 기반으로 오늘의 메뉴를 추천해드립니다.",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          // 카드 섹션
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: selectedFoods.length,
              itemBuilder: (context, index) {
                final food = selectedFoods[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Container(
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
                        // 배경 이미지
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            food["image"]!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // 텍스트 섹션
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  food["title"]!,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  food["description"]!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
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
          // 페이지 인디케이터
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Center(
              child: SmoothPageIndicator(
                controller: pageController,
                count: selectedFoods.length,
                effect: const WormEffect(
                  dotColor: Colors.grey,
                  activeDotColor: Color(0xFF312E81),
                  dotHeight: 8,
                  dotWidth: 8,
                ),
              ),
            ),
          ),
          // 홈으로 가기 버튼
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
                    borderRadius: BorderRadius.circular(8),
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
