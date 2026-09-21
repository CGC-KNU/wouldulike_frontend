import 'package:flutter/material.dart';

/// 글자가 하나씩 통통 떠오르며 나타나는 텍스트.
///
/// 각 글자를 개별 위젯으로 그려 순차 지연(stagger)으로 페이드+상승시킨다.
/// 한글 완성형 음절은 UTF-16 단일 코드유닛이라 `split('')`로 안전하게 분해된다.
/// 화면 탭으로 즉시 완성하려면 [AnimatedRevealTextState.completeNow]를 호출한다.
class AnimatedRevealText extends StatefulWidget {
  const AnimatedRevealText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
    this.charStagger = const Duration(milliseconds: 52),
    this.charDuration = const Duration(milliseconds: 300),
    this.startDelay = const Duration(milliseconds: 120),
    this.onCompleted,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final Duration charStagger;
  final Duration charDuration;
  final Duration startDelay;
  final VoidCallback? onCompleted;

  @override
  State<AnimatedRevealText> createState() => AnimatedRevealTextState();
}

class AnimatedRevealTextState extends State<AnimatedRevealText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late int _charCount;
  bool _completedNotified = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  void _setup() {
    _completedNotified = false;
    _charCount = widget.text.replaceAll('\n', '').length;
    final totalMs =
        widget.charStagger.inMilliseconds * (_charCount - 1).clamp(0, 9999) +
            widget.charDuration.inMilliseconds;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs <= 0 ? 1 : totalMs),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _notifyCompleted();
      });
    Future.delayed(widget.startDelay, () {
      if (mounted) _controller.forward();
    });
  }

  void _notifyCompleted() {
    if (_completedNotified) return;
    _completedNotified = true;
    widget.onCompleted?.call();
  }

  @override
  void didUpdateWidget(covariant AnimatedRevealText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.dispose();
      _setup();
    }
  }

  /// 타이핑을 즉시 완료한다.
  void completeNow() {
    if (_controller.isCompleted) return;
    _controller.value = 1.0;
    _notifyCompleted();
  }

  bool get isCompleted => _controller.isCompleted || _completedNotified;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      // 접근성: 모션 최소화 시 즉시 표시
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyCompleted());
      return Text(widget.text,
          style: widget.style, textAlign: widget.textAlign);
    }

    final totalMs = _controller.duration!.inMilliseconds;
    final lines = widget.text.split('\n');
    var globalIndex = 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      // 줄마다 Wrap이 내용 너비로 줄어들기 때문에, 줄 사이 정렬은 Column이 결정한다.
      // 여기를 고정하면 textAlign이 무시돼 짧은 줄이 가운데로 밀린다.
      crossAxisAlignment: _columnAlignment(),
      children: lines.map((line) {
        return Wrap(
          alignment: _wrapAlignment(),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: line.split('').map((ch) {
            final i = globalIndex++;
            final startMs = widget.charStagger.inMilliseconds * i;
            final endMs = startMs + widget.charDuration.inMilliseconds;
            var begin = (startMs / totalMs).clamp(0.0, 1.0);
            var end = (endMs / totalMs).clamp(0.0, 1.0);
            if (end <= begin) end = (begin + 0.001).clamp(0.0, 1.0);
            final anim = CurvedAnimation(
              parent: _controller,
              curve: Interval(begin, end, curve: Curves.easeOutBack),
            );
            return AnimatedBuilder(
              animation: anim,
              builder: (_, __) {
                final v = anim.value;
                return Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - v).clamp(0.0, 1.0) * 12),
                    child: Text(
                      ch == ' ' ? ' ' : ch,
                      style: widget.style,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  CrossAxisAlignment _columnAlignment() {
    switch (widget.textAlign) {
      case TextAlign.start:
      case TextAlign.left:
        return CrossAxisAlignment.start;
      case TextAlign.right:
      case TextAlign.end:
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.center;
    }
  }

  WrapAlignment _wrapAlignment() {
    switch (widget.textAlign) {
      case TextAlign.start:
      case TextAlign.left:
        return WrapAlignment.start;
      case TextAlign.right:
      case TextAlign.end:
        return WrapAlignment.end;
      default:
        return WrapAlignment.center;
    }
  }
}
