import 'package:flutter/material.dart';

import 'package:new1/coupon_list_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _buildMileageHero(),
          ),
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
            tabs: const [
              Tab(text: '쿠폰'),
              Tab(text: '스탬프'),
              Tab(text: '마일리지'),
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
                const MileageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 마일리지 히어로 카드 (M1: 오픈 준비 중 표시, M3에서 잔액 연동)
  Widget _buildMileageHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF192132),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '내 마일리지',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCBD5FF),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '오픈 준비 중이에요',
                  style: TextStyle(
                    fontSize: 18,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '방문 적립 마일리지가 곧 찾아와요',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w500,
                    color: Color(0x99FFFFFF),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.savings_outlined,
            size: 32,
            color: Color(0xFFCBD5FF),
          ),
        ],
      ),
    );
  }
}
