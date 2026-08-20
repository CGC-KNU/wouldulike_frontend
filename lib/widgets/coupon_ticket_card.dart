import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 쿠폰 티켓 카드. 지갑 쿠폰함과 식당 상세가 같은 디자인을 쓰도록 공용화한 위젯.
/// 표시 전용 — 라벨 계산과 사용 처리는 호출부가 한다.
class CouponTicketCard extends StatelessWidget {
  const CouponTicketCard({
    super.key,
    required this.iconPath,
    required this.storeLabel,
    required this.title,
    required this.subtitle,
    required this.notchColor,
    this.expiryText,
    this.expiryUrgent = false,
    this.actionLabel = '사용하기',
    this.onAction,
    this.isProcessing = false,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  /// 카테고리 SVG (assets/icons/category/*.svg)
  final String iconPath;
  final String storeLabel;
  final String title;
  final String subtitle;

  /// 티켓 노치는 카드 바깥으로 걸치므로 배경과 같은 색이어야 파인 것처럼 보인다.
  final Color notchColor;
  final String? expiryText;
  final bool expiryUrgent;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool isProcessing;
  final EdgeInsets margin;

  static const _ink = Color(0xFF191F28);
  static const _sub = Color(0xFF8B95A1);
  static const _primary = Color(0xFF4F46E5);
  static const _deep = Color(0xFF312E81);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
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
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            SvgPicture.asset(iconPath, width: 34, height: 34),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                storeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Pretendard',
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  height: 1.3,
                                  color: Color(0xFF333D4B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.85,
                            height: 1.3,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                            color: _sub,
                          ),
                        ),
                        if (expiryText != null) ...[
                          const SizedBox(height: 12),
                          _ExpiryChip(
                            text: expiryText!,
                            urgent: expiryUrgent,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 106,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 106,
                          child: ElevatedButton(
                            onPressed: isProcessing ? null : onAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFC7CCFF),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14.5,
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            child: isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(actionLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(left: -10, child: _TicketNotch(color: notchColor)),
          Positioned(right: -10, child: _TicketNotch(color: notchColor)),
        ],
      ),
    );
  }

  static Color get accent => _deep;
}

class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({required this.text, required this.urgent});

  final String text;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color =
        urgent ? const Color(0xFFE11D48) : const Color(0xFF4F46E5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xFFFFEBEF) : const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketNotch extends StatelessWidget {
  const _TicketNotch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
