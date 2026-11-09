import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class PartnerModeSwipe extends StatefulWidget {
  const PartnerModeSwipe(
      {super.key,
      required this.child,
      required this.onActivate,
      this.onProgress});
  final Widget child;
  final VoidCallback onActivate;
  final ValueChanged<double>? onProgress;
  @override
  State<PartnerModeSwipe> createState() => _PartnerModeSwipeState();
}

class _PartnerModeSwipeState extends State<PartnerModeSwipe> {
  Offset _start = Offset.zero;
  Offset _delta = Offset.zero;
  void _reset() {
    _delta = Offset.zero;
    widget.onProgress?.call(0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragDown: (d) {
          _start = d.globalPosition;
          _delta = Offset.zero;
        },
        onVerticalDragUpdate: (d) {
          _delta = d.globalPosition - _start;
          widget.onProgress?.call((-_delta.dy).clamp(0, 64));
        },
        onVerticalDragEnd: (_) {
          final valid = -_delta.dy >= 48 && -_delta.dy >= _delta.dx.abs() * 1.5;
          _reset();
          if (valid) {
            widget.onActivate();
          }
        },
        onVerticalDragCancel: _reset,
        child: widget.child,
      );
}

/// Its 44px target is above the bar, separate from the existing My tap target.
class PartnerBarFrame extends StatelessWidget {
  const PartnerBarFrame(
      {super.key,
      required this.child,
      required this.barHeight,
      this.onActivate,
      this.lift = 0,
      this.onProgress});
  final Widget child;
  final double barHeight;
  final VoidCallback? onActivate;
  final double lift;
  final ValueChanged<double>? onProgress;
  @override
  Widget build(BuildContext context) {
    if (onActivate == null) return SizedBox(height: barHeight, child: child);
    return SizedBox(
        height: barHeight + 44,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(
                    child: Align(
                        alignment: Alignment.topCenter,
                        child: Semantics(
                          label: '사장님 모드로 전환',
                          button: true,
                          onTap: onActivate,
                          child: ExcludeSemantics(
                              child: PartnerModeSwipe(
                            onActivate: onActivate!,
                            onProgress: onProgress,
                            child: GestureDetector(
                              onTap: onActivate,
                              behavior: HitTestBehavior.opaque,
                              child: SizedBox(
                                  width: 48,
                                  height: 44,
                                  child:
                                      Stack(clipBehavior: Clip.none, children: [
                                    AnimatedPositioned(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      left: 0,
                                      right: 0,
                                      top: 36 - lift,
                                      height: 44,
                                      child: const DecoratedBox(
                                          decoration: BoxDecoration(
                                              color: Color(0xFF312E81),
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                      top:
                                                          Radius.circular(16))),
                                          child: Align(
                                              alignment: Alignment.topCenter,
                                              child: Icon(
                                                  Icons.keyboard_arrow_up,
                                                  size: 18,
                                                  color: Colors.white))),
                                    ),
                                  ])),
                            ),
                          )),
                        ))),
              ])),
          Positioned(
              left: 0, right: 0, bottom: 0, height: barHeight, child: child),
        ]));
  }
}
