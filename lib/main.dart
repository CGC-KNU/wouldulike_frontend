import 'package:flutter/material.dart';
import 'start_survey.dart'; // start_survey 파일을 임포트

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: StartSurveyScreen(), // 초기 화면을 StartSurveyScreen으로 변경
    );
  }
}
