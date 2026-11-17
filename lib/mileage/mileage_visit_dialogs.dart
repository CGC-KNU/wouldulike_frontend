import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/services/app_config_service.dart';

/// 스탬프 없는 매장의 마일리지 적립 창들 (1018 목업).
/// 스탬프 적립 창·성공 창(coupon/stamp_add_dialog.dart)과 같은 모양·크기·색이다.
/// 실패 창은 스탬프 것(showStampAddFailedDialog)을 그대로 쓴다.

const Color _cta = Color(0xFF312E81);

String formatMileage(int value) {
  final s = value.abs().toString();
  final b = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 직원이 매장 PIN 을 넣는 창. 스탬프 적립 창에서 「적립 개수」 칸만 뺐다. 취소하면 null.
Future<String?> showMileageVisitDialog(
  BuildContext context, {
  required int points,
}) {
  final controller = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(builder: (context, setState) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 360,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.75,
            ),
            child: Container(
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
                      '마일리지 적립',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 19,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w800,
                        height: 1.21,
                      ),
                    ),
                    const SizedBox(height: 22),
                    // 스탬프 창과 같은 줄 간격(height 0.70 + 빈 줄)
                    Text(
                      '마일리지를 적립하시겠습니까?\n\n직원이 매장 PIN을 입력하시면\n\n${formatMileage(points)} M이 적립됩니다.',
                      style: const TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 14,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w500,
                        height: 0.70,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '매장 PIN',
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
                        maxLength: AppConfigService.pinLength,
                        style: const TextStyle(
                          color: Color(0xFF39393E),
                          fontSize: 16,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                            AppConfigService.pinLength,
                          ),
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
                              if (value.length != AppConfigService.pinLength) {
                                setState(() {
                                  error =
                                      'PIN은 ${AppConfigService.pinLength}자리 숫자여야 합니다.';
                                });
                                return;
                              }
                              Navigator.of(dialogContext).pop(value);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _cta,
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
                            child: const Text('적립하기'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    },
  ).whenComplete(controller.dispose);
}

/// 적립 완료. 스탬프 적립 성공 창과 같은 틀이고 도장 자리에 마일리지 코인이 들어간다.
Future<void> showMileageEarnedDialog(
  BuildContext context, {
  required int added,
  required int balance,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (context, value, child) => Transform.scale(
                scale: value,
                child: Transform.rotate(angle: (1 - value) * 0.5, child: child),
              ),
              child: Image.asset(
                'assets/images/mileage/mileage_coin.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${formatMileage(added)} M 적립!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Color(0xFF191F28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '보유 마일리지 ${formatMileage(balance)} M\n모은 마일리지로 식사권에 응모할 수 있어요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8B95A1),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cta,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('확인'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
