import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyScreen extends StatefulWidget {
  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  String uuid = '';
  String typeCode = '';
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
    String imagePath = 'assets/images/$typeCode.png';
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
      body: isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Color(0xFF312E81),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
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
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      imagePath,
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    "당신의 유형: $typeCode",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "게스트 ID: $uuid",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 유형 설명 섹션
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 24,
                        color: Color(0xFF312E81),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "유형 설명",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    summary,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 24),

                  // 어울리는 메뉴 및 MBTI 섹션
                  Row(
                    children: [
                      Icon(
                        Icons.restaurant_menu_outlined,
                        size: 24,
                        color: Color(0xFF312E81),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "어울리는 메뉴 및 MBTI",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    menu_mbti,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 24),

                  // 추천 식사 예시 섹션
                  Row(
                    children: [
                      Icon(
                        Icons.fastfood_outlined,
                        size: 24,
                        color: Color(0xFF312E81),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "추천 식사 예시",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    meal_ex,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 24),

                  // 잘 맞는 유형 섹션
                  Row(
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 24,
                        color: Color(0xFF312E81),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "잘 맞는 유형",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    matching_type,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 24),

                  // 잘 맞지 않는 유형 섹션
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 24,
                        color: Color(0xFF312E81),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "잘 맞지 않는 유형",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    non_matching,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}