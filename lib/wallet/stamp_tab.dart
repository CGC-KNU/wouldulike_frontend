import 'package:flutter/material.dart';

import 'package:new1/services/affiliate_service.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/coupon_service.dart';

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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 140),
      children: [
        for (final entry in _entries) _buildStampCard(entry),
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

  Widget _buildStampCard(_StampEntry entry) {
    final status = entry.status;
    final target = status.target > 0 ? status.target : (_defaultTarget ?? 10);
    final current = status.current.clamp(0, target);
    final name = entry.restaurant?.name ?? '매장 ${entry.restaurantId}';
    final category = entry.restaurant?.category ?? '';
    final remaining = target - current;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category.isNotEmpty)
                      Text(
                        category,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF797979),
                        ),
                      ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF172133),
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$current',
                      style: const TextStyle(
                        fontSize: 18,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF312E81),
                      ),
                    ),
                    TextSpan(
                      text: ' / $target',
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDotGrid(current: current, target: target),
          const SizedBox(height: 8),
          Text(
            remaining <= 0 ? '리워드 조건을 달성했어요!' : '$remaining개 더 모으면 리워드를 받아요',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w600,
              color: remaining <= 0
                  ? const Color(0xFF312E81)
                  : const Color(0xFF797979),
            ),
          ),
        ],
      ),
    );
  }

  /// target칸 점 그리드. 마지막 칸은 리워드 아이콘으로 표시.
  Widget _buildDotGrid({required int current, required int target}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < target; i++)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < current
                  ? const Color(0xFF312E81)
                  : const Color(0xFFF3F4F6),
              border: Border.all(
                color: i < current
                    ? const Color(0xFF312E81)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: i == target - 1
                ? Icon(
                    Icons.card_giftcard,
                    size: 14,
                    color:
                        i < current ? Colors.white : const Color(0xFFE1B53E),
                  )
                : (i < current
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null),
          ),
      ],
    );
  }
}
