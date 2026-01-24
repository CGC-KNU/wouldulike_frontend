import 'package:flutter/material.dart';
import 'food_recommendation_screen.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.totalScore,
    required this.selectedQuestions,
    required this.resetQuiz,
  });

  final int totalScore;
  final List<String> selectedQuestions;
  final Function resetQuiz;
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static const String _resultDescription =
      '설문 결과가 준비되었습니다. 아래에서 추천 음식을 확인해 보세요.';

  @override
  Widget build(BuildContext context) {
    const String imagePath = 'assets/images/food_image0.png';
    final size = MediaQuery.of(context).size;
    final padding = size.width * 0.05; // 5% padding

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.06),
              Text(
                '테스트 결과',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: size.width * 0.055,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: size.height * 0.005),
              Text(
                '설문 결과를 바탕으로 추천을 준비했어요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: size.width * 0.032,
                  fontWeight: FontWeight.w300,
                  color: const Color(0xFF6B7280),
                ),
              ),
              SizedBox(height: size.height * 0.02),
              Expanded(
                child: Container(
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
                          child: Image.asset(
                            imagePath,
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
                              '설문 결과 요약',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: size.width * 0.055,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: size.height * 0.01),
                            Text(
                              _resultDescription,
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
                ),
              ),
              SizedBox(height: size.height * 0.03),
              SizedBox(
                width: double.infinity,
                height: size.height * 0.085,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const FoodRecommendationScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF312E81),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "음식 추천받기",
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'Pretendard',
                          fontSize: size.width * 0.045,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "오늘의 메뉴를 추천해드릴게요!",
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: Colors.white.withOpacity(0.8),
                          fontSize: size.width * 0.032,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: size.height * 0.03),
            ],
          ),
        ),
      ),
    );
  }
}
