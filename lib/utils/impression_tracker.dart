import 'dart:async';

import 'package:flutter/widgets.dart';

/// 노출(impression) 이벤트를 **한 세션에 한 번만** 찍게 해 주는 기록장.
///
/// 노출을 볼 때마다 찍으면 분모가 부풀어 CTR 이 0 에 수렴한다. 홈 배너는
/// 3초마다 자동으로 넘어가므로 홈에 1분만 있어도 20건이 쌓이고, 목록은
/// 스크롤로 들락날락하는 만큼 늘어난다. 그래서 **같은 세션·같은 대상은 한 번**
/// 으로 잠근다 (2026-09-24 확정).
///
/// 세션의 경계를 **30분 무활동**으로 둔 것은 GA4 의 기준과 같게 맞추기
/// 위해서다. 다르게 두면 BigQuery 에서 `ga_session_id` 로 묶은 분모와
/// 앱이 보낸 건수가 어긋난다.
class ImpressionSession {
  ImpressionSession._();

  static const Duration _sessionGap = Duration(minutes: 30);

  static final Set<String> _seen = <String>{};
  static DateTime? _touchedAt;

  /// 이 세션에서 [key] 가 처음이면 `true`. 두 번째부터는 `false`.
  ///
  /// 부르는 것만으로 활동으로 치고 세션을 연장한다 — GA4 와 같다.
  static bool claim(String key) {
    final now = DateTime.now();
    final last = _touchedAt;
    if (last == null || now.difference(last) > _sessionGap) _seen.clear();
    _touchedAt = now;
    return _seen.add(key);
  }

  @visibleForTesting
  static void resetForTest() {
    _seen.clear();
    _touchedAt = null;
  }

  @visibleForTesting
  static int get seenCount => _seen.length;
}

/// 감싼 위젯이 **화면에 절반 이상 1초 넘게 보이면** [onImpression] 을 한 번 부른다.
///
/// 왜 이 세 조건인가 —
///   · **절반 이상** : 스크롤 끝에 살짝 걸친 것을 봤다고 셀 수는 없다.
///   · **1초** : 빠르게 지나가며 스쳰 것을 빼낸다. `analytics_events.dart` 의
///     노출 이벤트 주석이 처음부터 이 기준으로 적혀 있었다.
///   · **세션에 한 번** : [ImpressionSession] 이 맡는다.
///
/// 「보이는가」는 자기 [RenderBox] 와 **가장 가까운 스크롤 뷰포트**를 겹쳐
/// 재는 것으로 판단한다. 스크롤 영역이 없으면 화면 전체를 뷰포트로 본다.
/// 바텀시트나 대화상자가 덮고 있는 동안에는 찍지 않는다([ModalRoute.isCurrent]).
///
/// 재사용되는 목록에 넣을 때는 [dedupKey] 가 항목마다 달라야 한다.
/// `SliverList.builder` 는 항목이 바뀌어도 [State] 를 그대로 쓰기 때문에,
/// 키가 바뀌면 이 위젯이 스스로 다시 잰다.
class ImpressionDetector extends StatefulWidget {
  const ImpressionDetector({
    super.key,
    required this.dedupKey,
    required this.onImpression,
    required this.child,
    this.minVisibleFraction = 0.5,
    this.dwell = const Duration(seconds: 1),
    this.enabled = true,
  });

  /// 세션 안에서 이 노출을 가리키는 이름. 목록이면 항목마다 달라야 한다.
  final String dedupKey;

  /// 조건이 맞은 순간 한 번 불린다. 이벤트 전송은 부르는 쪽이 한다.
  final VoidCallback onImpression;

  final Widget child;

  /// 보였다고 칠 최소 면적 비율 (0~1).
  final double minVisibleFraction;

  /// 그만큼 계속 보여야 노출로 센다.
  final Duration dwell;

  /// `false` 면 아무것도 재지 않는다 (로딩 자리표시자 등).
  final bool enabled;

  @override
  State<ImpressionDetector> createState() => _ImpressionDetectorState();
}

class _ImpressionDetectorState extends State<ImpressionDetector> {
  ScrollPosition? _position;
  Timer? _timer;
  bool _evalScheduled = false;

  /// 이 자리에서 판정이 끝났는지. 세션에 이미 있어 안 보낸 경우도 끝난 것으로
  /// 두어, 스크롤마다 다시 재지 않는다.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_onFirstFrame);
  }

  void _onFirstFrame(Duration _) {
    if (!mounted) return;
    _attach();
    _evaluate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach();
  }

  @override
  void didUpdateWidget(ImpressionDetector old) {
    super.didUpdateWidget(old);
    // 목록이 항목을 재사용해 다른 대상이 들어온 경우 — 처음부터 다시 잰다.
    if (old.dedupKey != widget.dedupKey || old.enabled != widget.enabled) {
      _cancel();
      _settled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _evaluate();
      });
    }
  }

  void _attach() {
    final next = Scrollable.maybeOf(context)?.position;
    if (next == _position) return;
    _position?.removeListener(_onScroll);
    _position = next;
    _position?.addListener(_onScroll);
  }

  /// 스크롤 알림은 **레이아웃 전에** 온다. 그 자리에서 좌표를 읽으면 아직
  /// 옮겨지지 않은 위치가 나와, 이미 화면을 벗어난 것을 보이는 것으로 읽는다.
  /// 그래서 재는 일은 프레임이 그려진 뒤로 미룬다.
  void _onScroll() {
    if (_settled || _evalScheduled || !mounted) return;
    _evalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evalScheduled = false;
      if (mounted) _evaluate();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _evaluate() {
    if (_settled || !widget.enabled || !mounted) return;
    if (_visibleFraction() >= widget.minVisibleFraction) {
      _timer ??= Timer(widget.dwell, _fire);
    } else {
      _cancel();
    }
  }

  void _fire() {
    _timer = null;
    if (_settled || !mounted) return;
    // 1초가 지난 지금도 보이는지 다시 본다 — 그 사이 스크롤해 버렸을 수 있다.
    if (_visibleFraction() < widget.minVisibleFraction) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _settled = true;
    if (ImpressionSession.claim(widget.dedupKey)) widget.onImpression();
  }

  /// 뷰포트와 겹치는 면적 ÷ 자기 면적.
  double _visibleFraction() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return 0;
    final size = box.size;
    final area = size.width * size.height;
    if (area <= 0) return 0;
    final origin = box.localToGlobal(Offset.zero);
    final self = Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
    final overlap = self.intersect(_viewportRect());
    if (overlap.width <= 0 || overlap.height <= 0) return 0;
    return (overlap.width * overlap.height) / area;
  }

  /// 잘라 내는 창 — **화면**과 **가장 가까운 스크롤 뷰포트**가 겹치는 부분.
  ///
  /// 둘을 곱하는 이유는 스크롤이 겹쳐 있기 때문이다. 홈 배너는 세로로 흐르는
  /// 홈 안에 가로 캐러셀(`PageView`)로 들어 있어서, 가까운 뷰포트만 보면
  /// **홈을 내려 배너가 화면 밖으로 나간 뒤에도** 캐러셀 안에서는 그 장이
  /// 100% 보이는 것으로 읽힌다. 3초마다 자동으로 넘어가니, 보지도 않은 배너의
  /// 노출이 계속 쌓인다. 화면과 겹쳐야 비로소 「보였다」가 된다.
  Rect _viewportRect() {
    final view = View.maybeOf(context);
    Rect window;
    if (view == null) {
      window = Rect.largest;
    } else {
      final logical = view.physicalSize / view.devicePixelRatio;
      window = Rect.fromLTWH(0, 0, logical.width, logical.height);
    }

    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      final origin = viewport.localToGlobal(Offset.zero);
      window = window.intersect(Rect.fromLTWH(
        origin.dx,
        origin.dy,
        viewport.size.width,
        viewport.size.height,
      ));
    }
    return window;
  }

  @override
  void dispose() {
    _cancel();
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
