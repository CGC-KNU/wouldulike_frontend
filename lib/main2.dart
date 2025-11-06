import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:new1/affiliate_benefits_screen.dart';
import 'home.dart';
import 'my.dart';
import 'package:new1/utils/location_helper.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationHelper.refreshCurrentLocation();
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return const HomeContent();
      case 1:
        return const AffiliateBenefitsScreen();
      case 2:
        return const MyScreen();
      default:
        return const HomeContent();
    }
  }

  Widget _navIcon(String assetPath, Color color) {
    return SvgPicture.asset(
      assetPath,
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color selectedColor = Color(0xFF312E81);
    const Color unselectedColor = Color(0xFF9CA3AF);

    return Scaffold(
      body: _buildCurrentScreen(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          elevation: 4,
          backgroundColor: Colors.white,
          type: BottomNavigationBarType.fixed,
          iconSize: 26,
          selectedIconTheme: const IconThemeData(size: 26),
          unselectedIconTheme: const IconThemeData(size: 26),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
            height: 1.5,
            letterSpacing: -0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
            height: 1.5,
            letterSpacing: -0.2,
          ),
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: _navIcon('assets/images/home.svg', unselectedColor),
              activeIcon: _navIcon('assets/images/home.svg', selectedColor),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: _navIcon('assets/images/fork.svg', unselectedColor),
              activeIcon: _navIcon('assets/images/fork.svg', selectedColor),
              label: '제휴 / 혜택',
            ),
            BottomNavigationBarItem(
              icon: _navIcon('assets/images/my.svg', unselectedColor),
              activeIcon: _navIcon('assets/images/my.svg', selectedColor),
              label: '마이페이지',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: selectedColor,
          unselectedItemColor: unselectedColor,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}