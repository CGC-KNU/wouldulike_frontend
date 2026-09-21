import 'package:flutter/material.dart';

/// 티켓 카드 껍데기.
///
/// 좌우 노치를 배경색 원으로 덮는 대신 카드 모양에서 실제로 파낸 뒤(even-odd),
/// 파낸 모양 그대로 그림자를 그린다. 배경이 무슨 색이든 원 자국이 남지 않는다.
///
/// 노치 높이는 기본이 세로 가운데. 절취선처럼 특정 위치에 맞춰야 하면 그 위젯에
/// [notchAnchorKey]를 달아 넘기면 그 위젯의 중심에 맞춘다.
class TicketShell extends StatefulWidget {
  const TicketShell({
    super.key,
    required this.child,
    this.notchAnchorKey,
    this.borderRadius = 18,
    this.notchRadius = 10,
    this.color = Colors.white,
    this.borderColor,
    this.borderWidth = 1.5,
    this.shadows = defaultShadows,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final GlobalKey? notchAnchorKey;
  final double borderRadius;
  final double notchRadius;
  final Color color;

  /// 흰 배경 위에 올릴 때처럼 윤곽이 필요하면 지정한다.
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow> shadows;
  final EdgeInsets margin;

  static const List<BoxShadow> defaultShadows = [
    BoxShadow(color: Color(0x0D191F28), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x14191F28), blurRadius: 16, offset: Offset(0, 6)),
  ];

  @override
  State<TicketShell> createState() => _TicketShellState();
}

class _TicketShellState extends State<TicketShell> {
  /// null이면 세로 가운데
  double? _notchY;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(TicketShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (widget.notchAnchorKey == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = widget.notchAnchorKey?.currentContext?.findRenderObject();
      final shell = context.findRenderObject();
      if (anchor is! RenderBox || shell is! RenderBox) return;
      if (!anchor.attached || !shell.attached) return;
      final y = anchor
          .localToGlobal(Offset(0, anchor.size.height / 2), ancestor: shell)
          .dy;
      if (_notchY != y) setState(() => _notchY = y);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.margin,
      child: CustomPaint(
        painter: _TicketPainter(
          notchY: _notchY,
          borderRadius: widget.borderRadius,
          notchRadius: widget.notchRadius,
          color: widget.color,
          borderColor: widget.borderColor,
          borderWidth: widget.borderWidth,
          shadows: widget.shadows,
        ),
        child: ClipPath(
          clipper: _TicketClipper(
            notchY: _notchY,
            borderRadius: widget.borderRadius,
            notchRadius: widget.notchRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 라운드 사각형에서 좌우 노치 원을 실제로 뺀(difference) 티켓 모양.
///
/// even-odd로 겹쳐 놓으면 카드 **밖** 반원이 도로 채워져 온전한 원처럼 보인다.
Path _ticketPath({
  required Size size,
  required double borderRadius,
  required double notchRadius,
  double? notchY,
}) {
  final y = notchY ?? size.height / 2;
  final card = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(borderRadius),
      ),
    );
  final notches = Path()
    ..addOval(Rect.fromCircle(center: Offset(0, y), radius: notchRadius))
    ..addOval(
      Rect.fromCircle(center: Offset(size.width, y), radius: notchRadius),
    );
  return Path.combine(PathOperation.difference, card, notches);
}

class _TicketPainter extends CustomPainter {
  _TicketPainter({
    required this.notchY,
    required this.borderRadius,
    required this.notchRadius,
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.shadows,
  });

  final double? notchY;
  final double borderRadius;
  final double notchRadius;
  final Color color;

  /// 흰 배경 위에 올릴 때처럼 윤곽이 필요하면 지정한다.
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _ticketPath(
      size: size,
      borderRadius: borderRadius,
      notchRadius: notchRadius,
      notchY: notchY,
    );

    // 그림자는 카드 실루엣 밖에만 — 노치 구멍 안으로 번지면 원 자국처럼 보인다.
    final silhouette = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(borderRadius),
        ),
      );
    final outside = Path.combine(
      PathOperation.difference,
      Path()
        ..addRect(Rect.fromLTRB(-60, -60, size.width + 60, size.height + 60)),
      silhouette,
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final shadow in shadows) {
      canvas.drawPath(path.shift(shadow.offset), shadow.toPaint());
    }
    canvas.restore();

    canvas.drawPath(path, Paint()..color = color);

    final border = borderColor;
    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
  }

  @override
  bool shouldRepaint(_TicketPainter old) =>
      old.notchY != notchY ||
      old.borderRadius != borderRadius ||
      old.notchRadius != notchRadius ||
      old.color != color ||
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth ||
      old.shadows != shadows;
}

class _TicketClipper extends CustomClipper<Path> {
  _TicketClipper({
    required this.notchY,
    required this.borderRadius,
    required this.notchRadius,
  });

  final double? notchY;
  final double borderRadius;
  final double notchRadius;

  @override
  Path getClip(Size size) => _ticketPath(
        size: size,
        borderRadius: borderRadius,
        notchRadius: notchRadius,
        notchY: notchY,
      );

  @override
  bool shouldReclip(_TicketClipper old) =>
      old.notchY != notchY ||
      old.borderRadius != borderRadius ||
      old.notchRadius != notchRadius;
}
