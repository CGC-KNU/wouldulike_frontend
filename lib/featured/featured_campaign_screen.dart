import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:new1/affiliate_benefits_screen.dart';
import 'package:new1/services/affiliate_service.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/promotion_service.dart';

/// 기획전 특집 화면 (스펙 7.4, 프로토타입 화면 13)
class FeaturedCampaignScreen extends StatefulWidget {
  const FeaturedCampaignScreen({super.key, required this.campaign});

  final FeaturedCampaign campaign;

  @override
  State<FeaturedCampaignScreen> createState() => _FeaturedCampaignScreenState();
}

class _FeaturedStore {
  const _FeaturedStore({required this.item, required this.restaurant});

  final FeaturedCampaignItem item;
  final AffiliateRestaurantSummary restaurant;
}

class _FeaturedCampaignScreenState extends State<FeaturedCampaignScreen> {
  // home.dart와 동일한 즐겨찾기 저장 키
  static const String _kFavoriteRestaurantIdsKey =
      'affiliate_favorite_restaurant_ids';

  List<_FeaturedStore> _stores = const [];
  bool _isLoading = true;
  String? _error;
  List<UserCoupon> _coupons = const [];
  Map<int, StampStatus> _stampStatuses = const {};
  bool _requiresLogin = false;
  Set<int> _favoriteIds = <int>{};
  bool _isOpeningDetail = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _favoriteIds =
          (prefs.getStringList(_kFavoriteRestaurantIdsKey) ?? const <String>[])
              .map(int.tryParse)
              .whereType<int>()
              .toSet();

      final tab = await AffiliateService.fetchTabRestaurants();
      final byId = <int, AffiliateRestaurantSummary>{
        for (final r in tab.affiliateRestaurants) r.id: r,
      };
      final stores = <_FeaturedStore>[];
      for (final item in widget.campaign.items) {
        final restaurant = byId[item.restaurantId];
        if (restaurant == null) {
          // 스펙 7.4: 매칭 실패 항목은 제외하고 로그만 남긴다.
          debugPrint(
              'featured item excluded: restaurant ${item.restaurantId} not in tab-restaurants');
          continue;
        }
        stores.add(_FeaturedStore(item: item, restaurant: restaurant));
      }
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _isLoading = false;
      });
      await _loadUserData();
    } catch (e) {
      debugPrint('Failed to load featured stores: $e');
      if (!mounted) return;
      setState(() {
        _error = '기획전 매장 정보를 불러오지 못했어요.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final results = await Future.wait<dynamic>([
        CouponService.fetchMyCoupons(status: CouponStatus.issued),
        CouponService.fetchAllStampStatuses(),
      ]);
      if (!mounted) return;
      setState(() {
        _coupons = results[0] as List<UserCoupon>;
        _stampStatuses = (results[1] as StampStatusCollection).statuses;
        _requiresLogin = false;
      });
    } on ApiAuthException {
      if (!mounted) return;
      setState(() => _requiresLogin = true);
    } catch (e) {
      // 스탬프·쿠폰은 부가 정보라 실패해도 화면은 유지한다.
      debugPrint('Failed to load featured user data: $e');
    }
  }

  StampStatus _resolvedStampStatus(AffiliateRestaurantSummary restaurant) {
    return _stampStatuses[restaurant.id] ??
        StampStatus(
          current: restaurant.stampCurrent,
          target: restaurant.stampTarget,
        );
  }

  Future<void> _setFavorite(int restaurantId, bool isFavorite) async {
    final next = Set<int>.from(_favoriteIds);
    if (isFavorite) {
      next.add(restaurantId);
    } else {
      next.remove(restaurantId);
    }
    _favoriteIds = next;
    await _prefs?.setStringList(
      _kFavoriteRestaurantIdsKey,
      next.map((id) => id.toString()).toList(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openStoreDetail(AffiliateRestaurantSummary restaurant) async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return AffiliateRestaurantDetailSheet(
            restaurant: restaurant,
            coupons: _coupons
                .where((coupon) => coupon.restaurantId == restaurant.id)
                .toList(),
            requiresLogin: _requiresLogin,
            // 기획전 진입 라우트 인자. 시트가 닫히면 기획전 화면으로 복귀한다.
            source: 'featured_campaign',
            isFavorite: _favoriteIds.contains(restaurant.id),
            onFavoriteChanged: (isFavorite) =>
                _setFavorite(restaurant.id, isFavorite),
            initialStampStatus: _stampStatuses[restaurant.id],
            onStampStatusUpdated: (status) {
              if (!mounted) return;
              setState(() {
                _stampStatuses = Map<int, StampStatus>.from(_stampStatuses)
                  ..[restaurant.id] = status;
              });
            },
            onCouponRedeemed: (code) {
              if (!mounted) return;
              setState(() {
                _coupons =
                    _coupons.where((coupon) => coupon.code != code).toList();
              });
            },
            onRewardCouponsIssued: (codes) {
              if (codes.isEmpty || !mounted) return;
              final existing = _coupons.map((coupon) => coupon.code).toSet();
              final added = codes
                  .where((code) => !existing.contains(code))
                  .map(
                    (code) => UserCoupon(
                      code: code,
                      status: CouponStatus.issued,
                      restaurantId: restaurant.id,
                      issueKey: 'STAMP_REWARD:reward',
                    ),
                  )
                  .toList();
              if (added.isEmpty) return;
              setState(() {
                _coupons = List<UserCoupon>.from(_coupons)..addAll(added);
              });
            },
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isOpeningDetail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: Text(
          campaign.title,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Color(0xFF111827),
          ),
        ),
      ),
      body: _buildBody(campaign),
    );
  }

  Widget _buildBody(FeaturedCampaign campaign) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF6366F1),
      backgroundColor: Colors.white,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          _buildHero(campaign),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '우주라이크가 고른 ${_stores.length}곳',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                const Text(
                  '이번 달에만 제공돼요',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_stores.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '기획전 매장 정보를 불러오지 못했어요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            )
          else
            ...List.generate(_stores.length, (index) {
              final store = _stores[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _FeaturedStoreCard(
                  index: index,
                  item: store.item,
                  restaurant: store.restaurant,
                  campaignTag: widget.campaign.title,
                  stampStatus: _resolvedStampStatus(store.restaurant),
                  requiresLogin: _requiresLogin,
                  onTap: () => _openStoreDetail(store.restaurant),
                ),
              );
            }),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              _footerNote(campaign),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                height: 1.6,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _footerNote(FeaturedCampaign campaign) {
    final endsAt = campaign.endsAt?.toLocal();
    final until = endsAt != null
        ? '· 기획전 혜택은 ${endsAt.year}년 ${endsAt.month}월 ${endsAt.day}일까지 제공돼요.\n'
        : '';
    return '$until· 매장 사정에 따라 혜택이 조기 종료될 수 있어요.';
  }

  Widget _buildHero(FeaturedCampaign campaign) {
    final labelParts = <String>[
      if (campaign.periodLabel.isNotEmpty) campaign.periodLabel,
      if (campaign.region.isNotEmpty) campaign.region,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2670), Color(0xFF4B47C4), Color(0xFF7C64EE)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (labelParts.isNotEmpty)
            Text(
              labelParts.join(' · '),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC7D2FE),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            campaign.title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          if (campaign.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              campaign.subtitle,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.55,
                color: Color(0xE6FFFFFF),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            children: [
              _HeroChip(text: '선별 매장 ${widget.campaign.items.length}곳'),
              const _HeroChip(text: '기획전 한정 혜택'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _FeaturedStoreCard extends StatelessWidget {
  const _FeaturedStoreCard({
    required this.index,
    required this.item,
    required this.restaurant,
    required this.campaignTag,
    required this.stampStatus,
    required this.requiresLogin,
    required this.onTap,
  });

  final int index;
  final FeaturedCampaignItem item;
  final AffiliateRestaurantSummary restaurant;
  final String campaignTag;
  final StampStatus stampStatus;
  final bool requiresLogin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (restaurant.category.trim().isNotEmpty) restaurant.category.trim(),
      if (restaurant.zone.trim().isNotEmpty) restaurant.zone.trim(),
      if (campaignTag.trim().isNotEmpty) campaignTag.trim(),
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhoto(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: chips
                            .map(
                              (chip) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  chip,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF4FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.benefitTitle,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: Color(0xFF312E81),
                            ),
                          ),
                          if (item.benefitSub.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.benefitSub,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!requiresLogin && stampStatus.target > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '스탬프 ${stampStatus.current}/${stampStatus.target}',
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: (stampStatus.current /
                                        stampStatus.target)
                                    .clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: const Color(0xFFF3F4F8),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF6366F1)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: TextButton(
                        onPressed: onTap,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFF1C203C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '혜택 보러가기',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    final imageUrl =
        restaurant.imageUrls.isNotEmpty ? restaurant.imageUrls.first : null;
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: imageUrl != null
              ? Image.network(
                  imageUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _photoFallback(),
                )
              : _photoFallback(),
        ),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xCC111827),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        if (item.badge.isNotEmpty)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item.badge,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF312E81),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _photoFallback() {
    return Image.asset(
      'assets/images/food_image0.png',
      width: double.infinity,
      fit: BoxFit.cover,
    );
  }
}
