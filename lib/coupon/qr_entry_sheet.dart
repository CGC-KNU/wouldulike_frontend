import 'package:flutter/material.dart';

import 'package:new1/config/screen_ids.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/master_content.dart';
import 'package:new1/services/mileage_service.dart';
import 'package:new1/widgets/coupon_ticket_card.dart';
import 'package:new1/widgets/stamp_asset_grid.dart';

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
  String? restaurantCategory,
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
      restaurantCategory: restaurantCategory,
    ),
  );
}

class QrEntrySheet extends StatelessWidget {
  const QrEntrySheet({
    super.key,
    required this.entry,
    required this.restaurantName,
    this.coupon,
    this.restaurantCategory,
  });

  final QrEntry entry;
  final String restaurantName;
  final UserCoupon? coupon;

  /// 쿠폰 카드의 카테고리 아이콘용 (식당 상세와 같은 아이콘).
  final String? restaurantCategory;

  static const Color _primary = Color(0xFF4F46E5);
  static const Color _ink = Color(0xFF191F28);
  static const Color _sub = Color(0xFF8B95A1);

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
      // 스탬프 판·쿠폰 카드가 커져서 작은 화면에서도 넘치지 않게 스크롤을 허용한다.
      child: SingleChildScrollView(
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
      ),
    );
  }

  /// 쿠폰 카드. 식당 상세·쿠폰함과 같은 티켓 카드(CouponTicketCard)를 쓴다.
  /// 재방문이면 위에 "갖고 계신 쿠폰"으로 함께 쓰도록 유도한다. 사용 버튼은 아래 시트 버튼이 맡는다.
  Widget _couponCard(DateTime now) {
    final c = coupon!;
    final revisit = _isStampBranch;
    final label = !revisit
        ? null
        : (entry.couponIsReward ? '스탬프 보상 쿠폰이 도착해 있어요' : '갖고 계신 쿠폰');
    final benefit = c.benefit;
    final categoryKey = MasterContent.normalize(
      benefit?.restaurantCategory ?? restaurantCategory ?? '',
      unknownAsEtc: false,
    );
    final storeLabel = benefit?.allStores == true
        ? '전 매장 사용 가능'
        : (benefit?.restaurantNameText ?? restaurantName);
    return Column(
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
          const SizedBox(height: 8),
        ],
        CouponTicketCard(
          iconPath: MasterContent.svgOf(categoryKey),
          storeLabel: storeLabel,
          title: benefit?.resolvedTitle ?? kCouponBenefitFallbackTitle,
          subtitle: benefit?.resolvedSubtitle ?? kCouponBenefitFallbackSubtitle,
          notes: benefit?.notesText,
          expiryText: formatCouponExpiryLabel(c.expiresAt),
          expiryUrgent: isCouponExpiringSoon(c),
          showAction: false,
          margin: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// 제휴식당 상세의 스탬프 판과 같은 위젯(StampAssetGrid)·같은 도장 이미지.
  /// 선물 도장은 상세와 마찬가지로 "다음 보상 칸" 하나만 단다.
  Widget _progress() {
    final s = entry.stamp;
    final nextRewardStep = s.remaining > 0 ? s.current + s.remaining : null;
    return StampAssetGrid(
      current: s.current,
      target: s.target,
      rewardSteps: {
        if (nextRewardStep != null && nextRewardStep <= s.target)
          nextRewardStep,
      },
      alignment: WrapAlignment.center,
    );
  }

  /// 이 매장에 스탬프가 있는가. 있으면 첫 방문·쿠폰 보유 시트에서도 PIN 입력(스탬프) 버튼을 보여 준다.
  bool get _stampEnabled => entry.stamp.enabled && entry.stamp.target > 0;

  /// 쿠폰 + 스탬프 버튼. 누르면 PIN·개수 입력 창이 열린다 (서버 PIN 검증 없이는 적립되지 않는다).
  Widget _couponWithStampButtons(BuildContext context,
      {required _Btn closeBtn}) {
    return Column(
      children: [
        _column(context, [
          _Btn('쿠폰 쓰고 스탬프도 찍기', QrEntryAction.useCouponWithStamp,
              primary: true),
          _Btn('스탬프만 찍기', QrEntryAction.addStamp, outlined: true),
          closeBtn,
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

  Widget _buttons(BuildContext context) {
    switch (entry.branch) {
      case QrEntryBranch.couponArrived:
      case QrEntryBranch.couponHeld:
        // 스탬프가 있는 매장은 첫 방문에도 스탬프(PIN) 길을 연다. 예전에는 쿠폰 버튼만 있어서
        // 첫 방문 손님이 PIN 입력 화면에 갈 수 없었다.
        if (_hasCoupon && _stampEnabled) {
          return _couponWithStampButtons(
            context,
            closeBtn: _Btn('나중에 쓸게요', QrEntryAction.later),
          );
        }
        return _column(context, [
          _Btn('지금 쓰기', QrEntryAction.useCoupon, primary: true),
          _Btn('나중에 쓸게요', QrEntryAction.later),
        ]);
      case QrEntryBranch.stampProgress:
        if (_hasCoupon) {
          return _couponWithStampButtons(
            context,
            closeBtn: _Btn('매장 보기', QrEntryAction.viewStore),
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
