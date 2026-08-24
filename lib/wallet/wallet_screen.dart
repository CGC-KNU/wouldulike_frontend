import 'package:flutter/material.dart';

import 'package:new1/coupon_list_screen.dart';
import 'package:new1/mileage/mileage_shop_screen.dart';
import 'package:new1/services/mileage_service.dart';
import 'package:new1/wallet/mileage_tab.dart';
import 'package:new1/wallet/stamp_tab.dart';

/// 내 지갑: 마일리지 히어로 + 쿠폰/스탬프/마일리지 3탭 컨테이너 (스펙 7.1)
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, this.onRequestTab});

  /// 하단 탭 전환 요청 (0: 홈, 1: 대학가 근처 식당)
  final ValueChanged<int>? onRequestTab;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  MileageSummary? _summary;
  WalletOverview? _overview;

  @override
  void initState() {
    super.initState();
    // 시연 빌드에서 특정 탭부터 열 수 있게: --dart-define=DEMO_TAB=1 (0 쿠폰/1 스탬프/2 마일리지)
    _tabController = TabController(
      length: 3,
      initialIndex: const int.fromEnvironment('DEMO_TAB'),
      vsync: this,
    );
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    // 배지 수치는 overview 한 번으로 받고, 미배포 구간에서는 summary로 폴백한다.
    final overview = await MileageService.fetchWalletOverview();
    final summary = overview?.mileage ?? await MileageService.fetchSummary();
    if (!mounted) return;
    setState(() {
      _overview = overview;
      _summary = summary;
    });
  }

  Future<void> _openShop() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MileageShopScreen(initialSummary: _summary),
      ),
    );
    // 응모로 잔액이 줄었을 수 있으므로 복귀 시 갱신
    await _loadSummary();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _goToAffiliateTab() {
    widget.onRequestTab?.call(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 0,
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF172133),
            unselectedLabelColor: const Color(0xFF9CA3AF),
            indicatorColor: const Color(0xFF312E81),
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            tabs: [
              _buildTab('쿠폰', _overview?.usableCoupons),
              _buildTab('스탬프', _overview?.activeStampStores),
              const Tab(text: '마일리지'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                CouponListScreen(
                  source: 'wallet',
                  embedded: true,
                  onGoToAffiliate: _goToAffiliateTab,
                ),
                StampTab(onGoToAffiliate: _goToAffiliateTab),
                // 마일리지 히어로는 마일리지 탭에서만 보여준다.
                // (쿠폰·스탬프 탭에서는 화면 위쪽을 잔액이 차지할 이유가 없다)
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: _buildMileageHero(),
                    ),
                    const Expanded(child: MileageTab()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 탭 라벨 + 배지 숫자. 서버 수치가 없거나 0이면 배지를 붙이지 않는다.
  Widget _buildTab(String label, int? count) {
    if (count == null || count <= 0) return Tab(text: label);
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFF312E81),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 마일리지 히어로 카드. 잔액 + 마일리지 상점 진입 (스펙 7.1·7.2).
  Widget _buildMileageHero() {
    final summary = _summary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B47C4), Color(0xFF6A5AE6), Color(0xFF7C64EE)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '보유 마일리지',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                    color: Color(0xD1FFFFFF),
                  ),
                ),
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _comma(summary?.balance ?? 0),
                        style: const TextStyle(
                          fontSize: 26,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.78,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                      const TextSpan(
                        text: ' M',
                        style: TextStyle(
                          fontSize: 15,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '이번 달 +${_comma(summary?.monthEarned ?? 0)} M 적립 · 전 매장 사용',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w500,
                    color: Color(0xCCFFFFFF),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _openShop,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF312E81),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('마일리지 상점'),
          ),
        ],
      ),
    );
  }
}

String _comma(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
