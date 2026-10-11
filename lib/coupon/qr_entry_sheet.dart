import 'package:flutter/material.dart';

import 'package:new1/config/screen_ids.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/mileage_service.dart';

/// QR 진입 시트에서 고른 행동.
enum QrEntryAction {
  /// 쿠폰만 쓴다.
  useCoupon,

  /// 쿠폰을 쓰면서 스탬프도 한 번에 적립한다 (PIN 한 번).
  useCouponWithStamp,

  /// 스탬프만 적립한다.
  addStamp,
  later,
  viewStore,
}

/// 테이블 QR로 들어왔을 때 보여 주는 시트 (시안 14a·14b, `sheet.coupon_arrived`).
///
/// - 첫 방문: 쿠폰이 도착했어요 (쿠폰은 매장당 평생 1장, 서버가 한 번만 발급).
/// - 그 뒤 방문: 스탬프 적립 시트가 기본이다. 아직 안 쓴 쿠폰이 있으면 같은 시트에서
///   "쿠폰 쓰고 스탬프도 찍기"로 함께 쓰도록 유도한다.
///
/// 어느 분기든 막다른 화면이 없도록 항상 닫는 버튼(나중에/매장 보기)이 있다.
Future<QrEntryAction?> showQrEntrySheet(
  BuildContext context, {
  required QrEntry entry,
  required String restaurantName,
  UserCoupon? coupon,
}) {
  return showModalBottomSheet<QrEntryAction>(
    context: context,
    routeSettings: const RouteSettings(name: ScreenIds.sheetCouponArrived),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => QrEntrySheet(
      entry: entry,
      restaurantName: restaurantName,
      coupon: coupon,
    ),
  );
}

class QrEntrySheet extends StatelessWidget {
  const QrEntrySheet({
    super.key,
    required this.entry,
    required this.restaurantName,
    this.coupon,
  });

  final QrEntry entry;
  final String restaurantName;
  final UserCoupon? coupon;

  static const Color _primary = Color(0xFF4F46E5);
  static const Color _lav = Color(0xFFEEEDFC);
  static const Color _ink = Color(0xFF191F28);
  static const Color _sub = Color(0xFF8B95A1);
  static const Color _red = Color(0xFFE11D48);

  bool get _isStampBranch =>
      entry.branch == QrEntryBranch.stampProgress ||
      entry.branch == QrEntryBranch.stampDoneToday;

  bool get _hasCoupon => coupon != null && entry.branch != QrEntryBranch.none;

  /// "오늘 23:59까지" / "10월 14일까지"
  static String expiryText(DateTime? exp, DateTime now) {
    if (exp == null) return '';
    final sameDay =
        exp.year == now.year && exp.month == now.month && exp.day == now.day;
    if (sameDay) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '오늘 ${two(exp.hour)}:${two(exp.minute)}까지';
    }
    return '${exp.month}월 ${exp.day}일까지';
  }

  String get _eyebrow {
    switch (entry.branch) {
      case QrEntryBranch.couponArrived:
        return '테이블 QR로 들어왔어요';
      case QrEntryBranch.stampProgress:
      case QrEntryBranch.stampDoneToday:
        return '$restaurantName · 다시 오셨네요';
      default:
        return restaurantName;
    }
  }

  String get _headline {
    switch (entry.branch) {
      case QrEntryBranch.couponArrived:
        return '쿠폰이 도착했어요';
      case QrEntryBranch.couponHeld:
        return '갖고 계신 쿠폰이 있어요';
      case QrEntryBranch.stampProgress:
        return entry.stamp.nextReward.isNotEmpty
            ? '오늘 찍으면\n${entry.stamp.nextReward}'
            : '오늘 스탬프 찍고 가세요';
      case QrEntryBranch.stampDoneToday:
        return '오늘 적립 완료!';
      case QrEntryBranch.none:
        return restaurantName;
    }
  }

  String get _stampLine {
    final s = entry.stamp;
    if (!s.enabled || s.target <= 0) return '';
    final base = '스탬프 ${s.current}/${s.target}';
    switch (entry.branch) {
      case QrEntryBranch.couponArrived:
        return '$base · 계산하고 바로 적립';
      case QrEntryBranch.stampProgress:
        final last = s.lastVisitAt;
        return last == null
            ? base
            : '$base · 지난 방문 ${last.month}월 ${last.day}일';
      default:
        return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stampLine = _stampLine;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _eyebrow,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _sub,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.3,
              letterSpacing: -0.6,
              color: _ink,
            ),
          ),
          if (_isStampBranch && entry.stamp.target > 0) ...[
            const SizedBox(height: 14),
            _progress(),
            if (stampLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                stampLine,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _sub,
                ),
              ),
            ],
          ],
          if (_hasCoupon) ...[
            const SizedBox(height: 16),
            _couponCard(DateTime.now()),
          ],
          const SizedBox(height: 18),
          _buttons(context),
          if (!_isStampBranch && stampLine.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              stampLine,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: _sub,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 쿠폰 카드. 재방문이면 "갖고 계신 쿠폰"으로 함께 쓰도록 유도한다.
  Widget _couponCard(DateTime now) {
    final c = coupon!;
    final revisit = _isStampBranch;
    final label = !revisit
        ? null
        : (entry.couponIsReward ? '스탬프 보상 쿠폰이 도착해 있어요' : '갖고 계신 쿠폰');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: _lav,
        borderRadius: BorderRadius.circular(18),
        border: revisit ? Border.all(color: _primary.withOpacity(0.35)) : null,
      ),
      child: Column(
        children: [
          if (label != null) ...[
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _primary,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            c.benefit?.resolvedTitle ?? '쿠폰',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              expiryText(c.expiresAt, now),
              '$restaurantName에서만',
            ].where((e) => e.isNotEmpty).join(' · '),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    final s = entry.stamp;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < s.target && i < 10; i++)
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < s.current ? _primary : _lav,
            ),
          ),
      ],
    );
  }

  Widget _buttons(BuildContext context) {
    switch (entry.branch) {
      case QrEntryBranch.couponArrived:
      case QrEntryBranch.couponHeld:
        return _column(context, [
          _Btn('지금 쓰기', QrEntryAction.useCoupon, primary: true),
          _Btn('나중에 쓸게요', QrEntryAction.later),
        ]);
      case QrEntryBranch.stampProgress:
        if (_hasCoupon) {
          return Column(
            children: [
              _column(context, [
                _Btn('쿠폰 쓰고 스탬프도 찍기', QrEntryAction.useCouponWithStamp,
                    primary: true),
                _Btn('스탬프만 찍기', QrEntryAction.addStamp, outlined: true),
                _Btn('매장 보기', QrEntryAction.viewStore),
              ]),
              const SizedBox(height: 4),
              const Text(
                '직원이 PIN을 한 번만 누르면 같이 처리돼요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _sub,
                ),
              ),
            ],
          );
        }
        return _column(context, [
          _Btn('스탬프 찍기', QrEntryAction.addStamp, primary: true),
          _Btn('매장 보기', QrEntryAction.viewStore),
        ]);
      case QrEntryBranch.stampDoneToday:
        if (_hasCoupon) {
          return _column(context, [
            _Btn('쿠폰 쓰기', QrEntryAction.useCoupon, primary: true),
            _Btn('매장 보기', QrEntryAction.viewStore),
          ]);
        }
        return _column(context, [
          _Btn('매장 보기', QrEntryAction.viewStore, primary: true),
        ]);
      case QrEntryBranch.none:
        return _column(context, [
          _Btn('매장 보기', QrEntryAction.viewStore, primary: true),
        ]);
    }
  }

  Widget _column(BuildContext context, List<_Btn> buttons) {
    return Column(
      children: [
        for (final b in buttons)
          if (b.primary)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(b.action),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(b.label),
              ),
            )
          else if (b.outlined)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(b.action),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: const BorderSide(color: _primary, width: 1.4),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(b.label),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(b.action),
              child: Text(
                b.label,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _sub,
                ),
              ),
            ),
      ],
    );
  }
}

class _Btn {
  const _Btn(this.label, this.action,
      {this.primary = false, this.outlined = false});

  final String label;
  final QrEntryAction action;
  final bool primary;
  final bool outlined;
}
