import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'ticket_shell.dart';

/// 쿠폰 티켓 카드. 지갑 쿠폰함과 식당 상세가 같은 디자인을 쓰도록 공용화한 위젯.
/// 표시 전용 — 라벨 계산과 사용 처리는 호출부가 한다.
class CouponTicketCard extends StatelessWidget {
  const CouponTicketCard({
    super.key,
    required this.iconPath,
    required this.storeLabel,
    required this.title,
    required this.subtitle,
    this.notes,
    this.expiryText,
    this.expiryUrgent = false,
    this.actionLabel = '사용하기',
    this.onAction,
    this.isProcessing = false,
    this.showAction = true,
    this.borderColor,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  /// 카테고리 SVG (assets/icons/category/*.svg)
  final String iconPath;
  final String storeLabel;
  final String title;
  final String subtitle;

  /// 쿠폰 비고(사용 조건). 없으면 줄 자체를 그리지 않는다.
  final String? notes;

  final String? expiryText;
  final bool expiryUrgent;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool isProcessing;

  /// 온보딩 연출처럼 눌러서 쓸 수 없는 자리에서는 버튼을 숨긴다.
  final bool showAction;

  /// 흰 배경 위에 올릴 때 윤곽선.
  final Color? borderColor;
  final EdgeInsets margin;

  static const _ink = Color(0xFF191F28);
  static const _sub = Color(0xFF8B95A1);
  static const _primary = Color(0xFF4F46E5);
  static const _deep = Color(0xFF312E81);

  @override
  Widget build(BuildContext context) {
    return TicketShell(
      margin: margin,
      borderColor: borderColor,
      // 좌우 노치 없이 매끈한 카드 — 식당 상세와 통일.
      notchRadius: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
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
                    if (notes != null && notes!.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.info_outline_rounded,
                              size: 13,
                              color: _sub,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '사용 조건 · ${notes!}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'Pretendard',
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                letterSpacing: -0.2,
                                color: _sub,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
              if (showAction) ...[
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
            ],
          ),
        ),
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
    final color = urgent ? const Color(0xFFE11D48) : const Color(0xFF4F46E5);
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
