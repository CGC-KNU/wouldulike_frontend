import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 우디의 포즈. 컷마다 다른 포즈로 등장한다.
enum WoodyPose {
  /// 손 흔들며 인사
  greeting,

  /// 쿠폰(선물)을 두 손으로 안고 있음
  gift,

  /// 아래를 가리키며 "골라 줄래?"
  pick,
}

/// 마스코트 "우디" — 코드로 그린 캐릭터.
///
/// 이미지 에셋 없이 [CustomPaint]로 그려서 색/모션을 앱 테마와 함께 관리한다.
/// 잔잔한 상하 바운스가 기본이고, [WoodyPose.greeting]에서는 손을 흔든다.
class WoodyMascot extends StatefulWidget {
  const WoodyMascot({super.key, required this.pose, this.size = 168});

  final WoodyPose pose;
  final double size;

  @override
  State<WoodyMascot> createState() => _WoodyMascotState();
}

class _WoodyMascotState extends State<WoodyMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => CustomPaint(
          painter: _WoodyPainter(pose: widget.pose, t: _controller.value),
          size: Size.square(widget.size),
        ),
      ),
    );
  }
}

class _WoodyPainter extends CustomPainter {
  _WoodyPainter({required this.pose, required this.t});

  final WoodyPose pose;
  final double t;

  static const Color _primary = Color(0xFF312E81);
  static const Color _bodyFill = Color(0xFFE0E7FF);
  static const Color _soft = Color(0xFFC7D2FE);
  static const Color _accent = Color(0xFF6366F1);
  static const Color _cheek = Color(0xFFA5B4FC);

  Paint get _outline => Paint()
    ..color = _primary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _outlineThin => Paint()
    ..color = _primary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _armPaint => Paint()
    ..color = _primary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 9
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200);

    final wave = math.sin(t * 2 * math.pi); // -1..1
    final bob = math.sin(t * 2 * math.pi) * 4;

    // 바닥 그림자 (떠오르면 살짝 작아짐)
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(100, 184),
        width: 82 + bob * 0.8,
        height: 12,
      ),
      Paint()..color = const Color(0x14312E81),
    );

    canvas.save();
    canvas.translate(0, bob);

    switch (pose) {
      case WoodyPose.greeting:
        _drawRestArm(canvas, const Offset(52, 122), const Offset(40, 140),
            const Offset(38, 143));
        _drawBody(canvas);
        _drawSprout(canvas);
        _drawFace(canvas, happy: false);
        _drawWavingArm(canvas, wave);
        break;
      case WoodyPose.gift:
        _drawBody(canvas);
        _drawSprout(canvas);
        _drawFace(canvas, happy: true);
        _drawGift(canvas);
        _drawCoins(canvas);
        break;
      case WoodyPose.pick:
        _drawRestArm(canvas, const Offset(52, 122), const Offset(42, 140),
            const Offset(40, 143));
        _drawBody(canvas);
        _drawSprout(canvas);
        _drawFace(canvas, happy: false, wink: true);
        _drawPointArm(canvas);
        _drawChoiceSparkle(canvas);
        break;
    }

    canvas.restore();
  }

  void _drawBody(Canvas canvas) {
    final rect = Rect.fromCenter(
      center: const Offset(100, 112),
      width: 112,
      height: 108,
    );
    canvas.drawOval(rect, Paint()..color = _bodyFill);
    canvas.drawOval(rect, _outline);
  }

  void _drawSprout(Canvas canvas) {
    // 머리 위 새싹 — 친근함 포인트
    canvas.drawLine(const Offset(100, 60), const Offset(100, 48), _outlineThin);
    final leaf = Path()
      ..moveTo(100, 51)
      ..quadraticBezierTo(110, 44, 114, 52)
      ..quadraticBezierTo(106, 56, 100, 51)
      ..close();
    canvas.drawPath(leaf, Paint()..color = _accent);
  }

  /// 미튼(paw) 손 — 팔 끝에 붙는 통통한 손
  void _mitten(Canvas canvas, Offset o, {double r = 9}) {
    final rect = Rect.fromCenter(center: o, width: r * 2.3, height: r * 2);
    canvas.drawOval(rect, Paint()..color = _soft);
    canvas.drawOval(rect, _outlineThin);
  }

  void _drawFace(Canvas canvas, {required bool happy, bool wink = false}) {
    final cheekPaint = Paint()..color = _cheek.withOpacity(0.55);
    canvas.drawCircle(const Offset(72, 120), 8, cheekPaint);
    canvas.drawCircle(const Offset(128, 120), 8, cheekPaint);

    final eyePaint = Paint()..color = _primary;
    if (happy) {
      final l = Path()
        ..moveTo(72, 108)
        ..quadraticBezierTo(80, 99, 88, 108);
      final r = Path()
        ..moveTo(112, 108)
        ..quadraticBezierTo(120, 99, 128, 108);
      canvas.drawPath(l, _outlineThin);
      canvas.drawPath(r, _outlineThin);
    } else {
      canvas.drawCircle(const Offset(81, 106), 6, eyePaint);
      canvas.drawCircle(const Offset(81, 103), 2, Paint()..color = Colors.white);
      if (wink) {
        final r = Path()
          ..moveTo(111, 106)
          ..quadraticBezierTo(119, 100, 127, 106);
        canvas.drawPath(r, _outlineThin);
      } else {
        canvas.drawCircle(const Offset(119, 106), 6, eyePaint);
        canvas.drawCircle(
            const Offset(119, 103), 2, Paint()..color = Colors.white);
      }
    }

    if (happy) {
      final mouth = Path()
        ..moveTo(89, 120)
        ..quadraticBezierTo(100, 133, 111, 120)
        ..close();
      canvas.drawPath(mouth, Paint()..color = _primary);
    } else {
      final smile = Path()
        ..moveTo(90, 121)
        ..quadraticBezierTo(100, 129, 110, 121);
      canvas.drawPath(smile, _outlineThin..strokeWidth = 3.5);
    }
  }

  /// 아래로 편히 내린 짧은 팔 + 손
  void _drawRestArm(Canvas canvas, Offset shoulder, Offset elbow, Offset hand) {
    final arm = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..quadraticBezierTo(
          elbow.dx - 4, (shoulder.dy + hand.dy) / 2, elbow.dx, elbow.dy);
    canvas.drawPath(arm, _armPaint);
    _mitten(canvas, hand);
  }

  // ---------- greeting ----------

  void _drawWavingArm(Canvas canvas, double wave) {
    // 오른팔을 머리 옆으로 들어 손 흔들기 (어깨 기준 회전)
    canvas.save();
    canvas.translate(148, 118);
    canvas.rotate(wave * 0.14);
    final arm = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(14, -18, 18, -36);
    canvas.drawPath(arm, _armPaint);
    _mitten(canvas, const Offset(20, -40), r: 10);
    if (wave > 0.2) {
      final motion = Paint()
        ..color = _accent.withOpacity((wave - 0.2).clamp(0, 1) * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCircle(center: const Offset(20, -40), radius: 15),
          -1.2, 1.0, false, motion);
    }
    canvas.restore();
  }

  // ---------- gift ----------

  void _drawGift(Canvas canvas) {
    // 두 팔이 앞으로 모여 티켓을 안음
    final left = Path()
      ..moveTo(56, 124)
      ..quadraticBezierTo(66, 144, 82, 149);
    final right = Path()
      ..moveTo(144, 124)
      ..quadraticBezierTo(134, 144, 118, 149);
    canvas.drawPath(left, _armPaint);
    canvas.drawPath(right, _armPaint);

    // 쿠폰 티켓
    final ticket = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(100, 150), width: 58, height: 36),
      const Radius.circular(9),
    );
    canvas.drawRRect(ticket, Paint()..color = Colors.white);
    canvas.drawRRect(ticket, _outlineThin);

    final dash = Paint()
      ..color = _soft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    double y = 137;
    while (y < 163) {
      canvas.drawLine(Offset(115, y), Offset(115, y + 3.5), dash);
      y += 6.5;
    }
    _drawStar(canvas, const Offset(92, 150), 8, _accent);

    _mitten(canvas, const Offset(82, 150));
    _mitten(canvas, const Offset(118, 150));
  }

  void _drawCoins(Canvas canvas) {
    void coin(double baseX, double baseY, double phase, double r) {
      final drift = math.sin((t + phase) * 2 * math.pi) * 3.5;
      final center = Offset(baseX, baseY + drift);
      canvas.drawCircle(center, r, Paint()..color = _soft);
      canvas.drawCircle(center, r, _outlineThin..strokeWidth = 2.5);
    }

    coin(46, 76, 0.0, 8);
    coin(158, 68, 0.35, 6.5);
    coin(154, 126, 0.7, 5.5);
    _drawSparkle(canvas, const Offset(56, 118), 5,
        _accent.withOpacity(0.4 + 0.5 * math.sin(t * 2 * math.pi).abs()));
  }

  // ---------- pick ----------

  void _drawPointArm(Canvas canvas) {
    // 오른팔이 아래를 가리킴 (짧게)
    final arm = Path()
      ..moveTo(146, 124)
      ..quadraticBezierTo(158, 140, 152, 158);
    canvas.drawPath(arm, _armPaint);
    _mitten(canvas, const Offset(152, 160));
  }

  void _drawChoiceSparkle(Canvas canvas) {
    final pulse = (math.sin(t * 2 * math.pi) + 1) / 2; // 0..1
    final y = 172 + pulse * 4;
    final chevron = Paint()
      ..color = _accent.withOpacity(0.35 + 0.5 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(144, y)
      ..lineTo(152, y + 7)
      ..lineTo(160, y);
    canvas.drawPath(path, chevron);
  }

  // ---------- helpers ----------

  void _drawStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outer = -math.pi / 2 + i * 2 * math.pi / 5;
      final inner = outer + math.pi / 5;
      final po = Offset(c.dx + math.cos(outer) * r, c.dy + math.sin(outer) * r);
      final pin = Offset(
          c.dx + math.cos(inner) * r * 0.45, c.dy + math.sin(inner) * r * 0.45);
      if (i == 0) {
        path.moveTo(po.dx, po.dy);
      } else {
        path.lineTo(po.dx, po.dy);
      }
      path.lineTo(pin.dx, pin.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
  }

  @override
  bool shouldRepaint(_WoodyPainter old) => old.t != t || old.pose != pose;
}
