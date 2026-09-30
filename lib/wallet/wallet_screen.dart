import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:new1/coupon_list_screen.dart';
import 'package:new1/mileage/mileage_shop_screen.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/services/master_content.dart';
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
  static const _scheduleCollapsedKey = 'wallet_raffle_schedule_collapsed';

  MileageSummary? _summary;
  WalletOverview? _overview;
  bool _scheduleCollapsed = true;
  int _historyVersion = 0;

  @override
  void initState() {
    super.initState();
    // 시연 빌드에서 특정 탭부터 열 수 있게: --dart-define=DEMO_TAB=1 (0 쿠폰/1 스탬프/2 마일리지)
    final pending = DeepLinkService.instance.pendingWalletTab.value;
    const demoTab = int.fromEnvironment('DEMO_TAB');
    final initial = (pending != null && pending >= 0 && pending <= 2)
        ? pending
        : demoTab;
    if (pending != null) {
      DeepLinkService.instance.pendingWalletTab.value = null;
    }
    _tabController = TabController(
      length: 3,
      initialIndex: initial,
      vsync: this,
    );
    DeepLinkService.instance.pendingWalletTab.addListener(_onPendingWalletTab);
    _loadSummary();
    _loadRaffleSchedule();
  }

  Future<void> _loadRaffleSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _scheduleCollapsed =
          prefs.getBool(_scheduleCollapsedKey) ?? true);
    }
    await MasterContent.loadRaffleSchedule();
    if (mounted) setState(() {});
  }

  Future<void> _toggleSchedule() async {
    setState(() => _scheduleCollapsed = !_scheduleCollapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_scheduleCollapsedKey, _scheduleCollapsed);
  }

  void _onPendingWalletTab() {
    final idx = DeepLinkService.instance.pendingWalletTab.value;
    if (idx == null || !mounted) return;
    DeepLinkService.instance.pendingWalletTab.value = null;
    if (idx >= 0 && idx < 3 && _tabController.index != idx) {
      _tabController.animateTo(idx);
    }
  }

  Future<void> _loadSummary() async {
    try {
      // 배지 수치는 overview 한 번으로 받고, 미배포 구간에서는 summary로 폴백한다.
      final overview = await MileageService.fetchWalletOverview();
      final summary = overview?.mileage ?? await MileageService.fetchSummary();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _summary = summary;
      });
    } catch (e) {
      debugPrint('Failed to load wallet summary: $e');
    }
  }

  /// 내역 섹션은 키를 바꿔 다시 만들면 처음부터 다시 불러온다.
  void _reloadHistory() {
    if (mounted) setState(() => _historyVersion++);
  }

  Future<void> _refreshMileageTab() async {
    _reloadHistory();
    await Future.wait([_loadSummary(), _loadRaffleSchedule()]);
  }

  @override
  void dispose() {
    DeepLinkService.instance.pendingWalletTab.removeListener(_onPendingWalletTab);
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
                // 마일리지 탭 = 응모 일정 → 상점(잔액·식사권 응모) → 내 응모 현황 → 최근 내역.
                MileageShopScreen(
                  embedded: true,
                  initialSummary: _summary,
                  header: MasterContent.raffleSchedule.enabled
                      ? _buildRaffleSchedule(MasterContent.raffleSchedule)
                      : null,
                  footer: MileageHistorySection(
                    key: ValueKey(_historyVersion),
                  ),
                  onRefresh: _refreshMileageTab,
                  onEntered: () {
                    _reloadHistory();
                    _loadSummary();
                  },
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

  /// 응모 시작·마감·발표 안내. 문구는 운영진이 raffle_schedule 콘텐츠로 바꾼다.
  Widget _buildRaffleSchedule(RaffleSchedule schedule) {
    const ink = Color(0xFF191F28);
    const muted = Color(0xFF4E5968);
    const faint = Color(0xFF8B95A1);
    const primary = Color(0xFF312E81);
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in schedule.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.text,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (schedule.note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              schedule.note,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: faint,
              ),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggleSchedule,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 14, 12, _scheduleCollapsed ? 14 : 10),
              child: Row(
                children: [
                  const Icon(Icons.event_note_rounded,
                      size: 18, color: primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      schedule.title,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                  ),
                  Text(
                    _scheduleCollapsed ? '펼치기' : '접기',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: faint,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _scheduleCollapsed ? 0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: faint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _scheduleCollapsed
                ? const SizedBox(width: double.infinity)
                : body,
          ),
        ],
      ),
    );
  }
}
