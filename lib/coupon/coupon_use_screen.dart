import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/analytics_events.dart';
import '../services/coupon_service.dart';
import '../utils/analytics_logger.dart';

/// 쿠폰 사용 화면 — "쑥스러움 제거".
///
/// 매장에서 직원에게 그대로 보여주는 전체 화면 티켓. 실제 사용 처리는
/// 직원이 관리자 PIN을 입력해야 완료되며(보안), 그 단계를 "직원 확인"으로
/// 리프레임한다. 사용이 완료되면 `true`를 반환한다.
class CouponUseScreen extends StatelessWidget {
  const CouponUseScreen({
    super.key,
    required this.coupon,
    required this.restaurantId,
  });

  final UserCoupon coupon;
  final int restaurantId;

  static const Color _primary = Color(0xFF312E81);
  static const Color _accent = Color(0xFF6366F1);
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF9CA3AF);
  static const Color _danger = Color(0xFFE11D48);

  String? get _restaurantName => coupon.benefit?.restaurantNameText;

  String get _title => coupon.benefit?.resolvedTitle ?? '할인 쿠폰';

  String? get _subtitle {
    final s = coupon.benefit?.resolvedSubtitle;
    return (s != null && s.isNotEmpty) ? s : null;
  }

  String? get _notes => coupon.benefit?.notesText;

  ({String text, bool urgent})? get _dday {
    final exp = coupon.expiresAt;
    if (exp == null) return null;
    // 캘린더 일수 기준 (duration.inDays는 47시간을 1일로 절삭하는 문제가 있음)
    final now = DateTime.now();
    final expDate = DateTime(exp.year, exp.month, exp.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = expDate.difference(today).inDays;
    if (days < 0) return (text: '기한 만료', urgent: true);
    if (days == 0) return (text: '오늘까지', urgent: true);
    return (text: 'D-$days', urgent: days <= 7);
  }

  Future<void> _openStaffConfirm(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StaffConfirmSheet(
        coupon: coupon,
        restaurantId: restaurantId,
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dday = _dday;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                '직원분께\n이 화면을 보여주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  letterSpacing: -0.5,
                  color: _ink,
                ),
              ),
              const Spacer(),
              _buildTicket(dday),
              const SizedBox(height: 22),
              const Text(
                '따로 말하지 않아도 괜찮아요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                '화면만 보여주면 끝!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openStaffConfirm(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('직원이 확인했어요 · 사용 완료'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicket(({String text, bool urgent})? dday) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.14),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 상단 (인디고): 매장 + 혜택
            Container(
              width: double.infinity,
              color: _primary,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                children: [
                  if (_restaurantName != null)
                    Text(
                      _restaurantName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC7D2FE),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  if (_subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFD1D6FF),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 절취선 (양옆 노치)
            _buildPerforation(),
            // 하단 (흰): 코드 + 조건 + D-day
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
              child: Column(
                children: [
                  Text(
                    coupon.code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '직원이 확인하는 코드예요',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  if (_notes != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '사용 조건 · ${_notes!}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                  if (dday != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: dday.urgent
                            ? const Color(0xFFFDE8EC)
                            : const Color(0xFFEEF4FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        dday.urgent ? '${dday.text} · 곧 사라져요' : dday.text,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: dday.urgent ? _danger : _accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerforation() {
    return SizedBox(
      height: 24,
      child: Stack(
        children: [
          Container(color: Colors.white),
          Positioned(
            left: -12,
            top: 0,
            child: _notch(),
          ),
          Positioned(
            right: -12,
            top: 0,
            child: _notch(),
          ),
          const Positioned(
            left: 24,
            right: 24,
            top: 11,
            child: _DashedLine(),
          ),
        ],
      ),
    );
  }

  Widget _notch() {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            // 배경(흰 Scaffold)과 같은 색 원으로 티켓을 물어뜯은 듯한 노치
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashW = 5.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dashW + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dashW,
              height: 2,
              color: const Color(0xFFD1D5DB),
            ),
          ),
        );
      },
    );
  }
}

/// "직원 확인" 시트 — 직원이 관리자 PIN을 입력해 사용 처리한다.
class _StaffConfirmSheet extends StatefulWidget {
  const _StaffConfirmSheet({
    required this.coupon,
    required this.restaurantId,
  });

  final UserCoupon coupon;
  final int restaurantId;

  @override
  State<_StaffConfirmSheet> createState() => _StaffConfirmSheetState();
}

class _StaffConfirmSheetState extends State<_StaffConfirmSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _loading = false;

  static const Color _primary = Color(0xFF312E81);
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF9CA3AF);
  static const Color _danger = Color(0xFFE11D48);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.length != 4) {
      setState(() => _error = '비밀번호 4자리를 입력해 주세요.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    final result = await CouponService.redeemCouponWithoutThrow(
      couponCode: widget.coupon.code,
      restaurantId: widget.restaurantId,
      pin: value,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      AnalyticsLogger.logEvent(
        AnalyticsEvents.couponRedeemed,
        parameters: {
          AnalyticsEvents.paramCouponCode: widget.coupon.code,
          AnalyticsEvents.paramRestaurantId: widget.restaurantId,
          AnalyticsEvents.paramRestaurantName:
              widget.coupon.benefit?.restaurantNameText ?? '',
          AnalyticsEvents.paramCouponIssueSource:
              widget.coupon.couponIssueSource,
        },
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = result.errorMessage ?? '비밀번호가 올바르지 않아요. 다시 확인해 주세요.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '직원 확인',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '직원분이 관리자 비밀번호를 입력하면\n쿠폰이 사용 처리돼요.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: _muted,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              enabled: !_loading,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                hintStyle: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _primary, width: 1.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _danger,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFC7D2FE),
                  minimumSize: const Size.fromHeight(52),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('사용 처리'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
