import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/api_client.dart';
import 'services/coupon_service.dart';

class CouponListScreen extends StatefulWidget {
  const CouponListScreen({super.key});

  @override
  State<CouponListScreen> createState() => _CouponListScreenState();
}

class _CouponListScreenState extends State<CouponListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<UserCoupon> _coupons = const [];
  String? _processingCouponCode;

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
    _loadCoupons();
  }

  Future<void> _loadCoupons() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final coupons = await CouponService.fetchMyCoupons();
      if (!mounted) return;
      setState(() {
        _coupons = _sortedCoupons(coupons);
        _isLoading = false;
        _processingCouponCode = null;
      });
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '쿠폰 정보를 불러오지 못했어요 (${e.statusCode})';
        _isLoading = false;
      });
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '네트워크 오류가 발생했어요: $e';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '예상치 못한 오류가 발생했어요: $e';
        _isLoading = false;
      });
    }
  }

  String _statusLabel(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return '사용 가능';
      case CouponStatus.redeemed:
        return '사용 완료';
      case CouponStatus.expired:
        return '만료';
      case CouponStatus.canceled:
        return '취소';
      case CouponStatus.unknown:
        return '알 수 없음';
    }
  }

  Color _statusColor(CouponStatus status) {
    switch (status) {
      case CouponStatus.issued:
        return const Color(0xFF10B981);
      case CouponStatus.redeemed:
        return const Color(0xFF6366F1);
      case CouponStatus.expired:
        return const Color(0xFFF97316);
      case CouponStatus.canceled:
        return const Color(0xFFEF4444);
      case CouponStatus.unknown:
        return const Color(0xFF6B7280);
    }
  }

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
                    '제휴 매장 관리자가 안내해준 4자리 PIN을 입력해 주세요.',
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
                        error = 'PIN은 4자리 숫자여야 해요.';
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
        title: const Text(
          '내 쿠폰',
          style: TextStyle(color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF9FAFB),
      body: RefreshIndicator(
        onRefresh: _loadCoupons,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
                  const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadCoupons,
                    child: const Text('다시 시도'),
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _coupons.length,
      itemBuilder: (context, index) {
        final coupon = _coupons[index];
        return _buildCouponTile(coupon);
      },
    );
  }

  Widget _buildCouponTile(UserCoupon coupon) {
    final statusColor = _statusColor(coupon.status);
    final statusText = _statusLabel(coupon.status);
    final bool isProcessing = _processingCouponCode == coupon.code;
    final benefit = coupon.benefit;
    final title =
        benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle;
    final subtitle =
        benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle;
    final String restaurantLabel = benefit?.restaurantNameText ??
        (coupon.restaurantId != null
            ? '사용 가능 매장 ID: ${coupon.restaurantId}'
            : '사용 가능한 매장 정보가 없어요.');
    final expiryText = _formatExpiryDate(coupon.expiresAt);
    final expiryColor = const Color(0xFF312E81).withOpacity(0.75);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restaurantLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4B5563),
                  ),
                ),
                if (expiryText != null) ...[
                  const SizedBox(height: 6),
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
          if (coupon.status == CouponStatus.issued)
            TextButton(
              onPressed: isProcessing ? null : () => _handleRedeem(coupon),
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
}
