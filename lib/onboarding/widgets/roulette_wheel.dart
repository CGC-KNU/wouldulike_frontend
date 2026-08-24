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
    required this.labels,
    required this.rotation,
    this.size = 264,
  });

  final List<String> labels;
  final double rotation;
  final double size;

  /// [index] 세그먼트 중앙이 포인터(12시)에 오도록 하는 회전값.
  static double rotationForIndex(int index, int segmentCount) {
    final segmentAngle = 2 * math.pi / segmentCount;
    return -segmentAngle * index;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 16,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 16,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: OnboardingStyle.primary.withOpacity(0.18),
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
            top: 16 + size / 2 - 27,
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Text('🎁', style: TextStyle(fontSize: 24)),
            ),
          ),
          // 상단 포인터
          CustomPaint(
            size: const Size(26, 30),
            painter: _PointerPainter(),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.labels});

  final List<String> labels;

  static const List<Color> _segmentColors = [
    Color(0xFF312E81),
    Color(0xFFE0E7FF),
    Color(0xFF6366F1),
    Color(0xFFC7D2FE),
    Color(0xFF4338CA),
    Color(0xFFA5B4FC),
    Color(0xFF818CF8),
    Color(0xFFEEF4FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final count = labels.length;
    if (count == 0) return;
    final segmentAngle = 2 * math.pi / count;

    for (var i = 0; i < count; i++) {
      // 세그먼트 i의 중앙이 -π/2(12시) 기준이 되도록 시작각을 잡는다.
      final start = -math.pi / 2 - segmentAngle / 2 + segmentAngle * i;
      final paint = Paint()
        ..color = _segmentColors[i % _segmentColors.length]
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        segmentAngle,
        true,
        paint,
      );
    }

    // 세그먼트 경계선
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 - segmentAngle / 2 + segmentAngle * i;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        linePaint,
      );
    }

    // 라벨
    for (var i = 0; i < count; i++) {
      final midAngle = -math.pi / 2 + segmentAngle * i;
      final color = _segmentColors[i % _segmentColors.length];
      final isDark = color.computeLuminance() < 0.4;
      final label = labels[i].length > 5
          ? '${labels[i].substring(0, 5)}…'
          : labels[i];

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : OnboardingStyle.primary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(midAngle + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -radius + 14),
      );
      canvas.restore();
    }

    // 테두리
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.labels != labels;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black38, 3, false);
    canvas.drawPath(path, Paint()..color = OnboardingStyle.danger);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) => false;
}
