import 'package:flutter/material.dart';

import 'package:new1/services/coupon_service.dart';

/// 홈 기획전 세로배너 아래 "내 혜택 한 줄 요약" 카드의 표시 데이터. (시안 10)
///
/// 내 쿠폰 N장 · 오늘 만료 N · 스탬프 진행을 한 번에 보여 주려고
/// 홈이 이미 불러 둔 쿠폰·스탬프 목록에서 파생한다 (별도 API 호출 없음).
class MyBenefitSummary {
  const MyBenefitSummary({
    required this.couponCount,
    required this.couponStoreNames,
    required this.expiringTodayCount,
    required this.stamps,
  });

  final int couponCount;

  /// 쿠폰이 걸린 매장 이름 (만료가 가까운 쿠폰 순, 중복 제거).
  final List<String> couponStoreNames;

  /// 오늘 안에 만료되는 쿠폰 수.
  final int expiringTodayCount;

  /// 진행 중인 스탬프 (진행도 높은 순).
  final List<({String name, int current, int total})> stamps;

  bool get isEmpty => couponCount == 0 && stamps.isEmpty;

  static MyBenefitSummary from({
    required List<UserCoupon> coupons,
    required Map<int, StampStatus> stampStatuses,
    required String Function(int restaurantId) restaurantName,
    required DateTime now,
    int maxStamps = 2,
  }) {
    final usable =
        coupons.where((c) => c.status == CouponStatus.issued).toList()
          ..sort((a, b) {
            final ae = a.expiresAt;
            final be = b.expiresAt;
            if (ae == null && be == null) return 0;
            if (ae == null) return 1;
            if (be == null) return -1;
            return ae.compareTo(be);
          });

    final today = DateTime(now.year, now.month, now.day);
    var expiringToday = 0;
    final names = <String>[];
    for (final c in usable) {
      final exp = c.expiresAt;
      if (exp != null &&
          DateTime(exp.year, exp.month, exp.day) == today &&
          exp.isAfter(now)) {
        expiringToday++;
      }
      final name = (c.benefit?.restaurantNameText?.trim().isNotEmpty ?? false)
          ? c.benefit!.restaurantNameText!.trim()
          : (c.restaurantId != null ? restaurantName(c.restaurantId!) : '');
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }

    final stamps = stampStatuses.entries
        .where((e) => e.value.current > 0)
        .toList()
      ..sort((a, b) => b.value.current.compareTo(a.value.current));

    return MyBenefitSummary(
      couponCount: usable.length,
      couponStoreNames: names,
      expiringTodayCount: expiringToday,
      stamps: [
        for (final e in stamps.take(maxStamps))
          (
            name: restaurantName(e.key),
            current: e.value.current,
            total: e.value.boardLength > 0
                ? e.value.boardLength
                : e.value.target,
          ),
      ],
    );
  }
}

/// 내 쿠폰·오늘 만료·스탬프 진행을 한 카드에. 누르면 쿠폰함으로 간다.
class MyBenefitSummaryCard extends StatelessWidget {
  const MyBenefitSummaryCard({
    super.key,
    required this.summary,
    this.onTap,
  });

  final MyBenefitSummary summary;
  final VoidCallback? onTap;

  static const Color _ink = Color(0xFF1B1D24);
  static const Color _sub = Color(0xFF7C8090);
  static const Color _primary = Color(0xFF5146E5);
  static const Color _lav = Color(0xFFEEEDFC);
  static const Color _red = Color(0xFFE5484D);
  static const Color _redBg = Color(0xFFFDECEC);

  @override
  Widget build(BuildContext context) {
    final names = summary.couponStoreNames;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: _lav,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: '내 쿠폰 ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                                TextSpan(
                                  text: '${summary.couponCount}장',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: _primary,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontFamily: 'Pretendard'),
                          ),
                          if (names.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              names.take(3).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    if (summary.expiringTodayCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _redBg,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '오늘 만료 ${summary.expiringTodayCount}',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _red,
                          ),
                        ),
                      ),
                  ],
                ),
                if (summary.stamps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        '스탬프',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          [
                            for (final s in summary.stamps)
                              '${s.name} ${s.current}/${s.total}',
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _sub,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
