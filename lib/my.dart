import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/start_survey.dart';
class MyScreen extends StatefulWidget {
  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  String uuid = '';
  String typeCode = '';
  String type_name = '';
  String description = '';
  String summary = '';
  String menu_mbti = '';
  String meal_ex = '';
  String matching_type = '';
  String non_matching = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String fullUuid = prefs.getString('user_uuid') ?? '정보 없음';
      String shortUuid = fullUuid.split('-')[0];
      setState(() {
        uuid = shortUuid;
        typeCode = prefs.getString('user_type') ?? '정보 없음';
        type_name = prefs.getString('type_name') ?? '정보 없음';
        description = prefs.getString('type_description') ?? '설명 정보를 불러올 수 없습니다.';
        summary = prefs.getString('type_summary') ?? '정보 없음';
        menu_mbti = prefs.getString('menu_and_mbti') ?? '정보 없음';
        meal_ex = prefs.getString('meal_example') ?? '정보 없음';
        matching_type = prefs.getString('matching_type') ?? '정보 없음';
        non_matching = prefs.getString('non_matching') ?? '정보 없음';
        isLoading = false;
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final textScaleFactor = MediaQuery.of(context).textScaleFactor;

    String imagePath = 'assets/images/$typeCode.png';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Image.asset(
          'assets/images/logo1.png',
          height: screenHeight * 0.03, // 화면 높이에 비례
        ),
      ),
      body: isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Color(0xFF312E81),
        ),
      )
          : SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenHeight * 0.01,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: screenHeight * 0.02),
            _buildInfoContainer(
              screenWidth: screenWidth,
              screenHeight: screenHeight,
              child: Column(
                children: [
                  Text(
                    "당신의 유형은?",
                    style: TextStyle(
                      fontSize: screenWidth * 0.045,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02), // 이미지와 동일 간격
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      imagePath,
                      height: screenHeight * 0.25,
                      width: screenWidth * 0.5,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Text(
                    "$type_name",
                    style: TextStyle(
                      fontSize: screenWidth * 0.045,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.03),
            _buildInfoContainer(
              screenWidth: screenWidth,
              screenHeight: screenHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    icon: Icons.description_outlined,
                    title: "유형 설명",
                    screenWidth: screenWidth,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  _buildText(summary, screenWidth),

                  SizedBox(height: screenHeight * 0.03),
                  _buildSectionTitle(
                    icon: Icons.restaurant_menu_outlined,
                    title: "어울리는 메뉴 및 MBTI",
                    screenWidth: screenWidth,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  _buildText(menu_mbti, screenWidth),

                  SizedBox(height: screenHeight * 0.03),
                  _buildSectionTitle(
                    icon: Icons.fastfood_outlined,
                    title: "추천 식사 예시",
                    screenWidth: screenWidth,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  _buildText(meal_ex, screenWidth),

                  SizedBox(height: screenHeight * 0.03),
                  _buildSectionTitle(
                    icon: Icons.people_alt_outlined,
                    title: "잘 맞는 유형",
                    screenWidth: screenWidth,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  _buildText(matching_type, screenWidth),

                  SizedBox(height: screenHeight * 0.03),
                  _buildSectionTitle(
                    icon: Icons.warning_amber_outlined,
                    title: "잘 맞지 않는 유형",
                    screenWidth: screenWidth,
                  ),
                  SizedBox(height: screenHeight * 0.015),
                  _buildText(non_matching, screenWidth),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.02),
            SizedBox(
              width: double.infinity,
              height: screenHeight * 0.085,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => StartSurveyScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF312E81), // 원하는 색상
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "설문 다시하기",
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Pretendard',
                        fontSize: screenWidth * 0.045,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.005),
                    Text(
                      "새로운 추천을 받고 싶다면 다시 설문을 진행해보세요!",
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Colors.white.withOpacity(0.8),
                        fontSize: screenWidth * 0.032,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: screenHeight * 0.03), // 버튼 아래 여백 추가
          ],
        ),
      ),
    );
  }

  Widget _buildInfoContainer({
    required double screenWidth,
    required double screenHeight,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(0xFF312E81),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF312E81).withOpacity(0.15),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required double screenWidth,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: screenWidth * 0.06,
          color: Color(0xFF312E81),
        ),
        SizedBox(width: screenWidth * 0.03),
        Text(
          title,
          style: TextStyle(
            fontSize: screenWidth * 0.05,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildText(String text, double screenWidth) {
    return Text(
      text,
      style: TextStyle(
        fontSize: screenWidth * 0.04,
        color: Colors.black87,
        height: 1.5,
      ),
    );
  }
}
