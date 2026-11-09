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
    this.bottomInset = 0,
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
  double _dragStartIndex = 0;
  double _dragPhase = 0;
  double _dragWobble = 0;
  bool _justEndedDrag = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex;
    _toIndex = widget.selectedIndex;
    _dragT = widget.selectedIndex.toDouble();
    _dragStartIndex = _dragT;
    _controller = AnimationController(
      vsync: this,
      // 전체 모션을 조금 더 느리게 (기존 360ms → 480ms)
      duration: const Duration(milliseconds: 480),
    );
    // 기존 구조를 유지하기 위해 남겨두지만, 실제 배너 스케일 계산은 build에서 직접 처리한다.
    _bannerScale = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void didUpdateWidget(LiquidGlassBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isDragging) return;

    if (widget.selectedIndex != _toIndex) {
      // 드래그로 이미 위치가 맞춰진 경우에는 추가 이동 애니메이션 없이 상태만 동기화
      if (_justEndedDrag) {
        _fromIndex = widget.selectedIndex;
        _toIndex = widget.selectedIndex;
        _dragT = widget.selectedIndex.toDouble();
        _controller.reset();
        _justEndedDrag = false;
      } else {
        _fromIndex = _toIndex;
        _toIndex = widget.selectedIndex;
        _dragT = widget.selectedIndex.toDouble();
        _controller.forward(from: 0);
      }
    } else {
      _justEndedDrag = false;
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
    final fillColor = Colors.white.withOpacity(0.95);
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
        left: false,
        right: false,
        bottom: true,
        minimum: EdgeInsets.only(bottom: widget.bottomInset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: FractionallySizedBox(
              widthFactor: widget.widthFactor,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // 배너 스케일도 선택영역과 동일한 부드러운 곡선으로 펄스(pulse)처럼 커졌다가 줄어들게 만든다.
                  final t = Curves.easeInOutCubic.transform(
                    _controller.value.clamp(0.0, 1.0),
                  );
                  // 1.0 → 1.04 → 1.0
                  double scale = 1.0 + 0.04 * sin(pi * t);
                  // 슬라이드 중일 때는 배너 전체가 살짝 더 커지도록 추가 스케일 적용
                  if (_isDragging) {
                    scale *= 1.06;
                  }
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
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        // 유리 배너 배경은 둥글게 클리핑
                        ClipRRect(
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
                                  borderRadius:
                                      BorderRadius.circular(radius),
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
                                  borderRadius:
                                      BorderRadius.circular(radius),
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
                            ],
                          ),
                        ),
                        // 선택 영역과 탭 아이콘/텍스트는 배너 밖으로 살짝 넘어갈 수 있도록 클리핑 없이 그린다.
                        Material(
                          type: MaterialType.transparency,
                          child: LayoutBuilder(
                    builder: (context, constraints) {
                              final itemWidth =
                                  constraints.maxWidth / widget.tabs.length;
                              // 기본 너비를 넓게 두어 '대학가 근처 식당' 등 긴 라벨이 선택영역에 충분히 감싸지도록 한다.
                              final blobWidth = itemWidth * 0.92;
                              // 기본 높이는 배너와 동일하게 두고, 스케일로 배너를 넘어서도록 조정한다.
                              final blobHeight = widget.barHeight;
                      final centerY = widget.barHeight / 2;
                      final dragIndex =
                          _dragT.round().clamp(0, widget.tabs.length - 1);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (details) {
                          _isDragging = true;
                          _justEndedDrag = false;
                          _dragStartIndex = _dragT;
                          _controller.stop();
                          // 손가락이 닿은 위치를 바로 기준으로 잡도록 드래그 시작 시점에 초기화
                          final local = details.localPosition;
                          final t = local.dx / itemWidth - 0.5;
                          setState(() {
                            _dragT = t.clamp(
                              0.0,
                              widget.tabs.length - 1.0,
                            );
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          final t =
                              details.localPosition.dx / itemWidth - 0.5;
                          setState(() {
                            _dragT = t.clamp(
                              0.0,
                              widget.tabs.length - 1.0,
                            );
                            _dragPhase = (_dragPhase +
                                    details.delta.dx.abs() * 0.22) %
                                (pi * 2);
                            _dragWobble = (details.delta.dx.abs() / itemWidth)
                                .clamp(0.0, 1.0);
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          // 드래그 시작 인덱스와 종료 인덱스(연속값)를 기준으로
                          // 탭을 변경할지 / 원래 탭으로 되돌릴지 결정한다.
                          final double start = _dragStartIndex;
                          final double end = _dragT.clamp(
                            0.0,
                            widget.tabs.length - 1.0,
                          );

                          int target;
                          if ((end - start).abs() < 0.5) {
                            // 시작 탭 주변(±0.5 탭 폭)에서 손을 떼면, 원래 탭에 머무르도록 스냅.
                            target = start
                                .round()
                                .clamp(0, widget.tabs.length - 1);
                          } else {
                            // 그 외에는 "현재 위치에서 가장 가까운 탭"으로 이동.
                            target = end
                                .round()
                                .clamp(0, widget.tabs.length - 1);
                          }

                          _isDragging = false;
                          _dragWobble = 0;
                          // 드래그가 끝났을 때는 선택영역을 결정된 탭 위치에 두고
                          // 추가로 한 번 더 튀는(애니메이션) 모션 없이 상태만 동기화한다.
                          if (target != widget.selectedIndex) {
                            _fromIndex = target;
                            _toIndex = target;
                            _dragT = target.toDouble();
                            _controller.reset();
                            _justEndedDrag = true;
                            widget.onTap(target);
                          } else {
                            // 같은 탭 위에서 드래그를 멈춘 경우에는
                            // 선택영역이 이미 그 위치에 있으므로, from/to 인덱스를
                            // 현재 탭으로 강제 맞추기만 하고 추가 애니메이션은 주지 않는다.
                            _fromIndex = widget.selectedIndex;
                            _toIndex = widget.selectedIndex;
                            _dragT = widget.selectedIndex.toDouble();
                            _controller.reset();
                          }
                        },
                        child: Stack(
                          children: [
                            AnimatedBuilder(
                              animation: _controller,
                              builder: (context, child) {
                                // 탭 간 이동 시 위치/모양 변화 곡선을 더 부드럽게 조정한다.
                                // - travelCurve: 전체 이동 경로 (양 끝이 부드럽게 감속되는 S-curve)
                                // - morphCurve: 형태 변화(늘어남/찌그러짐)를 조금 더 천천히 풀어준다.
                                final travelCurve =
                                    Curves.easeInOutSine.transform(
                                  _controller.value,
                                );
                                final morphCurve =
                                    Curves.easeOutCirc.transform(
                                  min(1, _controller.value * 1.15),
                                );

                                // 기본 시작/끝 위치(탭 인덱스 기준)
                                final baseStartX =
                                    itemWidth * _fromIndex + itemWidth / 2;
                                final baseEndX =
                                    itemWidth * _toIndex + itemWidth / 2;
                                final dragX = itemWidth * (_dragT + 0.5);

                                // 드래그 중에는 선택영역이 손가락 바로 아래에 있어야 하므로,
                                // 중심(start/end)을 손가락 위치(dragX)에 고정한다.
                                double startX;
                                double endX;
                                double travelT;
                                if (_isDragging) {
                                  startX = dragX;
                                  endX = dragX;
                                  travelT = 0.0;
                                } else {
                                  startX = baseStartX;
                                  endX = baseEndX;
                                  travelT = travelCurve;
                                }
                                final dragMorph =
                                    (_dragWobble * 0.9).clamp(0.0, 1.0);
                                final morphT =
                                    _isDragging ? dragMorph : morphCurve;
                                final timeT =
                                    _isDragging ? 0.0 : _controller.value;
                                // 액체의 출렁임:
                                // - 드래그 중: 펄럭이지 않고, 손의 속도에 따라 살짝만 불룩해지는 정도
                                // - 자동 이동 중: 별도의 "출렁임" 없이 형태 변화/이동 곡선만으로 부드럽게 안착
                                double wobblePhase;
                                double wobbleAmp;
                                if (_isDragging) {
                                  final speed = _dragWobble.clamp(0.0, 1.0);
                                  // 시간에 따른 진동은 제거하고, 속도에 비례해 한 번만 살짝 불룩하게.
                                  wobblePhase = 0.0;
                                  wobbleAmp = 0.06 * speed;
                                } else {
                                  // 자동 이동(손을 뗀 뒤 탭으로 수렴)에서는
                                  // 별도의 출렁임 없이 0으로 두어, "억지로 출렁인다"는 느낌을 없앤다.
                                  wobblePhase = 0.0;
                                  wobbleAmp = 0.0;
                                }
                                final glowStrength =
                                    _isDragging ? 1.0 : 0.6;

                                // 선택 영역이 "움직이는 동안"에는 항상 조금 커졌다가,
                                // 목표 탭에 도달했을 때 다시 원래 크기로 돌아오도록 스케일 조정.
                                // 배너와 동일한 곡선(Curves.easeInOutCubic + sin)을 사용해 모션을 통일한다.
                                final movementT = Curves.easeInOutCubic.transform(
                                  _controller.value.clamp(0.0, 1.0),
                                );

                                // 클릭/탭/프레스/드래그 모두에서 공통으로 사용할
                                // 기준 최대 스케일 (기본 대비 약 40% 확대).
                                const double clickMaxScale = 1.40;

                                // 스케일 애니메이션:
                                // - 초반(0.0 ~ 0.5): 1.0 → clickMaxScale 로 빠르게 커진 뒤
                                // - 중간(0.5 ~ 0.9): clickMaxScale 상태를 유지하며 이동
                                // - 마지막(0.9 ~ 1.0): clickMaxScale → 1.0 로 천천히 줄어들어
                                //   "목표 탭에 도착했을 때"에만 작아지는 느낌을 준다.
                                double animScale;
                                if (movementT < 0.5) {
                                  final growT =
                                      Curves.easeOutCubic.transform(movementT / 0.5);
                                  animScale = lerpDouble(
                                        1.0,
                                        clickMaxScale,
                                        growT,
                                      ) ??
                                      clickMaxScale;
                                } else if (movementT < 0.9) {
                                  animScale = clickMaxScale;
                                } else {
                                  final shrinkT = Curves.easeInCubic.transform(
                                    ((movementT - 0.9) / 0.1).clamp(0.0, 1.0),
                                  );
                                  animScale = lerpDouble(
                                        clickMaxScale,
                                        1.0,
                                        shrinkT,
                                      ) ??
                                      1.0;
                                }

                                // 드래그 중에는 클릭 최대 스케일을 기준으로 추가 확대.
                                const double dragExtraMax = 0.15;
                                final dragExtra = dragExtraMax *
                                    _dragWobble.clamp(0.0, 1.0);
                                final dragScale = clickMaxScale + dragExtra;

                                // 상태별 스케일:
                                // - 기본: animScale (1.0 ~ clickMaxScale)
                                // - 드래그 중: dragScale (clickMaxScale 이상)
                                // - 선택된 탭을 꾹 누르는 동안: clickMaxScale 고정

                                double motionScale;
                                if (_isDragging) {
                                  motionScale = dragScale;
                                } else if (_isPressed) {
                                  motionScale = clickMaxScale;
                                } else {
                                  motionScale = animScale;
                                }

                                final blobRect = _blobRect(
                                  centerX: lerpDouble(
                                        startX,
                                        endX,
                                        travelT,
                                      ) ??
                                      endX,
                                  centerY: centerY,
                                  baseWidth: blobWidth * motionScale,
                                  baseHeight: blobHeight * motionScale,
                                  morphT: morphT,
                                  wobblePhase: wobblePhase,
                                  wobbleAmp: wobbleAmp,
                                );

                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CustomPaint(
                                      painter: _LiquidBlobPainter(
                                        startX: startX,
                                        endX: endX,
                                        centerY: centerY,
                                        baseWidth: blobWidth * motionScale,
                                        baseHeight: blobHeight * motionScale,
                                        travelT: travelT,
                                        morphT: morphT,
                                        wobblePhase: wobblePhase,
                                        wobbleAmp: wobbleAmp,
                                        drawFill: true,
                                        drawRim: false,
                                        cornerRadius: radius,
                                      ),
                                    ),
                                    ClipPath(
                                      clipper: _LensClipper(
                                        rect: blobRect,
                                        cornerRadius: radius,
                                      ),
                                      child: _TabRow(
                                        tabs: widget.tabs,
                                        iconBuilder: widget.iconBuilder,
                                        selectedColor: widget.selectedColor,
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
                                        startX: startX,
                                        endX: endX,
                                        centerY: centerY,
                                        baseWidth: blobWidth * motionScale,
                                        baseHeight: blobHeight * motionScale,
                                        travelT: travelT,
                                        morphT: morphT,
                                        wobblePhase: wobblePhase,
                                        wobbleAmp: wobbleAmp,
                                        drawFill: false,
                                        drawRim: true,
                                        glowStrength: glowStrength,
                                        cornerRadius: radius,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            Row(
                              children: List.generate(widget.tabs.length, (index) {
                                final tab = widget.tabs[index];
                                final isSelected = _isDragging
                                    ? index == dragIndex
                                    : index == widget.selectedIndex;
                                final Color baseUnselectedColor =
                                    Color.lerp(
                                          widget.unselectedColor,
                                          widget.selectedColor,
                                          0.35,
                                        ) ??
                                        widget.unselectedColor;
                                final iconColor = isSelected
                                    ? widget.selectedColor
                                    : baseUnselectedColor;
                                final labelStyle = isSelected
                                    ? widget.selectedLabelStyle.copyWith(
                                        color: widget.selectedColor,
                                      )
                                    : widget.unselectedLabelStyle.copyWith(
                                        color: baseUnselectedColor,
                                      );

                                return Expanded(
                                  child: InkWell(
                                    onTapDown: (_) {
                                      // 현재 탭을 누르고 있는 동안에는 선택영역이 커지도록 플래그 설정
                                      if (!_isDragging &&
                                          index == widget.selectedIndex) {
                                        setState(() {
                                          _isPressed = true;
                                        });
                                      }
                                    },
                                    onTapCancel: () {
                                      if (_isPressed) {
                                        setState(() {
                                          _isPressed = false;
                                        });
                                      }
                                    },
                                    onTap: () {
                                      // 이미 선택된 탭을 다시 탭했을 때도 선택영역이 살짝 커지는 모션을 주기 위해 처리
                                      if (!_isDragging &&
                                          index == widget.selectedIndex) {
                                        _fromIndex = index;
                                        _toIndex = index;
                                        _dragT = index.toDouble();
                                        _controller.forward(from: 0);
                                      }
                                      if (_isPressed) {
                                        _isPressed = false;
                                      }
                                      widget.onTap(index);
                                    },
                                    borderRadius:
                                        BorderRadius.circular(radius),
                                    splashColor:
                                        Colors.white.withOpacity(0.12),
                                    highlightColor: Colors.transparent,
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
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
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
    required this.cornerRadius,
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
  final double cornerRadius;
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
        cornerRadius: cornerRadius,
      );

      if (stretch > 0.5) {
        _drawBlob(
          canvas,
          centerX: startX,
          centerY: centerY + wobbleY * (1 - travelT),
          width: baseWidth * 0.92,
          height: baseHeight * 0.82,
          intensity: 0.06 * (1 - travelT),
          cornerRadius: cornerRadius,
        );
        _drawBlob(
          canvas,
          centerX: endX,
          centerY: centerY + wobbleY * travelT,
          width: baseWidth * 0.92,
          height: baseHeight * 0.82,
          intensity: 0.06 * travelT,
          cornerRadius: cornerRadius,
        );
        _drawBlob(
          canvas,
          centerX: (startX + endX) / 2,
          centerY: centerY + wobbleY * 0.4,
          width: baseWidth + connectorBoost,
          height: baseHeight * (0.78 + 0.18 * phase),
          intensity: 0.05 * phase,
          cornerRadius: cornerRadius,
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
      final rrect =
          RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withOpacity(0.55);
      canvas.drawRRect(rrect.deflate(1.2), rim);

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withOpacity(0.18 * glowStrength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawRRect(rrect.deflate(1), glow);
    }
  }

  void _drawBlob(
    Canvas canvas, {
    required double centerX,
    required double centerY,
    required double width,
    required double height,
    required double intensity,
      required double cornerRadius,
  }) {
    if (intensity <= 0) return;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: width,
      height: height,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
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
    canvas.drawRRect(rrect, paint);

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
    final highlightRRect = RRect.fromRectAndRadius(
      highlightRect,
      Radius.circular(cornerRadius * 0.7),
    );
    canvas.drawRRect(highlightRRect, highlightPaint);
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
        cornerRadius != oldDelegate.cornerRadius ||
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
  _LensClipper({required this.rect, required this.cornerRadius});

  final Rect rect;
  final double cornerRadius;

  @override
  Path getClip(Size size) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(cornerRadius),
        ),
      );
  }

  @override
  bool shouldReclip(covariant _LensClipper oldClipper) {
    return rect != oldClipper.rect ||
        cornerRadius != oldClipper.cornerRadius;
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
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
