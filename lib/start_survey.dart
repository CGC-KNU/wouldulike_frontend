import 'package:flutter/material.dart';
import 'question_screen.dart'; // QuizScreen 임포트

class StartSurveyScreen extends StatefulWidget {
  const StartSurveyScreen({super.key});

  @override
  _StartSurveyScreenState createState() => _StartSurveyScreenState();
}

class _StartSurveyScreenState extends State<StartSurveyScreen> {
  double _opacityFirstText = 0.0;
  double _opacitySecondText = 0.0;

  @override
  void initState() {
    super.initState();
    _startAnimations();
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 1000)); // 첫 번째 텍스트 지연
    setState(() {
      _opacityFirstText = 1.0;
    });

    await Future.delayed(const Duration(milliseconds: 1000)); // 두 번째 텍스트 지연
    setState(() {
      _opacitySecondText = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.white, // 배경색 흰색 유지
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: screenHeight * 0.35),
              child: const Text(
                '입맛 유형 테스트',
                style: TextStyle(
                  fontFamily: "Pretendard-Bold",
                  fontWeight: FontWeight.w700,
                  fontSize: 36,
                  color: Color(0xFF1E2761),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: screenHeight * 0.45),
              child: Column(
                children: [
                  AnimatedOpacity(
                    opacity: _opacityFirstText,
                    duration: const Duration(milliseconds: 1700),
                    child: const Text(
                      '무엇을 먹을지 고민이라면?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        letterSpacing: -0.5, // 글자 간격 줄이기
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  AnimatedOpacity(
                    opacity: _opacitySecondText,
                    duration: const Duration(milliseconds: 1700),
                    child: const Text(
                      '당신의 음식 취향 유형을 탐험해보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        letterSpacing: -0.5, // 글자 간격 줄이기
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: screenHeight * 0.1),
              child: SizedBox(
                width: screenWidth * 0.8,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => QuizScreen(
                          questionIndex: 0,
                          answerPressed: (score) {},
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF312E81),
                    padding:
                    EdgeInsets.symmetric(vertical: screenHeight * 0.025),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '테스트 시작하기',
                        style: TextStyle(
                          fontFamily: "Pretendard-SemiBold",
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '2분 만에 나의 음식 취향 확인하기',
                        style: TextStyle(
                          fontFamily: "Pretendard-Regular",
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
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