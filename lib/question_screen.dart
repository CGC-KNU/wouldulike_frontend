import 'package:flutter/material.dart';
import 'package:new1/services/master_content.dart';
import 'result_screen.dart';
import 'start_survey.dart';

class QuizScreen extends StatefulWidget {
  final int questionIndex;
  final Function answerPressed;

  const QuizScreen({
    super.key,
    required this.answerPressed,
    required this.questionIndex,
  });

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _totalScore = 0;
  int _currentQuestionIndex = 0;
  int _selectedIndex = -1;
  late List<String> _selectedAnswers;
  late List<int> _scores;

  List<Map<String, dynamic>> get _questions => MasterContent.quizQuestions;

  @override
  void initState() {
    super.initState();
    final count = _questions.length;
    _selectedAnswers = List.filled(count, '', growable: false);
    _scores = List.filled(count, -1, growable: false);
  }

  void _answerQuestion(int score, String answer, int index) {
    setState(() {
      _selectedIndex = index;  // 현재 선택만 저장
      _scores[_currentQuestionIndex] = score;
      _selectedAnswers[_currentQuestionIndex] = answer;
    });

    // 모든 질문에 답변했는지 확인
    bool allAnswered = true;
    for (int i = 0; i < _scores.length; i++) {
      if (_scores[i] == -1) {
        allAnswered = false;
        break;
      }
    }
    if (allAnswered) {
      _calculateFinalScore();
    }
  }

  void _calculateFinalScore() {
    _totalScore = 0;

    if (_scores.length < 12) {
      _totalScore = _scores.fold(0, (sum, value) => sum + (value < 0 ? 0 : value));
      return;
    }

    int sum1 = _scores[0] + _scores[1] + _scores[2];
    int sum2 = _scores[3] + _scores[4] + _scores[5];
    int sum3 = _scores[6] + _scores[7] + _scores[8];
    int sum4 = _scores[9] + _scores[10] + _scores[11];

    _totalScore += (sum1 >= 2) ? 2000 : 1000;
    _totalScore += (sum2 >= 2) ? 200 : 100;
    _totalScore += (sum3 >= 2) ? 20 : 10;
    _totalScore += (sum4 >= 2) ? 2 : 1;
  }

  void _nextQuestion() {
    if (_selectedIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("답변을 선택해주세요.")),
      );
      return;
    }

    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() {
        _currentQuestionIndex++;
        _selectedIndex = -1;  // 선택 초기화
      });
    } else {
      // 마지막 질문일 때 결과 화면으로 이동
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            totalScore: _totalScore,
            selectedQuestions: _selectedAnswers,
            resetQuiz: _resetQuiz,
          ),
        ),
      );
    }
  }

  void _previousQuestion() {
    if (_currentQuestionIndex > 0) {
      setState(() {
        _currentQuestionIndex--;
        _selectedIndex = -1;  // 선택 초기화
      });
    }
    else{
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const StartSurveyScreen()),
      );
    }
  }

  void _resetQuiz() {
    setState(() {
      _totalScore = 0;
      _currentQuestionIndex = 0;
      _selectedIndex = -1;
      _selectedAnswers = List.filled(_questions.length, '', growable: false);
      _scores = List.filled(_questions.length, -1, growable: false);
    });
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  double get _progress {
    return _questions.isNotEmpty
        ? (_currentQuestionIndex + 1) / _questions.length
        : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _previousQuestion,
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.05,
                vertical: screenHeight * 0.03,
              ),
              child: Column(
                children: [
                  Text(
                    '${_currentQuestionIndex + 1}/${_questions.length}',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: screenWidth * 0.04,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.03),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF312E81)),
                  ),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.05),
            Image.asset(
              'assets/images/thinking_emoji.png',
              width: screenWidth * 0.15,
              height: screenHeight * 0.1,
              fit: BoxFit.contain,
            ),
            SizedBox(height: screenHeight * 0.02),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
              child: Text(
                _questions.isNotEmpty && _currentQuestionIndex < _questions.length
                    ? '${_questions[_currentQuestionIndex]["questionText"]}'
                    : '질문이 없습니다.',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: screenWidth * 0.052,
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: screenHeight * 0.05),
            Expanded(
              child: _questions.isNotEmpty && _currentQuestionIndex < _questions.length
                  ? ListView.builder(
                itemCount: _questions[_currentQuestionIndex]["answers"].length,
                itemBuilder: (context, index) {
                  final answer = _questions[_currentQuestionIndex]["answers"][index];
                  final isSelected = _selectedIndex == index;

                  return GestureDetector(
                    onTap: () {
                      _answerQuestion(
                        answer["score"],
                        answer["text"],
                        index,
                      );
                    },
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
                        minHeight: screenHeight * 0.11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfff2f8ffff),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected ? Color(0xFF312E81) : Colors.grey.shade300,
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              answer["text"],
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                color: const Color(0xFF312E81),
                                fontSize: screenWidth * 0.04,
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
                  : const Center(
                child: Text(
                  '질문이 없습니다.',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.black,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ),
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
                    backgroundColor: _selectedIndex == -1
                        ? Colors.grey.shade300
                        : const Color(0xFF312E81),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    '다음으로',
                    style: TextStyle(
                      color: _selectedIndex == -1 ? Colors.grey : Colors.white,
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