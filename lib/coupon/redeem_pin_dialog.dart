import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/coupon/store_select_field.dart';
import 'package:new1/services/affiliate_service.dart'
    show AffiliateRestaurantSummary;
import 'package:new1/services/coupon_service.dart';
import 'package:new1/utils/analytics_logger.dart';

/// 쿠폰 사용 PIN 팝업 결과. 취소하면 null.
class CouponRedeemOutcome {
  const CouponRedeemOutcome({
    required this.redeemed,
    required this.restaurantId,
    this.addStampRequested = false,
    this.stampCount = 1,
    this.stampResult,
    this.stampError,
  });

  final bool redeemed;
  final int restaurantId;
  final bool addStampRequested;
  final int stampCount;
  final StampActionResult? stampResult;
  final String? stampError;
}

/// 쿠폰 사용 확인 + (기본 선택) 스탬프 동시 적립.
/// 적립 개수 UI는 스탬프만 적립하는 팝업과 같다.
Future<CouponRedeemOutcome?> showCouponRedeemPinDialog({
  required BuildContext context,
  required UserCoupon coupon,
  int? restaurantId,
  String? restaurantName,
  String? notes,
  String? couponIssueSource,
}) {
  return showDialog<CouponRedeemOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RedeemPinDialog(
      coupon: coupon,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      notes: notes,
      couponIssueSource: couponIssueSource,
    ),
  );
}

class _RedeemPinDialog extends StatefulWidget {
  const _RedeemPinDialog({
    required this.coupon,
    this.restaurantId,
    this.restaurantName,
    this.notes,
    this.couponIssueSource,
  });

  final UserCoupon coupon;
  final int? restaurantId;
  final String? restaurantName;
  final String? notes;
  final String? couponIssueSource;

  @override
  State<_RedeemPinDialog> createState() => _RedeemPinDialogState();
}

class _RedeemPinDialogState extends State<_RedeemPinDialog> {
  final TextEditingController _pin = TextEditingController();
  bool _addStamp = true;
  int _stampCount = 1;
  String? _error;
  bool _isLoading = false;
  AffiliateRestaurantSummary? _pickedStore;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  bool get _needsStorePick => widget.restaurantId == null;

  Future<void> _submit() async {
    final targetId = widget.restaurantId ?? _pickedStore?.id;
    if (targetId == null) {
      setState(() => _error = '사용할 매장을 먼저 선택해 주세요.');
      return;
    }
    final pin = _pin.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'PIN은 4자리 숫자여야 합니다.');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    final redeem = await CouponService.redeemCouponWithoutThrow(
      couponCode: widget.coupon.code,
      restaurantId: targetId,
      pin: pin,
    );
    if (!mounted) return;
    if (!redeem.isSuccess) {
      setState(() {
        _error = redeem.errorMessage ?? '비밀번호가 올바르지 않아요. 다시 확인해 주세요.';
        _isLoading = false;
      });
      return;
    }

    AnalyticsLogger.logEvent(
      AnalyticsEvents.couponRedeemed,
      parameters: {
        AnalyticsEvents.paramCouponCode: widget.coupon.code,
        AnalyticsEvents.paramRestaurantId: targetId,
        AnalyticsEvents.paramRestaurantName:
            _pickedStore?.name ?? widget.restaurantName ?? '',
        AnalyticsEvents.paramCouponIssueSource:
            widget.couponIssueSource ?? widget.coupon.couponIssueSource,
      },
    );

    StampActionResult? stampResult;
    String? stampError;
    if (_addStamp) {
      final stamp = await CouponService.addStamp(
        restaurantId: targetId,
        pin: pin,
        count: _stampCount,
      );
      if (stamp.isSuccess) {
        stampResult = stamp.result;
        final added = stampResult?.added ?? _stampCount;
        AnalyticsLogger.logEvent(
          AnalyticsEvents.stampIssued,
          parameters: {
            AnalyticsEvents.paramRestaurantId: targetId,
            AnalyticsEvents.paramRestaurantName:
                _pickedStore?.name ?? widget.restaurantName ?? '',
            AnalyticsEvents.paramStampCountAfter: stampResult?.current ?? 0,
            AnalyticsEvents.paramStampAddedCount: added,
          },
        );
      } else {
        stampError = stamp.errorMessage ?? '스탬프를 적립하지 못했어요.';
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      CouponRedeemOutcome(
        redeemed: true,
        restaurantId: targetId,
        addStampRequested: _addStamp,
        stampCount: _stampCount,
        stampResult: stampResult,
        stampError: stampError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final hasNotes = notes != null && notes.isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: ShapeDecoration(
            color: const Color(0xFFF2F2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '쿠폰 사용',
                  style: TextStyle(
                    color: Color(0xFF39393E),
                    fontSize: 19,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w800,
                    height: 1.21,
                  ),
                ),
                const SizedBox(height: 16),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '해당 쿠폰을 사용처리 하시겠습니까?\n관리자 비밀번호를 입력하시면',
                        style: TextStyle(
                          color: Color(0xFF39393E),
                          fontSize: 15,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w500,
                          height: 1.20,
                        ),
                      ),
                      TextSpan(
                        text: ' 즉시 사용처리',
                        style: TextStyle(
                          color: Color(0xFF39393E),
                          fontSize: 15,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w800,
                          height: 1.20,
                        ),
                      ),
                      TextSpan(
                        text: ' 됩니다.',
                        style: TextStyle(
                          color: Color(0xFF39393E),
                          fontSize: 15,
                          fontFamily: 'Pretendard',
                          fontWeight: FontWeight.w500,
                          height: 1.20,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasNotes) ...[
                  const SizedBox(height: 16),
                  _notesBox(notes),
                ],
                if (_needsStorePick) ...[
                  const SizedBox(height: 20),
                  StoreSelectField(
                    selected: _pickedStore,
                    enabled: !_isLoading,
                    onSelected: (store) => setState(() {
                      _pickedStore = store;
                      _error = null;
                    }),
                  ),
                ],
                const SizedBox(height: 18),
                _stampCheckbox(),
                if (_addStamp) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '적립 개수',
                    style: TextStyle(
                      color: Color(0xFF797979),
                      fontSize: 15,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _stampCountDropdown(),
                  const SizedBox(height: 8),
                  Text(
                    '스탬프 $_stampCount개가 함께 적립됩니다.',
                    style: const TextStyle(
                      color: Color(0xFF797979),
                      fontSize: 13,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  '비밀번호',
                  style: TextStyle(
                    color: Color(0xFF797979),
                    fontSize: 15,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                _pinField(),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: const Color(0xFF39393E),
                          side: const BorderSide(color: Color(0xFFBABAC0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C203C),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFD9D9D9),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.32,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_addStamp ? '사용하고 적립' : '사용하기'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stampCheckbox() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _isLoading
            ? null
            : () => setState(() => _addStamp = !_addStamp),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(
                value: _addStamp,
                onChanged: _isLoading
                    ? null
                    : (value) => setState(() => _addStamp = value ?? true),
                activeColor: const Color(0xFF1C203C),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Expanded(
                child: Text(
                  '스탬프도 함께 적립',
                  style: TextStyle(
                    color: Color(0xFF39393E),
                    fontSize: 15,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stampCountDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 2, color: Color(0xFFD9D9D9)),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _stampCount,
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          dropdownColor: Colors.white,
          style: const TextStyle(
            color: Color(0xFF39393E),
            fontSize: 16,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
          ),
          items: List.generate(
            4,
            (index) => DropdownMenuItem<int>(
              value: index + 1,
              child: Text('${index + 1}개'),
            ),
          ),
          onChanged: _isLoading
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _stampCount = value);
                },
        ),
      ),
    );
  }

  Widget _pinField() {
    return Container(
      width: double.infinity,
      height: 40,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 2, color: Color(0xFFD9D9D9)),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: TextField(
        controller: _pin,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 4,
        enabled: !_isLoading,
        style: const TextStyle(
          color: Color(0xFF39393E),
          fontSize: 16,
          fontFamily: 'Pretendard',
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        onSubmitted: (_) {
          if (!_isLoading) _submit();
        },
      ),
    );
  }

  Widget _notesBox(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: const Border.fromBorderSide(
          BorderSide(color: Color(0xFFE5E5E5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사용 조건',
            style: TextStyle(
              color: Color(0xFF797979),
              fontSize: 12,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            notes,
            style: const TextStyle(
              color: Color(0xFF39393E),
              fontSize: 14,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
