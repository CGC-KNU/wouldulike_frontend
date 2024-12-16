import 'package:flutter/material.dart';
import 'match_recommendation.dart';

class MatchSurvey2 extends StatefulWidget {
  final int totalScore;

  MatchSurvey2({required this.totalScore});

  @override
  _MatchSurvey2State createState() => _MatchSurvey2State();
}

class _MatchSurvey2State extends State<MatchSurvey2> {
  int? spicyRating;
  int? sweetRating;
  int? sourRating;
  Set<String> selectedKeywords = {};

  final List<String> keywords = [
    '매콤한', '짭짤한', '매운맛', '달콤한', '기름진', '바삭한', '고소한', '부드러운',
  ];

  // `resultType` 계산 함수
  String calculateResultType() {
    int total = widget.totalScore + (spicyRating ?? 0) + (sweetRating ?? 0) + (sourRating ?? 0);
    if (total <= 10) return "1형";
    if (total <= 20) return "2형";
    return "3형";
  }

  Widget buildRatingButtons(String label, int? currentRating, Function(int) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(5, (index) {
            bool isSelected = currentRating == index + 1;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? const Color(0xFF03037C) : Colors.white,
                foregroundColor: isSelected ? Colors.white : Colors.black,
                side: BorderSide(
                  color: isSelected ? const Color(0xFF03037C) : Colors.grey[300]!,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                setState(() {
                  onSelect(isSelected ? 0 : index + 1);
                });
              },
              child: Text('${index + 1}'),
            );
          }),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '매칭',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
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
                color: Colors.black,
              ),
            ),
            SizedBox(height: 24),
            buildRatingButtons(
                '매운맛', spicyRating, (rating) => setState(() => spicyRating = rating)),
            buildRatingButtons(
                '단맛', sweetRating, (rating) => setState(() => sweetRating = rating)),
            buildRatingButtons(
                '신맛', sourRating, (rating) => setState(() => sourRating = rating)),
            SizedBox(height: 24),
            Text(
              '키워드로 골라봐요!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keywords.map((keyword) {
                final isSelected = selectedKeywords.contains(keyword);
                return FilterChip(
                  selected: isSelected,
                  showCheckmark: false,
                  label: Text(
                    keyword,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: isSelected ? const Color(0xFF03037C) : Colors.white,
                  selectedColor: Color(0xFF03037C),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF03037C) : Colors.grey[300]!,
                  ),
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        selectedKeywords.add(keyword);
                      } else {
                        selectedKeywords.remove(keyword);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            SizedBox(height: 150),
            Container(
              width: double.infinity,
              height: 67.91,
              margin: EdgeInsets.only(bottom: 8),
              child: ElevatedButton(
                onPressed: () {
                  String resultType = calculateResultType();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MatchRecommendationScreen(resultType: resultType),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF03037C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '다음으로',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    Text(
                      '오늘의 입맛 유형 결과 확인하기',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
