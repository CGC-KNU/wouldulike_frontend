import 'package:flutter/material.dart';

class WishlistScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
      body: Center(
        child: Text(
          '찜 화면입니다.',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
