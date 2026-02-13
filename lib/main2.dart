import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:new1/affiliate_benefits_screen.dart';
import 'home.dart';
import 'my.dart';
import 'package:new1/utils/location_helper.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/utils/analytics_logger.dart';
import 'package:new1/widgets/liquid_glass_bottom_bar.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  static const List<String> _tabNames = <String>['home', 'affiliate', 'my'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocationHelper.refreshCurrentLocation();
      // 앱 시작 시 토큰 상태 확인
      _checkTokenIfNeeded();
      _logTabView(_selectedIndex);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 타이머 취소
    ApiClient.cancelTokenRefreshTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 토큰 상태 확인 및 타이머 재설정
      _checkTokenIfNeeded();
    } else if (state == AppLifecycleState.paused) {
      // 백그라운드로 갈 때 타이머 취소 (배터리 절약)
      ApiClient.cancelTokenRefreshTimer();
    }
  }

  /// 토큰이 필요하면 확인하고 갱신
  Future<void> _checkTokenIfNeeded() async {
    try {
      await ApiClient.ensureTokenValid();
      // 토큰 갱신 타이머 재설정
      await ApiClient.scheduleTokenRefresh();
    } catch (e) {
      // 토큰 갱신 실패는 조용히 처리 (API 요청 시 다시 시도됨)
      debugPrint('[MainAppScreen] Token validation error: $e');
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _logTabView(index);
  }

  void _logTabView(int index) {
    final tabName =
        index >= 0 && index < _tabNames.length ? _tabNames[index] : 'unknown';
    AnalyticsLogger.logEvent(
      'tab_view',
      parameters: {
        'tab_index': index,
        'tab_name': tabName,
      },
    );
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
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 선택된 탭: 기존 남색 유지, 미선택 탭: 좀 더 투명하게 표시
    const Color selectedColor = Color(0xFF312E81);
    const Color unselectedColor = Color(0x999CA3AF); // 기존 색상에서 알파(투명도)만 낮춤
    const TextStyle selectedLabelStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontWeight: FontWeight.w600,
      fontSize: 11.5,
      height: 1.5,
      letterSpacing: -0.2,
    );
    const TextStyle unselectedLabelStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontWeight: FontWeight.w500,
      fontSize: 11.0,
      height: 1.5,
      letterSpacing: -0.2,
    );

    return Scaffold(
      extendBody: true,
      body: _buildCurrentScreen(),
      bottomNavigationBar: LiquidGlassBottomBar(
        tabs: const [
          LiquidGlassTab(
            label: '홈',
            assetPath: 'assets/images/home.svg',
          ),
          LiquidGlassTab(
            label: '대학가 근처 식당',
            assetPath: 'assets/images/fork.svg',
          ),
          LiquidGlassTab(
            label: '마이페이지',
            assetPath: 'assets/images/my.svg',
          ),
        ],
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
        iconBuilder: _navIcon,
        selectedColor: selectedColor,
        unselectedColor: unselectedColor,
        selectedLabelStyle: selectedLabelStyle,
        unselectedLabelStyle: unselectedLabelStyle,
      ),
    );
  }
}