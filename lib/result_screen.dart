import 'package:flutter/material.dart';
import 'food_recommendation_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
  String _typeDescription = ' ';
  late String resultMessage;
  String _typeName = ' ';
  bool _isloading = true;
  @override
  void initState() {
    super.initState();
    _initializeData();
  }
  Future<void> _initializeData() async {
    resultMessage = _getResultMessage();
    //print('Starting API calls with resultMessage: $resultMessage');

    try {
      //print('Calling sendResultMessage...');
      await sendResultMessage(resultMessage);
      //print('sendResultMessage completed');
      //print('Calling fetchDescription...');
      String description = await fetchDescription(resultMessage);

      await fetchAllData(resultMessage);
      //print('fetchDescription completed');
      setState(() {
        _typeDescription = description;
      });
      //print('Fetching user data...');
      //await fetchUserData(); // 추가된 부분
    } catch (e) {
      print('Error in _initializeData: $e');
      setState(() {
        _typeDescription = '설명을 불러오는데 실패했습니다.';
      });
    } finally{
      setState(() {
        _isloading = false;
      });
    }
  }
  /*
  Future<void> fetchUserData() async {

    try {
      final prefs = await SharedPreferences.getInstance();
      final uuid = prefs.getString('user_uuid');

      if (uuid == null) {
        print('UUID not found');
        return;
      }
      final url = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/retrieve/?uuid=$uuid');
      // API 호출
      final response = await http.get(url);

      if (response.statusCode == 200) {
        // JSON 파싱
        final data = jsonDecode(response.body);

        // 필요한 값 추출
        final uuid = data['uuid'];
        final typeCode = data['type_code'];
        final favoriteRestaurants = data['favorite_restaurants'];

        // 콘솔에 출력
        print('UUID: $uuid');
        print('Type Code: $typeCode');
        print('Favorite Restaurants: $favoriteRestaurants');
      } else {
        print('Failed to fetch data. Status code: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching data: $error');
    }
  }
  */
  String _getResultMessage() {
    if (widget.totalScore == 1111) return 'IYFW';
    if (widget.totalScore == 2111) return 'SYFW';
    if (widget.totalScore == 1211) return 'INFW';
    if (widget.totalScore == 2211) return 'SNFW';
    if (widget.totalScore == 1121) return 'IYJW';
    if (widget.totalScore == 2121) return 'SYJW';
    if (widget.totalScore == 1221) return 'INJW';
    if (widget.totalScore == 2221) return 'SNJW';
    if (widget.totalScore == 1112) return 'IYFE';
    if (widget.totalScore == 2112) return 'SYFE';
    if (widget.totalScore == 1212) return 'INFE';
    if (widget.totalScore == 2212) return 'SNFE';
    if (widget.totalScore == 1122) return 'IYJE';
    if (widget.totalScore == 2122) return 'SYJE';
    if (widget.totalScore == 1222) return 'INJE';
    return 'SNJE';
  }


  Future<void> sendResultMessage(String resultMessage) async {
    // Base URL 설정
    final baseUrl = 'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/guests/update/type_code';

    try {
      // SharedPreferences에서 UUID 가져오기
      final prefs = await SharedPreferences.getInstance();
      final uuid = prefs.getString('user_uuid'); // 저장된 키 이름 확인 필요
      //print('UUID : $uuid');

      if (uuid == null) {
        //print('UUID가 null입니다. SharedPreferences에서 값을 확인하세요.');
        return;
      }

      // URL에 쿼리스트링 추가
      final url = Uri.parse('$baseUrl?uuid=$uuid&type_code=$resultMessage');

      // GET 요청 (fetch와 유사한 방식)
      final response = await http.get(url);
      if(response.statusCode == 200){
        await prefs.setString('user_type', resultMessage);
        //print('Type saved to sharedPreferences: $resultMessage');
      }
      //print('Response status: ${response.statusCode}');
      //print('Response body: ${response.body}');
    } catch (error) {
      print('Error: $error');
    }
  }


  Future<String> fetchDescription(String resultMessage) async {
    //print('Trying to fetch description for type: $resultMessage');
    final url = Uri.parse(
        'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/type-descriptions/type-descriptions/${resultMessage}/');
    //print('Request URL: $url');
    final prefs = await SharedPreferences.getInstance();
    try {
      // 단순화된 GET 요청
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        //print('Response body: ${response.body}');
        final description = responseData['description'];
        await prefs.setString('type_description', description);
        //print('Description saved to SharedPreferences');
        return description;
      } else {
        throw Exception('Failed to fetch description: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching description: $error');
      rethrow;
    }
  }

  Future<void> fetchAllData(String resultMessage) async{
    final url = Uri.parse('https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/type-descriptions/type-descriptions/all/${resultMessage}/');
    final prefs = await SharedPreferences.getInstance();
    try{
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Response body: ${response.body}');
        final summary = responseData['type_summary'];
        final menu_mbti = responseData['menu_and_mbti'];
        final meal_ex = responseData['meal_example'];
        final matching_type = responseData['matching_type'];
        final non_matching = responseData['non_matching_type'];
        final type_name = responseData['type_name'];
        await prefs.setString('type_summary', summary);
        await prefs.setString('menu_and_mbti', menu_mbti);
        await prefs.setString('meal_example', meal_ex);
        await prefs.setString('matching_type', matching_type);
        await prefs.setString('non_matching', non_matching);
        await prefs.setString('type_name', type_name);
        print('Description saved to SharedPreferences');
        setState(() {
          _typeName = responseData['type_name'];
        });
      } else {
        throw Exception('Failed to fetch description: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching description: $error');
      rethrow;
    }
  }
  @override
  Widget build(BuildContext context) {
    String imagePath = 'assets/images/$resultMessage.png';
    final size = MediaQuery.of(context).size;
    final padding = size.width * 0.05; // 5% padding

    return Scaffold(
      backgroundColor: Colors.white,
      body: _isloading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.grey,
              strokeWidth: 4.0,
            ),
            SizedBox(height: size.height * 0.02),
            Text(
              '취향 분석 중..!',
              style: TextStyle(
                fontSize: size.width * 0.05,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      )
          : SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.06),
              Text(
                '입맛 유형 테스트 결과',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: size.width * 0.055,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: size.height * 0.005),
              Text(
                '당신의 입맛을 똑 닮은 우주라이크 캐릭터를 만나보세요!',
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
                      // 이미지
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            imagePath,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      // 그라데이션 오버레이
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
                      // 텍스트 내용
                      Positioned(
                        left: padding,
                        right: padding,
                        bottom: padding * 1.5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '유형 $resultMessage',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: size.width * 0.055,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: size.height * 0.01),
                            Text(
                              _typeDescription,
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
                        builder: (context) => FoodRecommendationScreen(
                          resultMessage: resultMessage,
                        ),
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
                        "당신의 입맛에 맞는 음식을 추천받아요!",
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