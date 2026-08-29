import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';

const _ink = Color(0xFF191F28);
const _sub = Color(0xFF4E5968);
const _faint = Color(0xFF8B95A1);
const _primary = Color(0xFF4F46E5);
const _tint = Color(0xFFEEF1FE);

/// 결과 팝업에서 사용자가 고른 다음 행동.
enum RaffleResultAction {
  /// 당첨 — 쿠폰함으로 이동
  openCoupons,

  /// 미당첨 — 상점으로 돌아가 다시 응모
  enterAgain,

  /// 그냥 닫기
  close,
}

/// 추첨 결과 팝업. 당첨이면 화면 전체에 폭죽을 띄운 뒤 축하 팝업을 보여준다.
/// 쿠폰 발급 자체는 서버가 처리하고, 여기서는 발급 사실만 안내한다.
Future<RaffleResultAction> showRaffleResultDialog(
  BuildContext context, {
  required bool won,
  required int prizeAmount,
  required String title,
  int? raffleId,
  String? drawRound,
}) async {
  AnalyticsLogger.logEvent(
    AnalyticsEvents.drawResultView,
    parameters: {
      if (raffleId != null) AnalyticsEvents.paramRaffleId: raffleId,
      if (drawRound != null) AnalyticsEvents.paramDrawRound: drawRound,
      AnalyticsEvents.paramIsWinner: won,
      AnalyticsEvents.paramPrizeType: won ? 'voucher' : 'none',
      AnalyticsEvents.paramFaceValue: prizeAmount,
    },
  );

  OverlayEntry? fireworks;
  if (won) {
    HapticFeedback.heavyImpact();
    fireworks = OverlayEntry(
      builder: (_) => const IgnorePointer(child: _FireworksLayer()),
    );
    Overlay.of(context).insert(fireworks);
  }

  final action = await showDialog<RaffleResultAction>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _ResultDialog(
      won: won,
      prizeAmount: prizeAmount,
      title: title,
    ),
  );

  fireworks?.remove();
  return action ?? RaffleResultAction.close;
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.won,
    required this.prizeAmount,
    required this.title,
  });

  final bool won;
  final int prizeAmount;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PopIn(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: won ? _tint : const Color(0xFFF1F2F7),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  won
                      ? Icons.emoji_events_rounded
                      : Icons.sentiment_dissatisfied_rounded,
                  size: 36,
                  color: won ? _primary : _faint,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              won ? '당첨됐어요!' : '아쉽게 미당첨이에요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
                color: _ink,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              won
                  ? '${_comma(prizeAmount)}원 $title이\n쿠폰함으로 발급됐어요.'
                  : '이번엔 인연이 아니었어요.\n다음 추첨에 또 응모해 주세요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                height: 1.5,
                color: _sub,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  won
                      ? RaffleResultAction.openCoupons
                      : RaffleResultAction.enterAgain,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                child: Text(won ? '내 지갑에서 쿠폰 보기' : '다른 식사권 응모하기'),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(RaffleResultAction.close),
              child: const Text(
                '닫기',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _faint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 아이콘이 통통 튀며 등장한다.
class _PopIn extends StatefulWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
      child: widget.child,
    );
  }
}

/// 당첨 순간 화면 전체에 터지는 폭죽. 세 발이 시간차로 터진다.
class _FireworksLayer extends StatefulWidget {
  const _FireworksLayer();

  @override
  State<_FireworksLayer> createState() => _FireworksLayerState();
}

class _FireworksLayerState extends State<_FireworksLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _FireworksPainter(_controller.value),
      ),
    );
  }
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.progress);

  final double progress;

  /// (중심 x비율, 중심 y비율, 터지는 시점, 색상 시드)
  static const _bursts = [
    [0.5, 0.32, 0.0],
    [0.24, 0.46, 0.22],
    [0.76, 0.40, 0.40],
    [0.42, 0.60, 0.60],
  ];

  static const _colors = [
    _primary,
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF22C55E),
    Color(0xFF38BDF8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(11);
    for (var b = 0; b < _bursts.length; b++) {
      final burst = _bursts[b];
      final start = burst[2];
      // 각 폭죽은 0.55 구간 동안 퍼졌다가 사라진다.
      final local = ((progress - start) / 0.55).clamp(0.0, 1.0);
      final center = Offset(size.width * burst[0], size.height * burst[1]);
      const count = 22;
      for (var i = 0; i < count; i++) {
        final angle = (i / count) * 2 * pi + random.nextDouble() * 0.2;
        final distance = (60 + random.nextDouble() * 90) *
            Curves.easeOutCubic.transform(local);
        if (local <= 0 || local >= 1) continue;
        final position = Offset(
          center.dx + cos(angle) * distance,
          center.dy + sin(angle) * distance + 70 * local * local,
        );
        canvas.drawCircle(
          position,
          3.2 * (1 - local * 0.5),
          Paint()
            ..color = _colors[(i + b) % _colors.length]
                .withValues(alpha: (1 - local).clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

String _comma(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
