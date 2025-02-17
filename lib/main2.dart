import 'package:flutter/material.dart';
import 'my.dart';
import 'match.dart';
import 'wish.dart';
import 'home.dart';

class MainAppScreen extends StatefulWidget {
  @override
  _MainAppScreenState createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _selectedIndex = 0;

  // 각 화면을 리스트로 정의
  final List<Widget> _screens = <Widget>[
    HomeContent(),    // 홈 화면 콘텐츠
    MatchingScreen(), // 매칭 화면
    WishlistScreen(), // 찜 화면
    MyScreen(),       // 마이 화면
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],  // 현재 선택된 화면을 표시
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: '매칭',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: '찜',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '마이',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Color(0xFF312E81),           // 선택된 아이템의 색상
        unselectedItemColor: Colors.grey,         // 선택되지 않은 아이템의 기본 색상
        backgroundColor: Colors.white,
        onTap: _onItemTapped,
      ),
    );
  }
}