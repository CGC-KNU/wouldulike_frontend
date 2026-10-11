import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/services/app_config_service.dart';

const Color _stampCta = Color(0xFF312E81);

/// 스탬프 적립 창에서 고른 개수와 매장 PIN.
class StampAddRequest {
  const StampAddRequest({
    required this.pin,
    required this.count,
  });

  final String pin;
  final int count;
}

/// 매장 상세와 지갑 스탬프 탭이 같이 쓰는 적립 창.
/// 개수를 고르고 직원이 매장 PIN을 입력한다. 취소하면 null.
Future<StampAddRequest?> showStampAddDialog(BuildContext context) {
  final controller = TextEditingController();
  var selectedCount = 1;
  String? error;
  return showDialog<StampAddRequest>(
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
                      '스탬프 적립',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 19,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w800,
                        height: 1.21,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '스탬프를 적립하시겠습니까?\n\n적립 개수를 선택하고 직원이 매장 PIN을 입력하시면\n\n스탬프 $selectedCount개가 적립됩니다.',
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
                      '적립 개수',
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
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedCount,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(10),
                          dropdownColor: Colors.white,
                          style: const TextStyle(
                            color: Color(0xFF39393E),
                            fontSize: 16,
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w600,
                          ),
                          items: List.generate(
                            AppConfigService.stampMaxPerScan,
                            (index) => DropdownMenuItem<int>(
                              value: index + 1,
                              child: Text('${index + 1}개'),
                            ),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => selectedCount = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
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
                              Navigator.of(dialogContext).pop(
                                StampAddRequest(
                                  pin: value,
                                  count: selectedCount,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _stampCta,
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

/// 적립 실패. 다시 시도를 고르면 true.
Future<bool?> showStampAddFailedDialog(
  BuildContext context,
  String message,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFEBEF),
              ),
              child: const Icon(
                Icons.priority_high_rounded,
                size: 34,
                color: Color(0xFFE11D48),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '적립하지 못했어요',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Color(0xFF191F28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: Color(0xFF8B95A1),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4B5563),
                      side: const BorderSide(color: Color(0xFFE9EBF0)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('닫기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _stampCta,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('다시 시도'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showStampDailyLimitDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('적립 한도 안내'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      );
    },
  );
}

/// 적립 성공. 도장이 찍히듯 결과를 확정한다.
Future<void> showStampStampedDialog(
  BuildContext context, {
  required int added,
  required int current,
  required int total,
  required int remaining,
  required bool cycleReset,
  String? nextRewardText,
}) {
  final celebrate = cycleReset || (total > 0 && remaining == 0);
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
                celebrate
                    ? 'assets/images/stamp/stamp_reward.png'
                    : 'assets/images/stamp/stamp_filled.png',
                width: 96,
                height: 96,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              celebrate ? '리워드 도착!' : '스탬프 $added개 적립!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: Color(0xFF191F28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cycleReset
                  ? '리워드 쿠폰이 쿠폰함에 도착했어요\n스탬프판은 $current / $total 부터 다시 시작돼요'
                  : (celebrate
                      ? '리워드 쿠폰을 쿠폰함에서 확인하세요'
                      : nextRewardText != null
                          ? '$current / $total · $remaining개 더 모으면 $nextRewardText'
                          : '$current / $total 적립했어요'),
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
                  backgroundColor: _stampCta,
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
