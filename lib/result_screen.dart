import 'package:flutter/material.dart';
import 'food_recommendation_screen.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.totalScore,
    required this.selectedQuestions,
    required this.resetQuiz,
  });

  final int totalScore;
  final List<String> selectedQuestions;
  final Function resetQuiz;

  String getTypeDescription(String type) {
    final descriptions = {
      '1형': '일정도의 태양처럼 건고하게, 같은 맛과 독특한 풍미를 미를 선호하는 당신!',
      '2형': '마음이 따뜻한 달빛처럼, 부드럽고 달콤한 맛을 선호하는 당신!',
      '3형': '바람처럼 자유로운, 매콤하고 자극적인 맛을 선호하는 당신!',
      '4형': '구름처럼 포근한, 담백하고 깔끔한 맛을 선호하는 당신!'
    };
    return descriptions[type] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    String resultMessage;

    if (totalScore == 1111) {
      resultMessage = 'IYFW';
    } else if (totalScore == 2111) {
      resultMessage = 'SYFW';
    } else if (totalScore == 1211) {
      resultMessage = 'INFW';
    } else if (totalScore == 2211) {
      resultMessage = 'SNFW';
    } else if(totalScore == 1121){
      resultMessage = 'IYJW';
    } else if (totalScore == 2121) {
      resultMessage = 'SYJW';
    } else if (totalScore == 1221) {
      resultMessage = 'INJW';
    } else if (totalScore == 2221) {
      resultMessage = 'SNJW';
    } else if(totalScore == 1112){
      resultMessage = 'IYFE';
    } else if (totalScore == 2112) {
      resultMessage = 'SYFE';
    } else if (totalScore == 1212) {
      resultMessage = 'INFE';
    } else if (totalScore == 2212) {
      resultMessage = 'SNFE';
    } else if(totalScore == 1122){
      resultMessage = 'IYJE';
    } else if (totalScore == 2122) {
      resultMessage = 'SYJE';
    } else if (totalScore == 1222) {
      resultMessage = 'INJE';
    } else {
      resultMessage = 'SNJE';
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final screenWidth = constraints.maxWidth;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.00, -0.00),
                end: Alignment(1, 0),
                colors: [
                  Color(0xFFF8F5FF),
                  Color(0xFFF6F5FF),
                  Color(0xFFF5F5FF),
                  Color(0xFFF4F5FF),
                  Color(0xFFF1F5FF),
                  Color(0xFFF1F5FF),
                  Color(0xFFEFF6FF)
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: screenHeight * 0.1), // 상단 여백
                Text(
                  '당신의 음식 취향 분석 결과',
                  style: TextStyle(
                    fontSize: screenHeight * 0.03,
                    color: const Color(0xFF312E81),
                  ),
                ),
                SizedBox(height: screenHeight * 0.02), // 제목 아래 여백
                Container(
                  width: screenWidth * 0.5,
                  height: screenWidth * 0.5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4E6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                SizedBox(height: screenHeight * 0.02), // 이미지 아래 여백
                Text(
                  resultMessage,
                  style: TextStyle(
                    fontSize: screenHeight * 0.05,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF312E81),
                  ),
                ),
                SizedBox(height: screenHeight * 0.00001), // 결과 아래 여백
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
                  child: Text(
                    getTypeDescription(resultMessage),
                    style: TextStyle(
                      fontSize: screenHeight * 0.02,
                      color: const Color(0xFF4B5563),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: screenHeight * 0.0001), // 설명 아래 여백
                Container(
                  width: screenWidth * 0.95, // 너비를 화면의 95%로 확대
                  padding: EdgeInsets.all(screenHeight * 0.03), // 내부 여백 확대
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12), // 둥글기 조금 더 확대
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 6, // 그림자 크기 조정
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '당신의 특징',
                        style: TextStyle(
                          fontSize: screenHeight * 0.03, // 글자 크기 확대
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1F2937),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.015), // 텍스트 아래 여백
                      Text(
                        '여기에 당신의 특징과 관련된 정보를 추가하세요.\n여기에 당신의 특징과 관련된 정보를 추가하세요.\n여기에 당신의 특징과 관련된 정보를 추가하세요.',
                        style: TextStyle(
                          fontSize: screenHeight * 0.02, // 내용 글자 크기
                          color: const Color(0xFF4B5563),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: screenHeight * 0.03), // 특징 아래 여백
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity, // 버튼 크기 맞추기
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => FoodRecommendationScreen(
                              resultMessage: resultMessage,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF312E81),
                        padding: const EdgeInsets.symmetric(vertical: 16), // 첫 번째 버튼과 동일한 패딩
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "음식 추천받기", // 텍스트 스타일 그대로 유지
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18, // 첫 번째 버튼과 동일한 텍스트 크기
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.02), // 버튼 아래 여백
              ],
            ),
          );
        },
      ),
    );
  }
}
