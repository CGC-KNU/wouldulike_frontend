import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/affiliate_service.dart';
import 'services/api_client.dart';
import 'services/coupon_service.dart';

class AffiliateBenefitsScreen extends StatefulWidget {
  const AffiliateBenefitsScreen({super.key});

  @override
  State<AffiliateBenefitsScreen> createState() =>
      _AffiliateBenefitsScreenState();
}

class _AffiliateBenefitsScreenState extends State<AffiliateBenefitsScreen> {
  List<AffiliateRestaurantSummary> _restaurants = [];
  List<UserCoupon> _issuedCoupons = [];
  Map<int, int> _couponCounts = {};
  bool _isLoading = false;
  String? _error;
  bool _requiresLogin = false;
  String _selectedCategory = 'ALL';
  List<String> _categories = const ['ALL'];

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
      final restaurants = await AffiliateService.fetchRestaurants();
      final issuedCoupons = await _fetchIssuedCoupons();

      final categories = <String>{'ALL'};
      for (final restaurant in restaurants) {
        if (restaurant.category.isNotEmpty) {
          categories.add(restaurant.category);
        }
      }

      if (!mounted) return;
      setState(() {
        _restaurants = restaurants;
        _issuedCoupons = issuedCoupons;
        _couponCounts = _buildCouponCounts(issuedCoupons);
        _categories = categories.toList();
        _selectedCategory = 'ALL';
      });
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() => _error = '네트워크 연결 오류: $e');
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'HTTP ${e.statusCode}: ${e.body}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<UserCoupon>> _fetchIssuedCoupons() async {
    try {
      final coupons = await CouponService.fetchMyCoupons(
        status: CouponStatus.issued,
      );
      if (mounted) {
        setState(() => _requiresLogin = false);
      }
      return coupons;
    } on ApiAuthException catch (e) {
      if (mounted) {
        setState(() {
          _requiresLogin = true;
          _error = e.message;
        });
      }
      return const [];
    } on ApiHttpException catch (e) {
      if (mounted) {
        setState(() {
          _requiresLogin = false;
          _error = 'HTTP ${e.statusCode}: ${e.body}';
        });
      }
      return const [];
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
      return const [];
    }
  }

  Map<int, int> _buildCouponCounts(List<UserCoupon> coupons) {
    final counts = <int, int>{};
    for (final coupon in coupons) {
      final restaurantId = coupon.restaurantId;
      if (restaurantId == null) continue;
      counts.update(restaurantId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<AffiliateRestaurantSummary> get _filteredRestaurants {
    if (_selectedCategory == 'ALL') return _restaurants;
    return _restaurants
        .where((restaurant) => restaurant.category == _selectedCategory)
        .toList();
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() => _selectedCategory = category);
  }

  List<UserCoupon> _couponsForRestaurant(int restaurantId) {
    return _issuedCoupons
        .where((coupon) => coupon.restaurantId == restaurantId)
        .toList();
  }

  void _handleCouponRedeemed(String couponCode, int restaurantId) {
    setState(() {
      _issuedCoupons =
          _issuedCoupons.where((coupon) => coupon.code != couponCode).toList();
      final current = _couponCounts[restaurantId] ?? 0;
      if (current <= 1) {
        _couponCounts.remove(restaurantId);
      } else {
        _couponCounts[restaurantId] = current - 1;
      }
    });
  }

  void _handleRewardCouponIssued(String couponCode, int restaurantId) {
    setState(() {
      _issuedCoupons = List<UserCoupon>.from(_issuedCoupons)
        ..add(UserCoupon(
          code: couponCode,
          status: CouponStatus.issued,
          restaurantId: restaurantId,
        ));
      _couponCounts.update(restaurantId, (value) => value + 1,
          ifAbsent: () => 1);
    });
  }

  Future<void> _openRestaurantDetail(
      AffiliateRestaurantSummary restaurant) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return AffiliateRestaurantDetailSheet(
          restaurant: restaurant,
          coupons: _couponsForRestaurant(restaurant.id),
          requiresLogin: _requiresLogin,
          onCouponRedeemed: (code) =>
              _handleCouponRedeemed(code, restaurant.id),
          onRewardCouponIssued: (code) =>
              _handleRewardCouponIssued(code, restaurant.id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('제휴 / 혜택')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('제휴 / 혜택'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _buildCategoryFilter(),
            const SizedBox(height: 12),
            if (_filteredRestaurants.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('표시할 제휴 매장이 없어요.')),
              )
            else
              ..._filteredRestaurants
                  .map((restaurant) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: _buildRestaurantCard(restaurant),
                      ))
                  .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          return ChoiceChip(
            label: Text(category == 'ALL' ? '전체' : category),
            selected: selected,
            onSelected: (_) => _selectCategory(category),
            selectedColor: const Color(0xFFEEF2FF),
            labelStyle: TextStyle(
              color:
                  selected ? const Color(0xFF312E81) : const Color(0xFF4B5563),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _categories.length,
      ),
    );
  }

  Widget _buildRestaurantCard(AffiliateRestaurantSummary restaurant) {
    final couponCount = _couponCounts[restaurant.id] ?? 0;
    final hasImage = restaurant.imageUrls.isNotEmpty;
    final couponLabel = _requiresLogin
        ? '로그인이 필요해요'
        : couponCount > 0
            ? '보유 쿠폰 $couponCount'
            : '보유 쿠폰 없음';

    return InkWell(
      onTap: () => _openRestaurantDetail(restaurant),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: Container(
                color: const Color(0xFFE5E7EB),
                width: 108,
                height: 108,
                child: hasImage
                    ? Image.network(
                        restaurant.imageUrls.first,
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 36,
                        color: Color(0xFF6B7280),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name.isNotEmpty
                                ? restaurant.name
                                : '매장 정보를 찾을 수 없어요',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_right,
                          color: Color(0xFF9CA3AF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      restaurant.address.isNotEmpty
                          ? restaurant.address
                          : '주소 정보를 불러오지 못했어요.',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildTag(restaurant.category.isNotEmpty
                            ? restaurant.category
                            : '카테고리 정보 없음'),
                        if (restaurant.zone.isNotEmpty)
                          _buildTag(restaurant.zone),
                        _buildTag(couponLabel,
                            background: const Color(0xFFF3F4F6),
                            textColor: _requiresLogin
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF4B5563)),
                      ],
                    ),
                    if (restaurant.phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '전화: ${restaurant.phoneNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String label,
      {Color background = const Color(0xFFEEF2FF),
      Color textColor = const Color(0xFF312E81)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class AffiliateRestaurantDetailSheet extends StatefulWidget {
  const AffiliateRestaurantDetailSheet({
    super.key,
    required this.restaurant,
    required this.coupons,
    required this.requiresLogin,
    required this.onCouponRedeemed,
    required this.onRewardCouponIssued,
  });

  final AffiliateRestaurantSummary restaurant;
  final List<UserCoupon> coupons;
  final bool requiresLogin;
  final void Function(String couponCode) onCouponRedeemed;
  final void Function(String couponCode) onRewardCouponIssued;

  @override
  State<AffiliateRestaurantDetailSheet> createState() =>
      _AffiliateRestaurantDetailSheetState();
}

class _AffiliateRestaurantDetailSheetState
    extends State<AffiliateRestaurantDetailSheet> {
  late List<UserCoupon> _coupons;
  StampStatus? _stampStatus;
  bool _isStampLoading = true;
  bool _isStampProcessing = false;
  String? _stampError;
  String? _processingCouponCode;

  @override
  void initState() {
    super.initState();
    _coupons = List<UserCoupon>.from(widget.coupons);
    if (!widget.requiresLogin) {
      _loadStampStatus();
    } else {
      _isStampLoading = false;
      _stampError = '로그인 후 스탬프 정보를 확인할 수 있어요.';
    }
  }

  Future<void> _loadStampStatus() async {
    setState(() {
      _isStampLoading = true;
      _stampError = null;
    });
    try {
      final status = await CouponService.fetchStampStatus(
        restaurantId: widget.restaurant.id,
      );
      if (!mounted) return;
      setState(() {
        _stampStatus = status;
      });
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError = e.message;
      });
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError =
            _extractDetailMessage(e.body) ?? 'HTTP ${e.statusCode}: ${e.body}';
      });
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError = '네트워크 오류: ${e.cause}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stampError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isStampLoading = false);
      }
    }
  }

  Future<void> _handleAddStamp() async {
    final pin = await _promptForPin(
      title: '스탬프 적립',
      confirmLabel: '적립하기',
    );
    if (pin == null) return;

    setState(() => _isStampProcessing = true);
    try {
      final result = await CouponService.addStamp(
        restaurantId: widget.restaurant.id,
        pin: pin,
      );
      if (!mounted) return;
      setState(() {
        _stampStatus = result.status;
      });
      _showSnack('스탬프를 적립했어요.');
      final reward = result.rewardCouponCode;
      if (reward != null && reward.isNotEmpty) {
        final rewardCoupon = UserCoupon(
          code: reward,
          status: CouponStatus.issued,
          restaurantId: widget.restaurant.id,
        );
        setState(() {
          _coupons = List<UserCoupon>.from(_coupons)..add(rewardCoupon);
        });
        widget.onRewardCouponIssued(reward);
        _showSnack('리워드 쿠폰이 발급되었어요: $reward');
      }
    } on ApiAuthException catch (e) {
      _showSnack(e.message);
    } on ApiHttpException catch (e) {
      _showSnack(
          _extractDetailMessage(e.body) ?? '요청이 실패했어요 (HTTP ${e.statusCode})');
    } on ApiNetworkException catch (e) {
      _showSnack('네트워크 오류: ${e.cause}');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isStampProcessing = false);
      }
    }
  }

  Future<void> _handleRedeem(UserCoupon coupon) async {
    final pin = await _promptForPin(
      title: '쿠폰 사용',
      confirmLabel: '사용하기',
    );
    if (pin == null) return;

    setState(() => _processingCouponCode = coupon.code);
    try {
      await CouponService.redeemCoupon(
        couponCode: coupon.code,
        restaurantId: widget.restaurant.id,
        pin: pin,
      );
      if (!mounted) return;
      setState(() {
        _coupons = _coupons.where((item) => item.code != coupon.code).toList();
      });
      widget.onCouponRedeemed(coupon.code);
      _showSnack('쿠폰을 사용했어요.');
    } on ApiAuthException catch (e) {
      _showSnack(e.message);
    } on ApiHttpException catch (e) {
      _showSnack(
          _extractDetailMessage(e.body) ?? '요청이 실패했어요 (HTTP ${e.statusCode})');
    } on ApiNetworkException catch (e) {
      _showSnack('네트워크 오류: ${e.cause}');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _processingCouponCode = null);
      }
    }
  }

  Future<String?> _promptForPin({
    required String title,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: InputDecoration(
                      labelText: 'PIN (4자리)',
                      counterText: '',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '제휴 매장 관리자가 제공한 4자리 PIN을 입력해 주세요.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.length != 4) {
                      setState(() {
                        error = 'PIN은 4자리 숫자여야 합니다.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSnack(String message) {
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = widget.restaurant;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  restaurant.name.isNotEmpty
                      ? restaurant.name
                      : '매장 정보를 찾을 수 없어요',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  restaurant.address.isNotEmpty
                      ? restaurant.address
                      : '주소 정보를 불러오지 못했어요.',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (restaurant.category.isNotEmpty)
                      _buildInfoChip(restaurant.category),
                    if (restaurant.zone.isNotEmpty)
                      _buildInfoChip(restaurant.zone),
                    if (restaurant.phoneNumber.isNotEmpty)
                      _buildInfoChip('전화 ${restaurant.phoneNumber}'),
                  ],
                ),
                if (restaurant.url != null && restaurant.url!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _openRestaurantPage,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('네이버 지도로 이동'),
                  ),
                ],
                const SizedBox(height: 24),
                _buildStampSection(),
                const SizedBox(height: 24),
                _buildCouponSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStampSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '스탬프 적립',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '스탬프 갱신',
                onPressed: _isStampLoading || widget.requiresLogin
                    ? null
                    : _loadStampStatus,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.requiresLogin)
            const Text('로그인 후 스탬프를 적립할 수 있어요.')
          else if (_isStampLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            _buildStampProgress(),
            if (_stampError != null) ...[
              const SizedBox(height: 12),
              Text(
                _stampError!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isStampProcessing ? null : _handleAddStamp,
                child: _isStampProcessing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('적립 중...'),
                        ],
                      )
                    : const Text('스탬프 적립하기'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStampProgress() {
    final status = _stampStatus;
    if (status == null) {
      return const Text('스탬프 정보를 불러오지 못했어요.');
    }
    final target = status.target <= 0 ? 1 : status.target;
    final progress = (status.current / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        ),
        const SizedBox(height: 8),
        Text('${status.current} / ${status.target}'),
        if (status.updatedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            '업데이트: ${_formatDate(status.updatedAt!)}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCouponSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '보유 쿠폰',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.requiresLogin)
            const Text('로그인하면 제휴 쿠폰을 확인할 수 있어요.')
          else if (_coupons.isEmpty)
            const Text('사용 가능한 쿠폰이 없어요.')
          else
            Column(
              children:
                  _coupons.map((coupon) => _buildCouponTile(coupon)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildCouponTile(UserCoupon coupon) {
    final isProcessing = _processingCouponCode == coupon.code;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.code,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _couponStatusLabel(coupon.status),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: isProcessing || widget.requiresLogin
                ? null
                : () => _handleRedeem(coupon),
            child: isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('사용'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF4B5563),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openRestaurantPage() async {
    final url = widget.restaurant.url;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('유효한 링크가 아니에요.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('링크를 열 수 없어요.');
    }
  }

  String _couponStatusLabel(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return '사용 가능';
      case CouponStatus.redeemed:
        return '사용됨';
      case CouponStatus.expired:
        return '만료됨';
      case CouponStatus.canceled:
        return '취소됨';
      case CouponStatus.unknown:
        return '상태 확인 불가';
    }
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String? _extractDetailMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        const keys = ['detail', 'message', 'error'];
        for (final key in keys) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) {
            return value;
          }
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) {
              return first;
            }
          }
        }
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is String && value.isNotEmpty) {
            return value;
          }
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) {
              return first;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
