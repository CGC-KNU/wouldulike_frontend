import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/services/coupon_service.dart';
import 'package:new1/wallet/wallet_screen.dart';
import 'package:new1/widgets/coupon_ticket_card.dart';

/// 쿠폰이 발급될 때마다 띄우는 공용 팝업.
/// 일반 쿠폰이든 한정 쿠폰이든 발급 경로와 무관하게 이걸 쓴다.
/// 반드시 **발급 API 성공 응답 이후에만** 호출한다.
Future<void> showCouponIssuedDialog(
  BuildContext context, {
  required String title,
  String tag = '쿠폰 발급',
  String description = '내 쿠폰함에 담겼어요',
  UserCoupon? coupon,
}) {
  return showRewardBurst(
    context,
    tag: tag,
    title: title,
    description: description,
    coupon: coupon,
    showWallet: true,
  );
}

/// 리워드 수령 연출. 선물 상자가 흔들리다 뚜껑이 날아가고
/// 색종이와 함께 쿠폰이 솟아오른다.
///
/// [showWallet]이면 '내 지갑 바로가기' 버튼이 붙는다.
///
/// 반드시 **수령 API 성공 응답 이후에만** 호출한다.
Future<void> showRewardBurst(
  BuildContext context, {
  required String tag,
  required String title,
  String description = '내 쿠폰함에 담겼어요',
  String closeText = '닫기',
  UserCoupon? coupon,
  bool showWallet = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '리워드',
    barrierColor: const Color(0x9E12102D),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => _RewardBurst(
      tag: tag,
      title: title,
      description: description,
      closeText: closeText,
      coupon: coupon,
      showWallet: showWallet,
    ),
  );
}

const _deep = Color(0xFF312E81);
const _ink = Color(0xFF191F28);
const _muted = Color(0xFF4E5968);
const _gold = Color(0xFFE1B53E);
const _goldBg = Color(0xFFFBF3DC);
const _goldInk = Color(0xFF8A6410);

class _RewardBurst extends StatefulWidget {
  const _RewardBurst({
    required this.tag,
    required this.title,
    required this.description,
    required this.closeText,
    this.coupon,
    this.showWallet = false,
  });

  final String tag;
  final String title;
  final String description;
  final String closeText;

  /// 발급된 실제 쿠폰. null이면 방금 발급된 쿠폰을 서버에서 찾아 그린다.
  final UserCoupon? coupon;

  /// '내 지갑 바로가기' 버튼 노출 여부.
  final bool showWallet;

  @override
  State<_RewardBurst> createState() => _RewardBurstState();
}

class _RewardBurstState extends State<_RewardBurst>
    with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 1900);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _total);

  /// 뚜껑이 날아가는 순간의 햅틱을 한 번만 울리기 위한 플래그.
  bool _popped = false;

  /// 호출부가 쿠폰을 안 넘겼을 때 서버에서 찾아온 가장 최근 발급 쿠폰.
  UserCoupon? _fetched;

  // 1900ms 기준 구간. 각 요소가 겹치면서 이어진다.
  late final Animation<double> _shake = _seg(0, 500);
  late final Animation<double> _lid = _seg(480, 1330, Curves.easeOutCubic);
  late final Animation<double> _confetti = _seg(480, 1630);
  late final Animation<double> _coupon = _seg(1030, 1630, Curves.easeOutBack);
  late final Animation<double> _fade = _seg(1030, 1430);
  late final Animation<double> _button = _seg(1380, 1880);

  Animation<double> _seg(int fromMs, int toMs, [Curve curve = Curves.linear]) {
    final t = _total.inMilliseconds;
    return CurvedAnimation(
      parent: _c,
      curve: Interval(fromMs / t, toMs / t, curve: curve),
    );
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_maybeHaptic);
    _c.forward();
    if (widget.coupon == null) _loadLatestCoupon();
  }

  /// 가장 최근 발급 쿠폰. 실패하면 문구만으로 카드를 그린다.
  Future<void> _loadLatestCoupon() async {
    try {
      final coupons =
          await CouponService.fetchMyCoupons(status: CouponStatus.issued);
      if (!mounted || coupons.isEmpty) return;
      final sorted = [...coupons]..sort((a, b) =>
          (b.issuedAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(a.issuedAt?.millisecondsSinceEpoch ?? 0));
      setState(() => _fetched = sorted.first);
    } catch (_) {
      // 조회 실패해도 연출은 그대로 진행한다.
    }
  }

  void _maybeHaptic() {
    if (_popped || _c.value < 480 / _total.inMilliseconds) return;
    _popped = true;
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _c
      ..removeListener(_maybeHaptic)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // 카드 영역 탭은 닫히지 않도록 흡수
            child: SizedBox(
              width: 300,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBox(),
                    Transform.translate(
                      offset: Offset(0, 26 * (1 - _coupon.value)),
                      child: Opacity(
                        opacity: _fade.value.clamp(0.0, 1.0),
                        child: _buildCoupon(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: _button.value.clamp(0.0, 1.0),
                      child: _buildClose(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBox() {
    // 흔들림은 후반으로 갈수록 잦아든다.
    final s = _shake.value;
    final angle = math.sin(s * math.pi * 4) * 0.07 * (1 - s);

    return SizedBox(
      height: 132,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ConfettiPainter(_confetti.value),
            ),
          ),
          Transform.rotate(
            angle: angle,
            child: SizedBox(
              width: 132,
              height: 118,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 6,
                    bottom: 0,
                    child: _boxPart(
                      width: 120,
                      height: 82,
                      colors: const [Color(0xFF5B54D6), _deep],
                      ribbon: const [Color(0xFFF3D07A), Color(0xFFD9A32B)],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 14 - 190 * _lid.value,
                    child: Opacity(
                      opacity: (1 - _lid.value).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: -0.66 * _lid.value,
                        child: _boxPart(
                          width: 132,
                          height: 30,
                          colors: const [Color(0xFF6C64EC), Color(0xFF4038A0)],
                          ribbon: const [Color(0xFFF7DC93), _gold],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boxPart({
    required double width,
    required double height,
    required List<Color> colors,
    required List<Color> ribbon,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59000000), blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      child: Center(
        child: Container(
          width: 18,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: ribbon,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoupon() {
    final coupon = widget.coupon ?? _fetched;
    final benefit = coupon?.benefit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _goldBg,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: _gold),
          ),
          child: Text(
            widget.tag,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _goldInk,
            ),
          ),
        ),
        // 지갑 쿠폰함·식당 상세와 같은 카드 그대로 쓴다. 버튼은 숨긴다.
        CouponTicketCard(
          iconPath: 'assets/icons/category/all.svg',
          storeLabel: benefit?.restaurantNameText ?? '우주라이크',
          title: benefit?.resolvedTitle ?? widget.title,
          subtitle: benefit?.resolvedSubtitle ?? widget.description,
          notes: benefit?.notesText,
          showAction: false,
          margin: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildClose() {
    if (!widget.showWallet) {
      return _closeButton(widget.closeText, filled: true);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
              );
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _deep,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              '내 지갑 바로가기',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _closeButton(widget.closeText, filled: false),
      ],
    );
  }

  Widget _closeButton(String label, {required bool filled}) {
    return TextButton(
      onPressed: () => Navigator.of(context).maybePop(),
      style: TextButton.styleFrom(
        backgroundColor: filled ? Colors.white : Colors.transparent,
        foregroundColor: filled ? _deep : Colors.white,
        padding:
            EdgeInsets.symmetric(horizontal: filled ? 26 : 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 뚜껑이 날아갈 때 방사형으로 흩어지는 색종이.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);

  final double t;

  static const _count = 26;
  static const _colors = <Color>[
    _gold,
    Color(0xFF6366F1),
    Color(0xFFF472B6),
    Color(0xFF34D399),
    Color(0xFFFBBF24),
    Color(0xFFA78BFA),
    Color(0xFF60A5FA),
    Color(0xFFFB7185),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.42);

    for (var i = 0; i < _count; i++) {
      // 파티클마다 조금씩 늦게 출발해 한 덩어리로 보이지 않게 한다.
      final delay = i / _count * 0.18;
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;

      final angle = (-160 + (320 / (_count - 1)) * i) * math.pi / 180;
      final dist = 110 + (math.sin(i * 2.3)).abs() * 90;
      final pos = origin +
          Offset(
              math.cos(angle) * dist * p, math.sin(angle) * dist * p - 70 * p);

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate((i * 67 % 360 + 180) * math.pi / 180 * p);
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: 1 - p);
      if (i % 3 == 0) {
        canvas.drawCircle(Offset.zero, 4 * p.clamp(0.6, 1.0), paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 9, height: 13),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
