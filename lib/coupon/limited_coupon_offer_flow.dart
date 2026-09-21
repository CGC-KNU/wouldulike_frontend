import 'package:flutter/material.dart';

import 'package:new1/coupon/limited_coupon_pick_sheet.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';

/// 기간 한정 기획전 선택형 한정쿠폰.
/// 앱 접속 시 자동 발급하지 않고, offers에서 아직 안 받은 항목만 식당 선택 UI를 띄운다.
class LimitedCouponOfferFlow {
  LimitedCouponOfferFlow._();

  static bool _presenting = false;

  /// 로그인 후 앱 포그라운드 복귀·쿠폰함 진입 시 호출.
  /// 여러 기획전이 열려 있으면 항목마다 선택 UI를 이어 띄운다.
  static Future<void> maybePresent(
    BuildContext context, {
    VoidCallback? onCouponsChanged,
  }) async {
    if (_presenting) return;
    _presenting = true;
    var issuedAny = false;
    try {
      if (!await ApiClient.hasAccessToken()) return;
      final offers = await CouponService.fetchLimitedOffers();
      if (!context.mounted) return;
      for (final offer in offers) {
        if (!offer.needsSelection) continue;
        if (!context.mounted) return;
        final result = await showLimitedCouponPickSheet(
          context,
          offer: offer,
        );
        if (result?.claimed != true) continue;
        issuedAny = true;
        if (!context.mounted) continue;
        // 미션 완주와 같은 선물상자 팝업. 선택 화면을 닫은 뒤에만 띄운다.
        await showCouponIssuedDialog(
          context,
          tag: '한정쿠폰',
          title: (result!.title != null && result.title!.isNotEmpty)
              ? result.title!
              : '한정쿠폰을 받았어요',
          issuedCodes: result.issuedCodes,
        );
      }
    } catch (_) {
      // 오퍼 조회 실패는 앱 사용을 막지 않는다.
    } finally {
      _presenting = false;
    }
    if (issuedAny) {
      onCouponsChanged?.call();
    }
  }
}

/// 사용 성공 응답의 bonus_coupon 안내. 선택 UI는 띄우지 않는다.
Future<void> presentLimitedBonusIfAny(
  BuildContext context,
  UserCoupon? bonusCoupon, {
  VoidCallback? onCouponsChanged,
}) async {
  if (bonusCoupon == null || bonusCoupon.code.isEmpty) return;
  onCouponsChanged?.call();
  if (!context.mounted) return;
  await showCouponIssuedDialog(
    context,
    tag: '한정쿠폰 보너스',
    title: '한정쿠폰이 하나 더 지급됐어요',
    coupon: bonusCoupon,
    issuedCodes: [bonusCoupon.code],
  );
}
