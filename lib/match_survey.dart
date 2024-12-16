import 'package:flutter/material.dart';
import 'match_questionlist.dart';
import 'match_survey2.dart';

class SurveyScreen extends StatefulWidget {
  @override
  _SurveyScreenState createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  int currentPage = 1;
  final int totalPages = 8;
  int? selectedAnswer;
  List<int> userAnswers = [];

  void _answerQuestion(int score, int index) {
    setState(() {
      selectedAnswer = index;
      if (userAnswers.length >= currentPage) {
        userAnswers[currentPage - 1] = score; // 기존 답변 업데이트
      } else {
        userAnswers.add(score); // 새로운 답변 추가
      }
    });
  }

  void _nextQuestion() {
    if (selectedAnswer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("답변을 선택해주세요.")),
      );
      return;
    }

    if (currentPage < totalPages) {
      setState(() {
        currentPage++;
        selectedAnswer = null;
      });
    } else {
      int totalScore = userAnswers.fold(0, (sum, score) => sum + score);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MatchSurvey2(totalScore: totalScore),
        ),
      );
    }
  }

  void _previousQuestion() {
    if (currentPage > 1) {
      setState(() {
        currentPage--;
        selectedAnswer = userAnswers[currentPage - 1];
        userAnswers.removeLast();
      });
    }
  }

  double get _progress => currentPage / totalPages;

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

    Question currentQuestion = QuestionData.questions[currentPage - 1];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 뒤로가기 버튼
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: screenHeight * 0.02,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: _previousQuestion,
                  ),
                ],
              ),
            ),
            // 진행률 텍스트
            Padding(
              padding: EdgeInsets.only(bottom: screenHeight * 0.02),
              child: Text(
                '$currentPage / $totalPages',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: screenWidth * 0.04,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
            // 진행 바
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF312E81)),
              ),
            ),
            SizedBox(height: screenHeight * 0.03), // 추가 간격
            // 이미지
            Image.asset(
              'assets/images/thinking_emoji.png',
              width: screenWidth * 0.2,
              height: screenHeight * 0.12,
              fit: BoxFit.contain,
            ),
            SizedBox(height: screenHeight * 0.03),
            // 질문 텍스트
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
              child: Text(
                currentQuestion.questionText,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: screenWidth * 0.05,
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: screenHeight * 0.04), // 추가 간격
            // 답변 리스트
            Expanded(
              child: ListView.builder(
                itemCount: currentQuestion.answers.length,
                itemBuilder: (context, index) {
                  final answer = currentQuestion.answers[index];
                  final isSelected = selectedAnswer == index;

                  return GestureDetector(
                    onTap: () => _answerQuestion(answer.score, index),
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.05,
                        vertical: screenHeight * 0.01,
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: screenHeight * 0.02,
                        horizontal: screenWidth * 0.08,
                      ),
                      constraints: BoxConstraints(
                        minHeight: screenHeight * 0.1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F8FFFF),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey.shade300,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: Text(
                        answer.text,
                        style: TextStyle(
                          color: const Color(0xFF312E81),
                          fontSize: screenWidth * 0.04,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // 다음 버튼
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: screenHeight * 0.03,
              ),
              child: SizedBox(
                width: double.infinity,
                height: screenHeight * 0.08,
                child: ElevatedButton(
                  onPressed: _nextQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedAnswer == null
                        ? Colors.grey.shade300
                        : const Color(0xFF312E81),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    '다음으로',
                    style: TextStyle(
                      color: selectedAnswer == null ? Colors.grey : Colors.white,
                      fontSize: screenWidth * 0.05,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
