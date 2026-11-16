import 'package:flutter/material.dart';

/// 쿠폰 사용 화면과 스탬프 적립 화면이 같이 쓰는 PIN 입력 조각들.
/// 두 화면이 계속 같은 모양이도록 한 곳에 둔다.
class PinEntryColors {
  PinEntryColors._();

  static const Color primary = Color(0xFF4F46E5);
  static const Color lav = Color(0xFFEEEDFC);
  static const Color bg = Color(0xFFF6F6FA);
  static const Color ink = Color(0xFF191F28);
  static const Color sub = Color(0xFF8B95A1);
  static const Color line = Color(0xFFECECF3);
  static const Color red = Color(0xFFE11D48);
  static const Color redBg = Color(0xFFFDECEC);
}

/// PIN 자리 수만큼의 입력 칸. 채워진 칸은 점으로 가린다.
class PinBoxes extends StatelessWidget {
  const PinBoxes({
    super.key,
    required this.length,
    required this.pin,
    this.hasError = false,
    this.active = true,
  });

  final int length;
  final String pin;
  final bool hasError;

  /// 다음에 입력될 칸을 강조할지 (처리 중·잠김이면 끈다).
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final filled = i < pin.length;
        final current = i == pin.length && active;
        return Container(
          width: 44,
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? PinEntryColors.lav : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasError
                  ? PinEntryColors.red
                  : (filled || current
                      ? PinEntryColors.primary
                      : const Color(0xFFDADBE4)),
              width: 1.5,
            ),
          ),
          child: filled
              ? const Text(
                  '•',
                  style: TextStyle(
                      fontSize: 26, height: 1, color: PinEntryColors.ink),
                )
              : null,
        );
      }),
    );
  }
}

/// 시스템 키보드 대신 화면 하단 숫자 패드. 계산대에서 직원이 바로 누른다.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.disabled = false,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        18,
        6,
        18,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.6,
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          final isBack = k == '⌫';
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled ? null : (isBack ? onBackspace : () => onDigit(k)),
            child: Center(
              child: isBack
                  ? Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color:
                          disabled ? PinEntryColors.line : PinEntryColors.ink,
                    )
                  : Text(
                      k,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color:
                            disabled ? PinEntryColors.line : PinEntryColors.ink,
                      ),
                    ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 티켓 카드 안의 점선 구분선.
class PinDashedDivider extends StatelessWidget {
  const PinDashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashW = 6.0;
        const gap = 5.0;
        final count = (constraints.maxWidth / (dashW + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dashW,
              height: 1.5,
              color: const Color(0xFFD9DAE4),
            ),
          ),
        );
      },
    );
  }
}
