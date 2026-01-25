import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

class LiquidGlassTab {
  const LiquidGlassTab({
    required this.label,
    required this.assetPath,
  });

  final String label;
  final String assetPath;
}

class LiquidGlassBottomBar extends StatefulWidget {
  const LiquidGlassBottomBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
    required this.iconBuilder,
    required this.selectedColor,
    required this.unselectedColor,
    required this.selectedLabelStyle,
    required this.unselectedLabelStyle,
    this.barHeight = 72,
    this.maxWidth = 520,
    this.widthFactor = 0.9,
    this.bottomInset = 18,
    this.blurSigma = 30,
  });

  final List<LiquidGlassTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Widget Function(String assetPath, Color color) iconBuilder;
  final Color selectedColor;
  final Color unselectedColor;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final double barHeight;
  final double maxWidth;
  final double widthFactor;
  final double bottomInset;
  final double blurSigma;

  @override
  State<LiquidGlassBottomBar> createState() => _LiquidGlassBottomBarState();
}

class _LiquidGlassBottomBarState extends State<LiquidGlassBottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bannerScale;
  int _fromIndex = 0;
  int _toIndex = 0;
  bool _isDragging = false;
  double _dragT = 0;
  double _dragPhase = 0;
  double _dragWobble = 0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex;
    _toIndex = widget.selectedIndex;
    _dragT = widget.selectedIndex.toDouble();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _bannerScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.03)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 45,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(LiquidGlassBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _toIndex) {
      _fromIndex = _toIndex;
      _toIndex = widget.selectedIndex;
      _dragT = widget.selectedIndex.toDouble();
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.barHeight / 2;
    final fillColor = Colors.white.withOpacity(0.62);
    const glassBoost = ColorFilter.matrix(<double>[
      1.05,
      0,
      0,
      0,
      0,
      0,
      1.05,
      0,
      0,
      0,
      0,
      0,
      1.05,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);

    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomInset),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: FractionallySizedBox(
                widthFactor: widget.widthFactor,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final scale =
                        _controller.isDismissed ? 1.0 : _bannerScale.value;
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: SizedBox(
                    height: widget.barHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                          BoxShadow(
                            offset: const Offset(0, 16),
                            blurRadius: 36,
                            color: Colors.black.withOpacity(0.14),
                          ),
                          BoxShadow(
                            offset: const Offset(0, 4),
                            blurRadius: 12,
                            color: Colors.black.withOpacity(0.08),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColorFiltered(
                              colorFilter: glassBoost,
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: widget.blurSigma,
                                  sigmaY: widget.blurSigma,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                            ColorFiltered(
                              colorFilter: glassBoost,
                              child: Container(color: fillColor),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(radius),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withOpacity(0.14),
                                    Colors.white.withOpacity(0.03),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(radius),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.38),
                                  width: 1,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 14,
                              right: 14,
                              child: Container(
                                height: 1,
                                color: Colors.white.withOpacity(0.36),
                              ),
                            ),
                            const Positioned.fill(
                              child: _NoiseOverlay(opacity: 0.028),
                            ),
                            Material(
                              type: MaterialType.transparency,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final itemWidth =
                                      constraints.maxWidth / widget.tabs.length;
                                  final blobWidth = itemWidth - 6;
                                  final blobHeight = widget.barHeight - 8;
                                  final centerY = widget.barHeight / 2;
                                  final dragIndex =
                                      _dragT.round().clamp(0, widget.tabs.length - 1);

                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragStart: (_) {
                                      _isDragging = true;
                                      _controller.stop();
                                    },
                                    onHorizontalDragUpdate: (details) {
                                      final t = details.localPosition.dx /
                                              itemWidth -
                                          0.5;
                                      setState(() {
                                        _dragT = t.clamp(
                                          0.0,
                                          widget.tabs.length - 1.0,
                                        );
                                        _dragPhase = (_dragPhase +
                                                details.delta.dx.abs() * 0.12) %
                                            (pi * 2);
                                        _dragWobble = (details.delta.dx.abs() /
                                                itemWidth)
                                            .clamp(0.0, 1.0);
                                      });
                                    },
                                    onHorizontalDragEnd: (_) {
                                      final target = dragIndex;
                                      _isDragging = false;
                                      _dragWobble = 0;
                                      if (target != widget.selectedIndex) {
                                        _fromIndex = target;
                                        _toIndex = target;
                                        _controller.value = 1.0;
                                        widget.onTap(target);
                                      } else {
                                        _controller.forward(from: 0);
                                      }
                                    },
                                    child: Stack(
                                      children: [
                                        AnimatedBuilder(
                                          animation: _controller,
                                          builder: (context, child) {
                                            final travelCurve =
                                                Curves.easeInOutCubic.transform(
                                              _controller.value,
                                            );
                                            final morphCurve =
                                                Curves.easeOutCubic.transform(
                                              min(1, _controller.value * 1.25),
                                            );
                                            final startX =
                                                itemWidth * _fromIndex +
                                                    itemWidth / 2;
                                            final endX =
                                                itemWidth * _toIndex + itemWidth / 2;
                                            final dragX =
                                                itemWidth * (_dragT + 0.5);
                                            final blobX =
                                                _isDragging ? dragX : startX;
                                            final blobEndX =
                                                _isDragging ? dragX : endX;
                                            final travelT =
                                                _isDragging ? 0.0 : travelCurve;
                                            final morphT =
                                                _isDragging ? 0.0 : morphCurve;
                                            final timeT = _isDragging
                                                ? 0.0
                                                : _controller.value;
                                            final wobblePhase = _isDragging
                                                ? _dragPhase
                                                : timeT * pi * 2.4;
                                            final wobbleAmp = _isDragging
                                                ? 0.08 * _dragWobble
                                                : 0.06 * exp(-3 * timeT);
                                            final glowStrength =
                                                _isDragging ? 1.0 : 0.6;

                                            final blobRect = _blobRect(
                                              centerX: lerpDouble(
                                                    blobX,
                                                    blobEndX,
                                                    travelT,
                                                  ) ??
                                                  blobEndX,
                                              centerY: centerY,
                                              baseWidth: blobWidth,
                                              baseHeight: blobHeight,
                                              morphT: morphT,
                                              wobblePhase: wobblePhase,
                                              wobbleAmp: wobbleAmp,
                                            );

                                            return Stack(
                                              children: [
                                                CustomPaint(
                                                  painter: _LiquidBlobPainter(
                                                    startX: blobX,
                                                    endX: blobEndX,
                                                    centerY: centerY,
                                                    baseWidth: blobWidth,
                                                    baseHeight: blobHeight,
                                                    travelT: travelT,
                                                    morphT: morphT,
                                                    wobblePhase: wobblePhase,
                                                    wobbleAmp: wobbleAmp,
                                                    drawFill: true,
                                                    drawRim: false,
                                                  ),
                                                ),
                                                ClipPath(
                                                  clipper: _LensClipper(
                                                    rect: blobRect,
                                                  ),
                                                  child: _TabRow(
                                                    tabs: widget.tabs,
                                                    iconBuilder: widget.iconBuilder,
                                                    selectedColor:
                                                        widget.selectedColor,
                                                    unselectedColor:
                                                        widget.unselectedColor,
                                                    selectedLabelStyle:
                                                        widget.selectedLabelStyle,
                                                    unselectedLabelStyle:
                                                        widget.unselectedLabelStyle,
                                                    selectedIndex: -1,
                                                    barHeight: widget.barHeight,
                                                    onTap: (_) {},
                                                    forceSelected: true,
                                                  ),
                                                ),
                                                CustomPaint(
                                                  painter: _LiquidBlobPainter(
                                                    startX: blobX,
                                                    endX: blobEndX,
                                                    centerY: centerY,
                                                    baseWidth: blobWidth,
                                                    baseHeight: blobHeight,
                                                    travelT: travelT,
                                                    morphT: morphT,
                                                    wobblePhase: wobblePhase,
                                                    wobbleAmp: wobbleAmp,
                                                    drawFill: false,
                                                    drawRim: true,
                                                    glowStrength: glowStrength,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        Row(
                                          children: List.generate(
                                              widget.tabs.length, (index) {
                                            final tab = widget.tabs[index];
                                            final isSelected = _isDragging
                                                ? index == dragIndex
                                                : index == widget.selectedIndex;
                                            final iconColor = isSelected
                                                ? widget.selectedColor
                                                : widget.unselectedColor
                                                    .withOpacity(1.0);
                                            final labelStyle = isSelected
                                                ? widget.selectedLabelStyle
                                                    .copyWith(
                                                    color: widget.selectedColor,
                                                  )
                                                : widget.unselectedLabelStyle
                                                    .copyWith(
                                                    color: widget.unselectedColor,
                                                  );

                                            return Expanded(
                                              child: InkWell(
                                                onTap: () => widget.onTap(index),
                                                borderRadius:
                                                    BorderRadius.circular(radius),
                                                splashColor: Colors.white
                                                    .withOpacity(0.12),
                                                highlightColor:
                                                    Colors.transparent,
                                                child: SizedBox(
                                                  height: widget.barHeight,
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.center,
                                                    children: [
                                                      widget.iconBuilder(
                                                        tab.assetPath,
                                                        iconColor,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        tab.label,
                                                        style: labelStyle,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidBlobPainter extends CustomPainter {
  _LiquidBlobPainter({
    required this.startX,
    required this.endX,
    required this.centerY,
    required this.baseWidth,
    required this.baseHeight,
    required this.travelT,
    required this.morphT,
    required this.wobblePhase,
    required this.wobbleAmp,
    required this.drawFill,
    required this.drawRim,
    this.glowStrength = 0.6,
  });

  final double startX;
  final double endX;
  final double centerY;
  final double baseWidth;
  final double baseHeight;
  final double travelT;
  final double morphT;
  final double wobblePhase;
  final double wobbleAmp;
  final bool drawFill;
  final bool drawRim;
  final double glowStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = sin(pi * morphT);
    final wobble = sin(wobblePhase) * wobbleAmp;
    final scaleX = 1.12 - 0.28 * phase + 0.6 * wobble;
    final scaleY = 0.86 + 0.34 * phase - 0.5 * wobble;
    final stretch = (endX - startX).abs();
    final connectorBoost = stretch * 0.4 * (phase);
    final currentX = lerpDouble(startX, endX, travelT) ?? endX;
    final wobbleY = wobble * 2.2;

    if (drawFill) {
      _drawBlob(
        canvas,
        centerX: currentX,
        centerY: centerY + wobbleY,
        width: baseWidth * scaleX,
        height: baseHeight * scaleY,
        intensity: 0.1,
      );

      if (stretch > 0.5) {
        _drawBlob(
          canvas,
          centerX: startX,
          centerY: centerY + wobbleY * (1 - travelT),
          width: baseWidth * 0.92,
          height: baseHeight * 0.82,
          intensity: 0.06 * (1 - travelT),
        );
        _drawBlob(
          canvas,
          centerX: endX,
          centerY: centerY + wobbleY * travelT,
          width: baseWidth * 0.92,
          height: baseHeight * 0.82,
          intensity: 0.06 * travelT,
        );
        _drawBlob(
          canvas,
          centerX: (startX + endX) / 2,
          centerY: centerY + wobbleY * 0.4,
          width: baseWidth + connectorBoost,
          height: baseHeight * (0.78 + 0.18 * phase),
          intensity: 0.05 * phase,
        );
      }
    }

    if (drawRim) {
      final rect = _blobRect(
        centerX: currentX,
        centerY: centerY + wobbleY,
        baseWidth: baseWidth,
        baseHeight: baseHeight,
        morphT: morphT,
        wobblePhase: wobblePhase,
        wobbleAmp: wobbleAmp,
      );
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withOpacity(0.55);
      canvas.drawOval(rect.deflate(1.2), rim);

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withOpacity(0.18 * glowStrength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawOval(rect.deflate(1), glow);
    }
  }

  void _drawBlob(
    Canvas canvas, {
    required double centerX,
    required double centerY,
    required double width,
    required double height,
    required double intensity,
  }) {
    if (intensity <= 0) return;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: width,
      height: height,
    );
    final shader = RadialGradient(
      center: const Alignment(0.0, -0.15),
      radius: 0.9,
      colors: [
        Colors.black.withOpacity(intensity),
        Colors.black.withOpacity(intensity * 0.7),
        Colors.black.withOpacity(0.0),
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(rect);

    final paint = Paint()
      ..shader = shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(rect, paint);

    final highlightRect = Rect.fromCenter(
      center: Offset(centerX - width * 0.14, centerY - height * 0.18),
      width: width * 0.45,
      height: height * 0.35,
    );
    final highlightShader = RadialGradient(
      center: const Alignment(-0.2, -0.3),
      radius: 0.9,
      colors: [
        Colors.white.withOpacity(intensity * 0.18),
        Colors.white.withOpacity(0.0),
      ],
      stops: const [0.0, 1.0],
    ).createShader(highlightRect);
    final highlightPaint = Paint()..shader = highlightShader;
    canvas.drawOval(highlightRect, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidBlobPainter oldDelegate) {
    return startX != oldDelegate.startX ||
        endX != oldDelegate.endX ||
        travelT != oldDelegate.travelT ||
        morphT != oldDelegate.morphT ||
        wobblePhase != oldDelegate.wobblePhase ||
        wobbleAmp != oldDelegate.wobbleAmp ||
        drawFill != oldDelegate.drawFill ||
        drawRim != oldDelegate.drawRim ||
        glowStrength != oldDelegate.glowStrength ||
        baseWidth != oldDelegate.baseWidth ||
        baseHeight != oldDelegate.baseHeight;
  }
}

Rect _blobRect({
  required double centerX,
  required double centerY,
  required double baseWidth,
  required double baseHeight,
  required double morphT,
  required double wobblePhase,
  required double wobbleAmp,
}) {
  final phase = sin(pi * morphT);
  final wobble = sin(wobblePhase) * wobbleAmp;
  final scaleX = 1.12 - 0.28 * phase + 0.6 * wobble;
  final scaleY = 0.86 + 0.34 * phase - 0.5 * wobble;
  return Rect.fromCenter(
    center: Offset(centerX, centerY + wobble * 2.2),
    width: baseWidth * scaleX,
    height: baseHeight * scaleY,
  );
}

class _LensClipper extends CustomClipper<Path> {
  _LensClipper({required this.rect});

  final Rect rect;

  @override
  Path getClip(Size size) {
    return Path()..addOval(rect);
  }

  @override
  bool shouldReclip(covariant _LensClipper oldClipper) {
    return rect != oldClipper.rect;
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tabs,
    required this.iconBuilder,
    required this.selectedColor,
    required this.unselectedColor,
    required this.selectedLabelStyle,
    required this.unselectedLabelStyle,
    required this.selectedIndex,
    required this.barHeight,
    required this.onTap,
    this.forceSelected = false,
  });

  final List<LiquidGlassTab> tabs;
  final Widget Function(String assetPath, Color color) iconBuilder;
  final Color selectedColor;
  final Color unselectedColor;
  final TextStyle selectedLabelStyle;
  final TextStyle unselectedLabelStyle;
  final int selectedIndex;
  final double barHeight;
  final ValueChanged<int> onTap;
  final bool forceSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(tabs.length, (index) {
        final tab = tabs[index];
        final isSelected = forceSelected || index == selectedIndex;
        final iconColor = isSelected ? selectedColor : unselectedColor;
        final labelStyle = isSelected
            ? selectedLabelStyle.copyWith(color: selectedColor)
            : unselectedLabelStyle.copyWith(color: unselectedColor);

        return Expanded(
          child: InkWell(
            onTap: forceSelected ? null : () => onTap(index),
            borderRadius: BorderRadius.circular(barHeight / 2),
            splashColor: Colors.white.withOpacity(0.12),
            highlightColor: Colors.transparent,
            child: SizedBox(
              height: barHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconBuilder(tab.assetPath, iconColor),
                  const SizedBox(height: 4),
                  Text(
                    tab.label,
                    style: labelStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _NoiseOverlay extends StatefulWidget {
  const _NoiseOverlay({required this.opacity});

  final double opacity;

  @override
  State<_NoiseOverlay> createState() => _NoiseOverlayState();
}

class _NoiseOverlayState extends State<_NoiseOverlay> {
  static Future<Uint8List>? _noiseFuture;
  Uint8List? _noiseBytes;

  @override
  void initState() {
    super.initState();
    _noiseFuture ??= _generateNoisePng();
    _noiseFuture!.then((bytes) {
      if (!mounted) return;
      setState(() => _noiseBytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _noiseBytes;
    if (bytes == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Opacity(
        opacity: widget.opacity,
        child: Image.memory(
          bytes,
          repeat: ImageRepeat.repeat,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

Future<Uint8List> _generateNoisePng() async {
  const size = 20;
  final rand = Random(31);
  final pixels = Uint8List(size * size * 4);

  for (var i = 0; i < size * size; i++) {
    final base = i * 4;
    final value = 110 + rand.nextInt(100);
    pixels[base] = value;
    pixels[base + 1] = value;
    pixels[base + 2] = value;
    pixels[base + 3] = 255;
  }

  final buffer = await ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ImageDescriptor.raw(
    buffer,
    width: size,
    height: size,
    pixelFormat: PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ImageByteFormat.png);

  codec.dispose();
  descriptor.dispose();
  buffer.dispose();

  return data!.buffer.asUint8List();
}
