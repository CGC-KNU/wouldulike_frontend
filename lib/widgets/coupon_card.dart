import 'package:flutter/material.dart';
import 'package:new1/services/coupon_service.dart';

const String kCouponBenefitFallbackTitle = '혜택 정보 없음';
const String kCouponBenefitFallbackSubtitle = '상세 내용을 확인해 주세요';

class CouponCard extends StatelessWidget {
  final UserCoupon coupon;
  final bool isProcessing;
  final VoidCallback? onRedeem;

  const CouponCard({
    super.key,
    required this.coupon,
    this.isProcessing = false,
    this.onRedeem,
  });

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

  String? _formatExpiryDate(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    return '만료일: ${expiresAt.year}.${expiresAt.month.toString().padLeft(2, '0')}.${expiresAt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(coupon.status);
    final benefit = coupon.benefit;
    final restaurantName = benefit?.restaurantNameText ?? benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle;
    final subtitle = benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle;
    final description = benefit?.descriptionText;
    final expiryText = _formatExpiryDate(coupon.expiresAt);
    final bool isIssued = coupon.status == CouponStatus.issued;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Restaurant name (bold, top)
          Text(
            restaurantName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              fontFamily: 'Pretendard',
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // Benefit subtitle
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w400,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          // Description/type label (red)
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFEF4444),
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // Expiry + Button row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Expiry date (indigo)
              if (expiryText != null)
                Text(
                  expiryText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF312E81),
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const Spacer(),
              // "사용하기" button
              if (isIssued)
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : onRedeem,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF312E81), width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '사용하기',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF312E81),
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              // Status badge for non-issued coupons
              if (!isIssued)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(coupon.status),
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
