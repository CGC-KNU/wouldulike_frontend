import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../onboarding_style.dart';

/// 온보딩 쿠폰 지급 연출용 룰렛 휠.
///
/// [rotation]은 라디안 단위 회전값 — 부모가 AnimationController로 돌린다.
/// 세그먼트 0번의 중앙이 rotation == 0일 때 12시(포인터) 방향에 온다.
class RouletteWheel extends StatelessWidget {
  const RouletteWheel({
    super.key,
    this.labels = prizeLabels,
    required this.rotation,
    this.size = 264,
  });

  final List<String> labels;
  final double rotation;
  final double size;

  static const String loseLabel = '꽝';
  static const String winLabel = '쿠폰';

  /// 룰렛 칸. 포인터는 0번에 멈추므로(`rotationForIndex(0, ...)` = 0)
  /// 당첨은 항상 쿠폰이다.
  static const List<String> prizeLabels = [
    winLabel,
    '마일리지',
    winLabel,
    loseLabel,
    winLabel,
    '마일리지',
    winLabel,
    loseLabel,
    winLabel,
    '마일리지',
    winLabel,
    loseLabel,
  ];

  /// [index] 세그먼트 중앙이 포인터(12시)에 오도록 하는 회전값.
  static double rotationForIndex(int index, int segmentCount) {
    final segmentAngle = 2 * math.pi / segmentCount;
    return -segmentAngle * index;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 50,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 50,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: OnboardingStyle.primary.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Transform.rotate(
                angle: rotation,
                child: CustomPaint(
                  painter: _WheelPainter(labels: labels),
                ),
              ),
            ),
          ),
          // 중앙 허브
          Positioned(
            top: 50 + size / 2 - 31,
            child: Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OnboardingStyle.primary,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.restaurant_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          // 상단 포인터 — 핀 끝이 링에 닿도록 아래로 내려 겹친다.
          // (휠 상단 y=50, 링 바깥면 y≈52 → 핀 박스 높이를 늘려 끝을 링까지 밀어넣는다)
          const SizedBox(
            height: 58,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Icon(Icons.location_on, size: 46, color: Colors.white),
                Icon(Icons.location_on,
                    size: 36, color: OnboardingStyle.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.labels});

  final List<String> labels;

  static const Color _lineColor = Color(0xFFDDE1FB);

  /// 당첨 칸(쿠폰)만 연보라로 눈에 띄게, 꽝은 빈 칸처럼 흰색.
  static const Color _winColor = Color(0xFFC7D2FE);

  static Color _segmentColor(String label) => switch (label) {
        RouletteWheel.winLabel => _winColor,
        RouletteWheel.loseLabel => Colors.white,
        _ => OnboardingStyle.accentSoft,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    final count = labels.length;
    if (count == 0) return;
    final segmentAngle = 2 * math.pi / count;

    // 칸 배경 — 꽝은 흰색, 상품 칸은 옅은 인디고
    for (var i = 0; i < count; i++) {
      // 세그먼트 i의 중앙이 -π/2(12시) 기준이 되도록 시작각을 잡는다.
      final start = -math.pi / 2 - segmentAngle / 2 + segmentAngle * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        segmentAngle,
        true,
        Paint()..color = _segmentColor(labels[i]),
      );
    }

    // 칸 경계선
    final linePaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 - segmentAngle / 2 + segmentAngle * i;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        linePaint,
      );
    }

    // 라벨 — 허브와 테두리 사이 공간의 중앙에, 중심 방향으로 눕혀 쓴다.
    const hubRadius = 38.0;
    final outerEdge = radius - 14; // 링 안쪽 여백
    for (var i = 0; i < count; i++) {
      final midAngle = -math.pi / 2 + segmentAngle * i;
      final label = labels[i];
      final isWin = label == RouletteWheel.winLabel;
      final isLose = label == RouletteWheel.loseLabel;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: isWin ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: -0.7,
            color: isWin
                ? OnboardingStyle.primary
                : isLose
                    ? const Color(0xFF9AA3B2)
                    : OnboardingStyle.primary,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: outerEdge - hubRadius);

      // +π 회전이면 회전축 x가 중심 방향을 향한다 → 테두리부터 안쪽으로 읽힌다.
      // 텍스트 중심이 (허브~테두리) 중앙 반지름에 오도록 시작점을 잡는다.
      final midRadius = (hubRadius + outerEdge) / 2;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(midAngle + math.pi);
      textPainter.paint(
        canvas,
        Offset(-(midRadius + textPainter.width / 2), -textPainter.height / 2),
      );
      canvas.restore();
    }

    // 굵은 테두리 링
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = OnboardingStyle.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.labels != labels;
}
