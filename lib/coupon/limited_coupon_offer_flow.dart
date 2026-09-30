import 'package:flutter/material.dart';

import 'package:new1/coupon/limited_coupon_pick_sheet.dart';
import 'package:new1/data/campus_options.dart';
import 'package:new1/onboarding/onboarding_style.dart';
import 'package:new1/profile_setup_screen.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/user_service.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';

/// 기간 한정 기획전 선택형 한정쿠폰 + 학생회·이벤트 코드로 받은 식당 선택권
/// + 화·목 골라받기 쿠폰(TUE_THU_GENERAL_SELECT). 앱 접속 시 자동 발급하지
/// 않고, offers에서 아직 안 받은 항목만 식당 선택 UI를 띄운다.
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
      await _presentLoop(context, onIssued: () => issuedAny = true);
    } catch (_) {
      // 오퍼 조회 실패는 앱 사용을 막지 않는다.
    } finally {
      _presenting = false;
    }
    if (issuedAny) {
      onCouponsChanged?.call();
    }
  }

  static Future<void> _presentLoop(
    BuildContext context, {
    required VoidCallback onIssued,
    int depth = 0,
  }) async {
    // 대학가 등록 후 offers를 다시 쳐서 이어가는 재귀 호출. 왕복이 반복되는
    // 상황을 막기 위해 한 번만 재시도한다.
    if (depth > 1) return;
    final offers = await CouponService.fetchLimitedOffers();
    if (!context.mounted) return;
    for (final offer in offers) {
      if (offer.needsCampusRegistration) {
        if (!context.mounted) return;
        final registered = await _presentCampusRequiredPrompt(context, offer);
        if (registered) {
          return _presentLoop(context, onIssued: onIssued, depth: depth + 1);
        }
        continue;
      }
      if (!offer.needsSelection) continue;
      if (!context.mounted) return;
      final result = await showLimitedCouponPickSheet(
        context,
        offer: offer,
      );
      if (result?.claimed != true) continue;
      onIssued();
      if (!context.mounted) continue;
      // 미션 완주와 같은 선물상자 팝업. 선택 화면을 닫은 뒤에만 띄운다.
      await showCouponIssuedDialog(
        context,
        tag: offer.tagLabel,
        title: (result!.title != null && result.title!.isNotEmpty)
            ? result.title!
            : '${offer.tagLabel}을 받았어요',
        issuedCodes: result.issuedCodes,
      );
    }
  }

  /// 대학가 미등록으로 후보 식당이 비어 있는 오퍼용 안내. 쿠폰 선택 화면을
  /// 벗어나지 않고 바텀시트에서 바로 대학가를 골라 등록한다. 등록되면
  /// true를 반환해 offers를 다시 치게 한다.
  static Future<bool> _presentCampusRequiredPrompt(
    BuildContext context,
    LimitedCouponOffer offer,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CampusRegisterSheet(),
    );
    return saved == true;
  }
}

/// 화·목 골라받기 쿠폰처럼 campus_required인 오퍼용 대학가 등록 바텀시트.
/// 쿠폰 선택 화면 밖으로 나가지 않고 여기서 바로 고르고 저장한다.
class _CampusRegisterSheet extends StatefulWidget {
  const _CampusRegisterSheet();

  @override
  State<_CampusRegisterSheet> createState() => _CampusRegisterSheetState();
}

class _CampusRegisterSheetState extends State<_CampusRegisterSheet> {
  String? _selected;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final campus = _selected;
    if (campus == null) {
      setState(() => _error = '대학가를 선택해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await UserService.fetchCurrentUserProfile();
      final nickname = profile?['nickname']?.toString().trim() ?? '';
      if (nickname.isEmpty) {
        // 닉네임이 없는 드문 경우(가입 미완료 등)만 전체 프로필 설정으로 보낸다.
        if (!mounted) return;
        final result =
            await Navigator.of(context, rootNavigator: true).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => ProfileSetupScreen(
              initialProfile: profile,
              isRequiredFlow: false,
            ),
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop(result == true);
        return;
      }
      await UserService.updateCurrentUserProfile(
        nickname: nickname,
        campus: campus,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '등록하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '대학가를 등록해 주세요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: OnboardingStyle.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '대학가를 등록하면 근처 식당 쿠폰을 받을 수 있어요',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: OnboardingStyle.body,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final campus in kCampusOptions)
                    ChoiceChip(
                      label: Text(campus),
                      selected: _selected == campus,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                                _selected = campus;
                                _error = null;
                              }),
                      selectedColor: OnboardingStyle.accentSoft,
                      labelStyle: TextStyle(
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w700,
                        color: _selected == campus
                            ? OnboardingStyle.primary
                            : OnboardingStyle.body,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: _selected == campus
                              ? OnboardingStyle.primary
                              : OnboardingStyle.line,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      showCheckmark: false,
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OnboardingStyle.danger,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                style: OnboardingStyle.primaryButton(
                  enabled: !_saving && _selected != null,
                ),
                onPressed: _saving || _selected == null ? null : _save,
                child: Text(_saving ? '등록 중…' : '등록하고 계속하기'),
              ),
              Center(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: OnboardingStyle.muted,
                    textStyle: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('다음에'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
