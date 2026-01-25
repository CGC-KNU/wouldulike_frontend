import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:new1/utils/analytics_logger.dart';

import 'services/api_client.dart';
import 'services/coupon_service.dart';

class CouponListScreen extends StatefulWidget {
  const CouponListScreen({super.key, this.source});

  final String? source;

  @override
  State<CouponListScreen> createState() => _CouponListScreenState();
}

class _CouponListScreenState extends State<CouponListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<UserCoupon> _coupons = const [];
  String? _processingCouponCode;
  bool _requiresLogin = false;
  int _selectedTabIndex = 0; // 0: 사용 가능, 1: 사용 완료

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

  List<UserCoupon> _sortedCoupons(List<UserCoupon> coupons) {
    final sorted = List<UserCoupon>.from(coupons);
    sorted.sort((a, b) {
      final priorityDiff = _statusPriority(a.status) - _statusPriority(b.status);
      if (priorityDiff != 0) return priorityDiff;
      return a.code.compareTo(b.code);
    });
    return sorted;
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
      setState(() {
        _coupons = _sortedCoupons(coupons);
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
        _processingCouponCode = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'TIMEOUT';
        _isLoading = false;
        _coupons = const [];
      });
    } on ApiHttpException catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'HTTP_ERROR';
        _isLoading = false;
        _coupons = const [];
      });
    } on ApiNetworkException catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'NETWORK_ERROR';
        _isLoading = false;
        _coupons = const [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'UNKNOWN_ERROR';
        _isLoading = false;
        _coupons = const [];
      });
    }
  }

  List<UserCoupon> get _availableCoupons =>
      _coupons.where((c) => c.status == CouponStatus.issued).toList();

  List<UserCoupon> get _completedCoupons =>
      _coupons.where((c) => c.status != CouponStatus.issued).toList();

  List<UserCoupon> get _filteredCoupons {
    if (_selectedTabIndex == 0) {
      return _availableCoupons;
    }
    return _completedCoupons;
  }

  void _selectStatusTab(int index) {
    if (_selectedTabIndex == index) return;
    setState(() {
      _selectedTabIndex = index;
    });
  }

  Widget _buildStatusTabSwitcher({
    required int availableCount,
    required int completedCount,
  }) {
    const labels = ['사용 가능', '사용 완료'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE7E9F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = _selectedTabIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => _selectStatusTab(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0B1033).withOpacity(0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[index],
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: selected
                            ? const Color(0xFF111439)
                            : const Color(0xFF6B6F94),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
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

    final pin = await _promptForPin(
      title: '쿠폰 사용',
      confirmLabel: '사용하기',
    );
    if (pin == null) return;

    setState(() => _processingCouponCode = coupon.code);
    try {
      await CouponService.redeemCoupon(
        couponCode: coupon.code,
        restaurantId: restaurantId,
        pin: pin,
      );
      if (!mounted) return;
      setState(() {
        _coupons =
            _coupons.where((element) => element.code != coupon.code).toList();
        _processingCouponCode = null;
      });
      _showSnack('쿠폰을 사용했어요.');
    } on ApiAuthException catch (e) {
      _showSnack(e.message);
    } on ApiHttpException catch (e) {
      _showSnack(_extractDetailMessage(e.body) ?? '쿠폰 사용에 실패했어요.');
    } on ApiNetworkException catch (e) {
      _showSnack('네트워크 오류: $e');
    } catch (e) {
      _showSnack('알 수 없는 오류: $e');
    } finally {
      if (mounted && _processingCouponCode == coupon.code) {
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
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
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 55,
                    height: 40,
                    child: Text(
                      '비밀번호',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF797979),
                        fontSize: 15,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
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
                        errorText: error,
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
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            foregroundColor: const Color(0xFF39393E),
                            side: const BorderSide(color: Color(0xFFBABAC0)),
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1C203C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
                          child: Text(confirmLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
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
    return Scaffold(
      appBar: AppBar(
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
      body: RefreshIndicator(
        // 일반 화면 진입 로딩과 동일한 톤의 인디케이터 사용
        color: const Color(0xFF6366F1),
        backgroundColor: Colors.white,
        strokeWidth: 2,
        onRefresh: _loadCoupons,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requiresLogin) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                        setState(() {
                          _requiresLogin = false;
                          _errorMessage = null;
                          _isLoading = false;
                          _coupons = _sortedCoupons(result);
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
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: const Center(
              child: Text(
                '보유한 쿠폰이 아직 없어요.',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      );
    }

    final availableCount = _availableCoupons.length;
    final completedCount = _completedCoupons.length;
    final filtered = _filteredCoupons;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildStatusTabSwitcher(
          availableCount: availableCount,
          completedCount: completedCount,
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.25,
            child: Center(
              child: Text(
                _selectedTabIndex == 0
                    ? '사용 가능한 쿠폰이 없어요.'
                    : '사용 완료된 쿠폰이 없어요.',
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
    final expiryColor = const Color.fromARGB(255, 185, 183, 247);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1033), Color(0xFF1C2470)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
                  if (expiryText != null &&
                      coupon.status == CouponStatus.issued) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
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