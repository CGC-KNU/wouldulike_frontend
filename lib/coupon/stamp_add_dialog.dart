import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/coupon/pin_entry_widgets.dart';
import 'package:new1/services/app_config_service.dart';
import 'package:new1/services/remote_text_service.dart';

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

/// 매장 상세·지갑 스탬프 탭·QR 시트가 같이 쓰는 스탬프 적립 화면.
/// 쿠폰 사용 화면과 같은 디자인(티켓 카드 + 매장 PIN 칸 + 하단 숫자 패드)이다.
/// 직원이 PIN을 모두 누르면 개수와 함께 돌려주고, 닫으면 null.
Future<StampAddRequest?> showStampAddDialog(
  BuildContext context, {
  String? restaurantName,
}) {
  return Navigator.of(context, rootNavigator: true).push<StampAddRequest>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StampAddScreen(restaurantName: restaurantName),
    ),
  );
}

class StampAddScreen extends StatefulWidget {
  const StampAddScreen({super.key, this.restaurantName});

  final String? restaurantName;

  @override
  State<StampAddScreen> createState() => _StampAddScreenState();
}

class _StampAddScreenState extends State<StampAddScreen> {
  String _pin = '';
  int _count = 1;

  int get _pinLength => AppConfigService.pinLength;

  void _onDigit(String d) {
    if (_pin.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == _pinLength) {
      Navigator.of(context).pop(StampAddRequest(pin: _pin, count: _count));
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PinEntryColors.bg,
      appBar: AppBar(
        backgroundColor: PinEntryColors.bg,
        surfaceTintColor: PinEntryColors.bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: PinEntryColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '스탬프 적립',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: PinEntryColors.ink,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  _ticket(),
                  if (AppConfigService.stampMaxPerScan > 1) ...[
                    const SizedBox(height: 18),
                    _countSection(),
                  ],
                ],
              ),
            ),
          ),
          PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
        ],
      ),
    );
  }

  Widget _ticket() {
    final name = widget.restaurantName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: PinEntryColors.ink.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          if (name != null && name.isNotEmpty)
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PinEntryColors.sub,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '스탬프 $_count개 적립',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: -0.8,
              color: PinEntryColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '직원이 매장 PIN을 입력하면 적립돼요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: PinEntryColors.sub,
            ),
          ),
          const SizedBox(height: 16),
          const PinDashedDivider(),
          const SizedBox(height: 14),
          Text(
            RemoteText.string('coupon_use_show_staff'),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: PinEntryColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            RemoteText.string('coupon_use_pin_label'),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: PinEntryColors.sub,
            ),
          ),
          const SizedBox(height: 8),
          PinBoxes(length: _pinLength, pin: _pin),
          const SizedBox(height: 8),
          Text(
            RemoteText.string('coupon_use_pin_help'),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: PinEntryColors.sub,
            ),
          ),
        ],
      ),
    );
  }

  /// 쿠폰 사용 화면의 "몇 명이 함께 결제했나요?"와 같은 인원 버튼.
  Widget _countSection() {
    final max = AppConfigService.stampMaxPerScan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
      decoration: BoxDecoration(
        color: PinEntryColors.lav,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '몇 명이 함께 결제했나요?',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: PinEntryColors.sub,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(max, (i) {
              final n = i + 1;
              final selected = n == _count;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == max - 1 ? 4 : 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _count = n),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? PinEntryColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$n명',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.white : PinEntryColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '스탬프 $_count개가 적립돼요.',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: PinEntryColors.primary,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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

/// 하루 적립 한도 안내. 실패·성공 창과 같은 흰 카드 모양이다.
Future<void> showStampDailyLimitDialog(BuildContext context, String message) {
  return showDialog<void>(
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
                color: PinEntryColors.lav,
              ),
              child: const Icon(
                Icons.schedule_rounded,
                size: 34,
                color: PinEntryColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '적립 한도 안내',
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
