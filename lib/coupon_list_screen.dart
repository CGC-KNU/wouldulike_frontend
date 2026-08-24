import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';

import 'coupon/coupon_use_screen.dart';
import 'services/api_client.dart';
import 'services/coupon_service.dart'
    show
        CouponService,
        CouponStatus,
        UserCoupon,
        kCouponBenefitFallbackTitle,
        kCouponBenefitFallbackSubtitle;

class _CouponCategoryMeta {
  const _CouponCategoryMeta(this.label, this.assetPath);

  final String label;
  final String assetPath;
}

const Map<String, _CouponCategoryMeta> _kCouponCategoryMeta = {
  'ALL': _CouponCategoryMeta('전체', 'assets/images/total.png'),
  'KOREAN': _CouponCategoryMeta('한식', 'assets/images/korean.png'),
  'CHINESE': _CouponCategoryMeta('중식', 'assets/images/chinese.png'),
  'JAPANESE': _CouponCategoryMeta('일식', 'assets/images/japanese.png'),
  'WESTERN': _CouponCategoryMeta('양식', 'assets/images/western.png'),
  'SNACK': _CouponCategoryMeta('분식', 'assets/images/snack.png'),
  'PUB': _CouponCategoryMeta('술집', 'assets/images/pub.png'),
  'CAFE': _CouponCategoryMeta('카페', 'assets/images/cafe.png'),
  'DONKATSU': _CouponCategoryMeta('돈가스', 'assets/images/donkatsu.png'),
  'HAMBURGER': _CouponCategoryMeta('햄버거', 'assets/images/hamburger.png'),
  'ETC': _CouponCategoryMeta('기타', 'assets/images/total.png'),
  'UNCLASSIFIED': _CouponCategoryMeta('미분류', 'assets/images/total.png'),
};

const Map<String, String> _kCouponCategoryAlias = {
  'ALL': 'ALL',
  '전체': 'ALL',
  'KOREAN': 'KOREAN',
  '한식': 'KOREAN',
  '고기/구이': 'KOREAN',
  'CHINESE': 'CHINESE',
  '중식': 'CHINESE',
  'JAPANESE': 'JAPANESE',
  '일식': 'JAPANESE',
  'WESTERN': 'WESTERN',
  '양식': 'WESTERN',
  'SNACK': 'SNACK',
  '분식': 'SNACK',
  'PUB': 'PUB',
  'BAR': 'PUB',
  '술집': 'PUB',
  'CAFE': 'CAFE',
  '카페': 'CAFE',
  'DONKATSU': 'DONKATSU',
  '돈가스': 'DONKATSU',
  'HAMBURGER': 'HAMBURGER',
  '햄버거': 'HAMBURGER',
  'ETC': 'ETC',
  '기타': 'ETC',
  '아시안': 'ETC',
  'UNCLASSIFIED': 'UNCLASSIFIED',
  '미분류': 'UNCLASSIFIED',
};

const List<String> _kCouponCategoryOrder = [
  'ALL',
  'KOREAN',
  'CHINESE',
  'JAPANESE',
  'WESTERN',
  'SNACK',
  'PUB',
  'CAFE',
  'DONKATSU',
  'HAMBURGER',
  'ETC',
  'UNCLASSIFIED',
];

class CouponListScreen extends StatefulWidget {
  const CouponListScreen({
    super.key,
    this.source,
    this.embedded = false,
    this.onGoToAffiliate,
  });

  final String? source;

  /// 지갑 탭 안에 임베드될 때 true — Scaffold 없이 본문만 렌더링
  final bool embedded;

  /// 빈 상태에서 "대학가 근처 식당 보러 가기" 이동 콜백 (지갑 임베드 시)
  final VoidCallback? onGoToAffiliate;

  @override
  State<CouponListScreen> createState() => _CouponListScreenState();
}

class _CouponListScreenState extends State<CouponListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<UserCoupon> _coupons = const [];
  String? _processingCouponCode;
  bool _requiresLogin = false;
  String _selectedCategory = 'ALL';
  List<String> _categories = const ['ALL'];
  bool _expiringOnly = false;

  int _statusPriority(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return 0;
      case CouponStatus.redeemed:
        return 1;
      case CouponStatus.expired:
        return 2;
      case CouponStatus.canceled:
        return 3;
      case CouponStatus.unknown:
        return 4;
    }
  }

  /// 정렬 기준 날짜: 사용 완료는 updatedAt, 그 외는 issuedAt. 없으면 expiresAt 사용.
  DateTime? _sortDate(UserCoupon c) => c.updatedAt ?? c.issuedAt ?? c.expiresAt;

  List<UserCoupon> _sortedCoupons(List<UserCoupon> coupons) {
    final sorted = List<UserCoupon>.from(coupons);
    sorted.sort((a, b) {
      final dateA = _sortDate(a);
      final dateB = _sortDate(b);
      if (dateA != null && dateB != null) {
        final cmp = dateB.compareTo(dateA);
        if (cmp != 0) return cmp;
      } else if (dateA != null)
        return -1;
      else if (dateB != null) return 1;
      final statusDiff = _statusPriority(a.status) - _statusPriority(b.status);
      if (statusDiff != 0) return statusDiff;
      return a.code.compareTo(b.code);
    });
    return sorted;
  }

  String _normalizeCategoryKey(String category) {
    final normalized = category.trim().toUpperCase();
    return _kCouponCategoryAlias[normalized] ??
        _kCouponCategoryAlias[category.trim()] ??
        normalized;
  }

  int _categoryOrderIndex(String category) {
    final normalized = _normalizeCategoryKey(category);
    final index = _kCouponCategoryOrder.indexOf(normalized);
    return index == -1 ? _kCouponCategoryOrder.length : index;
  }

  List<String> _sortCategories(Iterable<String> source) {
    final list = source.toSet().toList();
    list.sort((a, b) {
      final orderA = _categoryOrderIndex(a);
      final orderB = _categoryOrderIndex(b);
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }
      return a.compareTo(b);
    });
    return list;
  }

  String _couponCategoryKey(UserCoupon coupon) {
    final raw =
        (coupon.restaurantCategory ?? coupon.benefit?.restaurantCategory)
            ?.trim();
    if (raw == null || raw.isEmpty) return 'UNCLASSIFIED';
    final key = _normalizeCategoryKey(raw);
    if (_kCouponCategoryMeta.containsKey(key)) {
      return key;
    }
    return raw;
  }

  List<String> _deriveCategories(List<UserCoupon> coupons) {
    return _sortCategories({
      'ALL',
      ...coupons.map(_couponCategoryKey),
    });
  }

  _CouponCategoryMeta _resolveCategoryMeta(String category) {
    final key = _normalizeCategoryKey(category);
    final meta = _kCouponCategoryMeta[key];
    if (meta != null) return meta;
    final trimmed = category.trim();
    return _CouponCategoryMeta(
      trimmed.isEmpty ? '기타' : trimmed,
      _kCouponCategoryMeta['ALL']!.assetPath,
    );
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
    });
  }

  @override
  void initState() {
    super.initState();
    AnalyticsLogger.logEvent(
      'coupon_page_view',
      parameters: {
        if (widget.source != null) 'source': widget.source!,
      },
    );
    _loadCoupons();
  }

  Future<void> _loadCoupons() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _requiresLogin = false;
    });

    try {
      // 안전망으로 화면 단에서도 최대 10초까지만 기다리고,
      // 그 이상 걸리면 에러 UI를 통해 다시 시도를 안내한다.
      final coupons = await CouponService.fetchMyCoupons().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted) return;
      final issuedCoupons = coupons
          .where((coupon) => coupon.status == CouponStatus.issued)
          .toList();
      _logCouponIssueBreakdown(issuedCoupons);
      final categories = _deriveCategories(issuedCoupons);
      setState(() {
        _coupons = _sortedCoupons(issuedCoupons);
        _categories = categories;
        if (!categories.contains(_selectedCategory)) {
          _selectedCategory = 'ALL';
        }
        _isLoading = false;
        _processingCouponCode = null;
      });
    } on ApiAuthException {
      // 로그인 필요 상태: 자세한 에러 메시지는 노출하지 않고
      // 전용 로그인 안내 UI를 보여준다.
      if (!mounted) return;
      setState(() {
        _requiresLogin = true;
        _isLoading = false;
        _coupons = const [];
        _categories = const ['ALL'];
        _selectedCategory = 'ALL';
        _processingCouponCode = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'TIMEOUT';
        _isLoading = false;
        _coupons = const [];
        _categories = const ['ALL'];
        _selectedCategory = 'ALL';
      });
    } on ApiHttpException catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'HTTP_ERROR';
        _isLoading = false;
        _coupons = const [];
        _categories = const ['ALL'];
        _selectedCategory = 'ALL';
      });
    } on ApiNetworkException catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'NETWORK_ERROR';
        _isLoading = false;
        _coupons = const [];
        _categories = const ['ALL'];
        _selectedCategory = 'ALL';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'UNKNOWN_ERROR';
        _isLoading = false;
        _coupons = const [];
        _categories = const ['ALL'];
        _selectedCategory = 'ALL';
      });
    }
  }

  void _logCouponIssueBreakdown(List<UserCoupon> coupons) {
    final counts = <String, int>{};
    for (final c in coupons) {
      final source = c.couponIssueSource;
      counts[source] = (counts[source] ?? 0) + 1;
    }
    for (final entry in counts.entries) {
      if (entry.value > 0) {
        AnalyticsLogger.logEvent(
          AnalyticsEvents.couponIssueBreakdown,
          parameters: {
            AnalyticsEvents.paramIssueSource: entry.key,
            AnalyticsEvents.paramCount: entry.value,
          },
        );
      }
    }
  }

  /// 만료임박 = 잔여 3일 이하 (스펙 7.1)
  bool _isExpiringSoon(UserCoupon coupon) {
    final expiresAt = coupon.expiresAt;
    if (expiresAt == null) return false;
    final diff = expiresAt.difference(DateTime.now());
    return !diff.isNegative && diff <= const Duration(days: 3);
  }

  List<UserCoupon> get _filteredCoupons {
    Iterable<UserCoupon> result = _coupons;
    if (_selectedCategory != 'ALL') {
      result = result
          .where((coupon) => _couponCategoryKey(coupon) == _selectedCategory);
    }
    if (_expiringOnly) {
      result = result.where(_isExpiringSoon);
    }
    return result.toList();
  }

  /// 지갑 임베드 시 상태 필터 칩 (전체 / 만료임박)
  Widget _buildStatusFilter() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF192132) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFF192132) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Pretendard',
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : const Color(0xFF797979),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('전체', !_expiringOnly, () {
          if (_expiringOnly) setState(() => _expiringOnly = false);
        }),
        const SizedBox(width: 8),
        chip('만료임박', _expiringOnly, () {
          if (!_expiringOnly) setState(() => _expiringOnly = true);
        }),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    if (_categories.isEmpty) {
      return const SizedBox.shrink();
    }
    const double scale = 1.00;
    return SizedBox(
      height: 90 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => SizedBox(width: 12 * scale),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          final meta = _resolveCategoryMeta(category);
          final textStyle = TextStyle(
            color: selected ? const Color(0xFF172133) : const Color(0xFF797979),
            fontSize: 12 * scale,
            fontFamily: 'Pretendard',
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            height: 1.92,
          );

          return InkWell(
            onTap: () => _selectCategory(category),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 52 * scale,
              height: 66 * scale,
              decoration: ShapeDecoration(
                color: selected
                    ? const Color(0x99C7CDD1)
                    : const Color(0xFFF9FAFB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 6 * scale,
                vertical: 8 * scale,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Image.asset(
                      meta.assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    meta.label,
                    style: textStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 상태 색상은 상세 시트 디자인에 맞춘 배지 스타일에서 처리하므로
  // 더 이상 별도 매핑이 필요 없어졌다.

  Future<void> _handleRedeem(UserCoupon coupon) async {
    final restaurantId = coupon.restaurantId;
    if (restaurantId == null) {
      _showSnack('이 쿠폰은 사용 가능한 매장 정보가 없어요.');
      return;
    }

    setState(() => _processingCouponCode = coupon.code);
    try {
      // "쑥스러움 제거" 전체 화면 사용 화면으로 진입.
      // 실제 사용 처리는 그 안의 "직원 확인"(관리자 PIN)에서 이뤄진다.
      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CouponUseScreen(
            coupon: coupon,
            restaurantId: restaurantId,
          ),
        ),
      );
      if (!mounted) return;
      if (success == true) {
        setState(() {
          _coupons =
              _coupons.where((element) => element.code != coupon.code).toList();
        });
        _showSnack('쿠폰을 사용했어요.');
      }
    } finally {
      if (mounted && _processingCouponCode == coupon.code) {
        setState(() => _processingCouponCode = null);
      }
    }
  }

  /// 쿠폰 사용 PIN 다이얼로그 (레거시 — 현재는 CouponUseScreen 사용).
  // ignore: unused_element
  Future<bool> _showRedeemPinDialog({
    required UserCoupon coupon,
    required int restaurantId,
    String? restaurantName,
    String? notes,
  }) async {
    final controller = TextEditingController();
    String? error;
    bool isLoading = false;
    final hasNotes = notes != null && notes.isNotEmpty;
    return (await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(builder: (context, setState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: 358,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFF2F2F2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '쿠폰 사용',
                          style: TextStyle(
                            color: Color(0xFF39393E),
                            fontSize: 19,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w800,
                            height: 1.21,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 330,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: '해당 쿠폰을 사용처리 하시겠습니까?\n관리자 비밀번호를 입력하시면',
                                  style: TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 15,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w500,
                                    height: 1.20,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' 즉시 사용처리',
                                  style: TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 15,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w700,
                                    height: 1.20,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' 됩니다.',
                                  style: TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 15,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w500,
                                    height: 1.20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (hasNotes) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE5E5E5),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '사용 조건',
                                  style: TextStyle(
                                    color: Color(0xFF797979),
                                    fontSize: 12,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  notes,
                                  style: const TextStyle(
                                    color: Color(0xFF39393E),
                                    fontSize: 14,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          '비밀번호',
                          style: TextStyle(
                            color: Color(0xFF797979),
                            fontSize: 15,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          height: 40,
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                width: 2,
                                color: Color(0xFFD9D9D9),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          child: TextField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 4,
                            enabled: !isLoading,
                            style: const TextStyle(
                              color: Color(0xFF39393E),
                              fontSize: 16,
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              counterText: '',
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 12,
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isLoading
                                    ? null
                                    : () =>
                                        Navigator.of(dialogContext).pop(false),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  foregroundColor: const Color(0xFF39393E),
                                  side: const BorderSide(
                                      color: Color(0xFFBABAC0)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                child: const Text('취소'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isLoading
                                    ? null
                                    : () async {
                                        final value = controller.text.trim();
                                        if (value.length != 4) {
                                          setState(() {
                                            error = 'PIN은 4자리 숫자여야 합니다.';
                                          });
                                          return;
                                        }
                                        setState(() {
                                          error = null;
                                          isLoading = true;
                                        });
                                        final result = await CouponService
                                            .redeemCouponWithoutThrow(
                                          couponCode: coupon.code,
                                          restaurantId: restaurantId,
                                          pin: value,
                                        );
                                        if (!dialogContext.mounted) return;
                                        if (result.isSuccess) {
                                          AnalyticsLogger.logEvent(
                                            AnalyticsEvents.couponRedeemed,
                                            parameters: {
                                              AnalyticsEvents.paramCouponCode:
                                                  coupon.code,
                                              AnalyticsEvents.paramRestaurantId:
                                                  restaurantId,
                                              AnalyticsEvents
                                                      .paramRestaurantName:
                                                  restaurantName ?? '',
                                              AnalyticsEvents
                                                      .paramCouponIssueSource:
                                                  coupon.couponIssueSource,
                                            },
                                          );
                                          Navigator.of(dialogContext).pop(true);
                                        } else {
                                          setState(() {
                                            error = result.errorMessage ??
                                                '비밀번호가 올바르지 않아요. 다시 확인해 주세요.';
                                            isLoading = false;
                                          });
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1C203C),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  textStyle: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    letterSpacing: -0.32,
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('사용하기'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            });
          },
        )) ??
        false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  String? _formatExpiryDate(DateTime? expiresAt) {
    if (expiresAt == null) return null;

    final now = DateTime.now();
    final difference = expiresAt.difference(now);

    // Already expired
    if (difference.isNegative) {
      return '만료됨';
    }

    // Less than 24 hours
    if (difference.inHours < 24) {
      if (difference.inHours > 0) {
        return '${difference.inHours}시간 남음';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}분 남음';
      } else {
        return '곧 만료';
      }
    }

    // Less than 7 days
    if (difference.inDays < 7) {
      return '${difference.inDays}일 남음';
    }

    // 7 days or more - show date
    return '${expiresAt.year}.${expiresAt.month.toString().padLeft(2, '0')}.${expiresAt.day.toString().padLeft(2, '0')}까지';
  }

  @override
  Widget build(BuildContext context) {
    final content = RefreshIndicator(
      // 일반 화면 진입 로딩과 동일한 톤의 인디케이터 사용
      color: const Color(0xFF6366F1),
      backgroundColor: Colors.white,
      strokeWidth: 2,
      onRefresh: _loadCoupons,
      child: _buildBody(),
    );

    if (widget.embedded) {
      return Container(
        color: const Color(0xFFF9FAFB),
        child: content,
      );
    }

    return Scaffold(
      appBar: widget.source == 'tab'
          ? AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              scrolledUnderElevation: 0,
              elevation: 0,
              toolbarHeight: 0,
            )
          : AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              scrolledUnderElevation: 0,
              elevation: 0,
              title: const Text(
                '내 쿠폰',
                style: TextStyle(color: Colors.black),
              ),
              iconTheme: const IconThemeData(color: Colors.black),
            ),
      backgroundColor: const Color(0xFFF9FAFB),
      body: content,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requiresLogin) {
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
                  const Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: Color(0xFF312E81),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      '로그인하면 보유한 쿠폰을 확인할 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.of(context).pushNamed(
                        '/login',
                        arguments: const {'redirect': 'coupon_list'},
                      );
                      // 로그인 화면에서 쿠폰 리스트를 미리 불러온 경우
                      // 바로 상태를 갱신하고, 실패했으면 기존 로딩 로직을 사용.
                      if (result is List<UserCoupon>) {
                        final issuedCoupons = result
                            .where((coupon) =>
                                coupon.status == CouponStatus.issued)
                            .toList();
                        final sorted = _sortedCoupons(issuedCoupons);
                        final categories = _deriveCategories(issuedCoupons);
                        setState(() {
                          _requiresLogin = false;
                          _errorMessage = null;
                          _isLoading = false;
                          _coupons = sorted;
                          _categories = categories;
                          if (!categories.contains(_selectedCategory)) {
                            _selectedCategory = 'ALL';
                          }
                        });
                      } else if (result == true) {
                        await _loadCoupons();
                      }
                    },
                    child: const Text('카카오로 로그인'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
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
                  const Icon(
                    Icons.refresh,
                    size: 40,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '쿠폰을 불러오지 못했어요.\n다시 시도해 주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadCoupons,
                    child: const Text('새로고침'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_coupons.isEmpty) {
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
                  const Text(
                    '보유한 쿠폰이 아직 없어요.',
                    style: TextStyle(fontSize: 16),
                  ),
                  if (widget.onGoToAffiliate != null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: widget.onGoToAffiliate,
                      child: const Text('대학가 근처 식당 보러 가기'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final filtered = _filteredCoupons;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 140, // 하단 바와 겹치지 않도록 다른 탭과 동일한 여백
      ),
      children: [
        _buildCategoryFilter(),
        if (widget.embedded) ...[
          const SizedBox(height: 12),
          _buildStatusFilter(),
        ],
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.25,
            child: Center(
              child: Text(
                _expiringOnly
                    ? '만료 임박한 쿠폰이 없어요.'
                    : _selectedCategory != 'ALL'
                        ? '선택한 카테고리의 쿠폰이 없어요.'
                        : '사용 가능한 쿠폰이 없어요.',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          )
        else ...[
          for (final coupon in filtered) _buildCouponTile(coupon),
        ],
      ],
    );
  }

  Widget _buildCouponTile(UserCoupon coupon) {
    final bool isProcessing = _processingCouponCode == coupon.code;
    final benefit = coupon.benefit;
    final title = benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle;
    final subtitle =
        benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle;
    final String? restaurantName = benefit?.restaurantNameText;
    String? restaurantLabel;
    if (restaurantName != null && restaurantName.isNotEmpty) {
      restaurantLabel = restaurantName;
    } else if (coupon.restaurantId != null) {
      restaurantLabel = '적용 매장 ID: ${coupon.restaurantId}';
    }
    final expiryText = _formatExpiryDate(coupon.expiresAt);
    final isExpiryUrgent = coupon.expiresAt != null &&
        coupon.expiresAt!.difference(DateTime.now()) <= const Duration(days: 7);
    final expiryColor =
        isExpiryUrgent ? const Color(0xFFB87270) : const Color(0xFFE1B53E);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF192132),
      ),
      child: IntrinsicHeight(
        child: Row(
          // ListView 안에서 높이가 무한대로 주어질 수 있기 때문에
          // stretch를 직접 사용하면 h=Infinity 제약이 전달될 수 있어
          // IntrinsicHeight로 한 번 감싸 높이를 한정한 뒤, 버튼을
          // 우측 하단에 정렬한다.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (restaurantLabel != null) ...[
                    Text(
                      restaurantLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCBD5FF),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  if (coupon.status != CouponStatus.redeemed) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFD1D6FF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (expiryText != null &&
                      coupon.status == CouponStatus.issued) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_isExpiringSoon(coupon)) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB87270),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '마감임박',
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: expiryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          expiryText,
                          style: TextStyle(
                            fontSize: 12,
                            color: expiryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (coupon.status == CouponStatus.issued) ...[
              const SizedBox(width: 12),
              SizedBox(
                height: double.infinity,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: ElevatedButton(
                    onPressed:
                        isProcessing ? null : () => _handleRedeem(coupon),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0B1033),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0B1033),
                            ),
                          )
                        : const Text('사용'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 쿠폰 상태 배지는 상단 탭으로 대체되었기 때문에,
  // 블록 내부에는 별도의 상태 텍스트를 표시하지 않는다.
}
