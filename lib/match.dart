import 'package:flutter/material.dart';
import 'match_survey.dart';
import 'home.dart';
class MatchingScreen extends StatefulWidget {
  @override
  _MatchingScreenState createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  String? selectedOption;

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        //centerTitle: true,
        title: Image.asset(
          'assets/images/wouldulike.png', // 로고 이미지 경로
          height: 20, // 원하는 높이로 설정
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 16),
              Text(
                '당신의 입맛에 맞춘 특별한 한 끼,\n어떤 선택을 하시겠어요?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildOptionButton(
                      '새로운 스타일의\n식사 도전하기',
                      Icons.restaurant,
                      'new_style',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _buildOptionButton(
                      '익숙하고 편안한\n식사 즐기기',
                      Icons.check,
                      'familiar_style',
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Container(
                width: double.infinity, // 부모 위젯에 맞춰 너비를 유동적으로 설정
                constraints: BoxConstraints(maxWidth: 362), // 최대 너비를 제한
                padding: EdgeInsets.all(20), // Padding은 Container에서 직접 설정
                decoration: ShapeDecoration(
                  color: Color(0xFFEFF6FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(topRight: Radius.circular(35)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '오늘 뭐 먹지? 이젠 더 이상 고민하지 마세요!',
                      style: TextStyle(
                        color: Color(0xFF354C97),
                        fontSize: 16,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '오늘 우리의 입맛 유형을 확인합니다!',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '모두의 입맛을 사로잡을 추천 메뉴와 맛집까지\n한 번에 알아봐요!',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              Spacer(),
              Container(
                width: double.infinity,
                height: 67.91,
                margin: EdgeInsets.only(bottom: 8),
                child: ElevatedButton(
                  onPressed: selectedOption != null
                      ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SurveyScreen()),
                    );
                  }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF03037C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '테스트 시작하기\n',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: '1분 안에 우리의 입맛 유형 확인하기',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton(String text, IconData icon, String option) {
    bool isSelected = selectedOption == option;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedOption = option;
        });
      },
      child: Container(
        height: 196,
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFF5F7FF) : Colors.white,
          border: Border.all(
            color: isSelected ? Color(0xFF3D3DFF) : Colors.grey[300]!,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Color(0xFF3D3DFF) : Colors.grey[600],
              size: 24,
            ),
            SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Color(0xFF3D3DFF) : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}