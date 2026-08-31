import 'package:new1/widgets/category_strip.dart';
import 'package:flutter/material.dart';

import 'package:new1/affiliate_benefits_screen.dart';
import 'package:new1/services/affiliate_service.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/app_config_service.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/master_content.dart';
import 'package:new1/widgets/stamp_asset_grid.dart';

/// 지갑 스탬프 탭: 매장별 스탬프 현황 카드 목록.
/// /api/coupons/stamps/my/all/ 결과를 제휴 식당 목록과 restaurant_id로 매칭한다.
class StampTab extends StatefulWidget {
  const StampTab({super.key, this.onGoToAffiliate});

  /// 빈 상태에서 "제휴 식당 보러 가기" 탭 이동 콜백
  final VoidCallback? onGoToAffiliate;

  @override
  State<StampTab> createState() => _StampTabState();
}

class _StampEntry {
  const _StampEntry({
    required this.restaurantId,
    required this.status,
    this.restaurant,
  });

  final int restaurantId;
  final StampStatus status;
  final AffiliateRestaurantSummary? restaurant;
}

class _StampTabState extends State<StampTab> {
  String _selectedCategory = 'ALL';
  bool _isLoading = true;
  bool _requiresLogin = false;
  bool _hasError = false;
  List<_StampEntry> _entries = const [];
  int? _defaultTarget;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _requiresLogin = false;
      _hasError = false;
    });

    try {
      final results = await Future.wait([
        CouponService.fetchAllStampStatuses(),
        AffiliateService.fetchRestaurants(),
      ]).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      final collection = results[0] as StampStatusCollection;
      final restaurants = results[1] as List<AffiliateRestaurantSummary>;
      final byId = {for (final r in restaurants) r.id: r};

      final entries = collection.statuses.entries
          // 스탬프를 1개라도 적립한 매장만 보여준다.
          // (서버는 0개 매장도 함께 내려주므로 여기서 걸러야 목록이 비지 않는다)
          .where((e) => e.value.current > 0)
          .map((e) => _StampEntry(
                restaurantId: e.key,
                status: e.value,
                restaurant: byId[e.key],
              ))
          .toList()
        // 진행도가 높은 매장을 위로
        ..sort((a, b) => b.status.current.compareTo(a.status.current));

      setState(() {
        _entries = entries;
        _defaultTarget = collection.defaultTarget;
        _isLoading = false;
      });
    } on ApiAuthException {
      if (!mounted) return;
      setState(() {
        _requiresLogin = true;
        _isLoading = false;
        _entries = const [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
        _entries = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      color: const Color(0xFF6366F1),
      backgroundColor: Colors.white,
      strokeWidth: 2,
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_requiresLogin) {
      return _buildMessage(
        icon: Icons.lock_outline,
        message: '로그인하면 적립한 스탬프를 확인할 수 있어요.',
        buttonLabel: '카카오로 로그인',
        onPressed: () async {
          final result = await Navigator.of(context).pushNamed(
            '/login',
            arguments: const {'redirect': 'wallet_stamp'},
          );
          if (result != null) await _load();
        },
      );
    }

    if (_hasError) {
      return _buildMessage(
        icon: Icons.refresh,
        message: '스탬프 현황을 불러오지 못했어요.\n다시 시도해 주세요.',
        buttonLabel: '새로고침',
        onPressed: _load,
      );
    }

    if (_entries.isEmpty) {
      return _buildMessage(
        icon: Icons.local_cafe_outlined,
        message: '아직 적립한 스탬프가 없어요.\n제휴 식당에서 방문 스탬프를 모아보세요.',
        buttonLabel: widget.onGoToAffiliate != null ? '제휴 식당 보러 가기' : null,
        onPressed: widget.onGoToAffiliate,
      );
    }

    // 쿠폰 탭과 같은 카테고리 줄. 선택하면 해당 분류 매장만 남긴다.
    final visible = _selectedCategory == 'ALL'
        ? _entries
        : _entries
            .where((e) =>
                normalizeCategoryKey(e.restaurant?.category ?? '') ==
                _selectedCategory)
            .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 140),
      children: [
        CategoryStrip(
          selected: _selectedCategory,
          onSelect: (key) => setState(() => _selectedCategory = key),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Center(
              child: Text(
                '${MasterContent.labelOf(_selectedCategory)} 스탬프가 아직 없어요',
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8B95A1),
                ),
              ),
            ),
          )
        else
          for (final entry in visible) _buildStampCard(entry),
      ],
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String message,
    String? buttonLabel,
    VoidCallback? onPressed,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: const Color(0xFF312E81)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF39393E),
                    ),
                  ),
                ),
                if (buttonLabel != null) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onPressed,
                    child: Text(buttonLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 매장별 스탬프 티켓. 식당 상세와 같은 도장 에셋·절취선 구성을 쓴다.
  Widget _buildStampCard(_StampEntry entry) {
    final status = entry.status;
    // 칸 수·리워드 위치·남은 개수는 모두 서버 응답(target + rewards)에서 파생시킨다.
    final board = status.boardLength > 0
        ? status.boardLength
        : (_defaultTarget ?? AppConfigService.stampDefaultCycleTarget);
    final current = status.current.clamp(0, board);
    final name = entry.restaurant?.name ?? '매장 ${entry.restaurantId}';
    final category = entry.restaurant?.category ?? '';
    final nextReward = status.nextReward;
    final remaining = status.remainingToNextReward;
    final rewardTiers = status.thresholdRewards;
    final rewardSteps = <int>{
      for (final r in rewardTiers) r.stamps!,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D191F28),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x14191F28),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/images/stamp/stamp_tag.png',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: Color(0xFF191F28),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (category.isNotEmpty) category,
                          nextReward == null || remaining <= 0
                              ? '리워드를 받을 수 있어요'
                              : '$remaining개 더 모으면 '
                                  '${stampRewardBenefitText(nextReward)}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF8B95A1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$current',
                        style: const TextStyle(
                          fontSize: 20,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      TextSpan(
                        text: ' / $board',
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF191F28),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _DashedDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStampGrid(
                  current: current,
                  target: board,
                  rewardSteps: rewardSteps,
                ),
                if (rewardTiers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildRewardTierList(rewardTiers, current),
                ],
                const SizedBox(height: 14),
                _buildAddStampButton(entry),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 카드에서 바로 스탬프를 적립한다.
  /// PIN 입력·적립 처리는 식당 상세 시트의 기존 플로우를 그대로 재사용한다.
  Widget _buildAddStampButton(_StampEntry entry) {
    final restaurant = entry.restaurant;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        // 제휴 식당 목록에 없는 매장은 상세 시트를 열 수 없으므로 비활성화한다.
        onPressed: restaurant == null ? null : () => _openStampAdd(entry),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE5E7EB),
          disabledForegroundColor: const Color(0xFF9CA3AF),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        icon: const Icon(Icons.add_circle_outline, size: 18),
        label: const Text('적립하기'),
      ),
    );
  }

  /// 식당 상세 시트를 띄워 스탬프 적립(PIN 확인)을 진행하고, 닫히면 목록을 갱신한다.
  Future<void> _openStampAdd(_StampEntry entry) async {
    final restaurant = entry.restaurant;
    if (restaurant == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return AffiliateRestaurantDetailSheet(
          restaurant: restaurant,
          coupons: const [],
          requiresLogin: false,
          source: 'wallet_stamp',
          isFavorite: false,
          onFavoriteChanged: (_) {},
          initialStampStatus: entry.status,
          onStampStatusUpdated: (_) {},
          onCouponRedeemed: (_) {},
          onRewardCouponsIssued: (_) {},
        );
      },
    );
    if (!mounted) return;
    // 적립 결과(도장 수·리워드 쿠폰)를 목록에 반영한다.
    await _load();
  }

  /// "N개 → 혜택" 목록. 서버 rewards 그대로 보여준다(하드코딩 없음).
  Widget _buildRewardTierList(List<StampReward> tiers, int current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in tiers)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: (r.stamps ?? 0) <= current
                        ? const Color(0xFFEEF2FF)
                        : const Color(0xFFF2F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${r.stamps}개',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w800,
                      color: (r.stamps ?? 0) <= current
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFF8B95A1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stampRewardBenefitText(r),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w600,
                      color: (r.stamps ?? 0) <= current
                          ? const Color(0xFF191F28)
                          : const Color(0xFF6B7684),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 5칸씩 줄바꿈되는 원형 도장. 리워드가 걸린 칸은 선물 도장으로 표시한다.
  Widget _buildStampGrid({
    required int current,
    required int target,
    required Set<int> rewardSteps,
  }) {
    return StampAssetGrid(
      current: current,
      target: target,
      rewardSteps: rewardSteps,
    );
  }

}

/// 티켓 절취선.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      child: CustomPaint(painter: _DashedLinePainter(), size: Size.infinite),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE3E6EF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.75), Offset(x + dash, 0.75), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
