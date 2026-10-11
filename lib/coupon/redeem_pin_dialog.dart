import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/coupon/store_select_field.dart';
import 'package:new1/services/affiliate_service.dart'
    show AffiliateRestaurantSummary;
import 'package:new1/services/app_config_service.dart';
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
    this.bonusCoupon,
  });

  final bool redeemed;
  final int restaurantId;
  final bool addStampRequested;
  final int stampCount;
  final StampActionResult? stampResult;
  final String? stampError;
  final UserCoupon? bonusCoupon;
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
  String fromScreen = 'unknown',
  bool initialAddStamp = false,
}) {
  // 사용 화면 진입. 홈·쿠폰함·제휴 세 지점이 지금까지 구분되지 않아
  // 어느 경로에서 쿠폰을 꺼내 쓰는지 알 수 없었다.
  AnalyticsLogger.logEvent(
    AnalyticsEvents.couponUseScreenView,
    parameters: {
      AnalyticsEvents.paramCouponCode: coupon.code,
      if (restaurantId != null) AnalyticsEvents.paramRestaurantId: restaurantId,
      AnalyticsEvents.paramFromScreen: fromScreen,
      AnalyticsEvents.paramCouponIssueSource:
          couponIssueSource ?? coupon.couponIssueSource,
      AnalyticsEvents.paramExpiryState: _expiryState(coupon),
    },
  );
  // 작은 팝업이 아니라 직원에게 그대로 보여주는 전체 화면으로 연다.
  return Navigator.of(context, rootNavigator: true).push<CouponRedeemOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _RedeemPinDialog(
        coupon: coupon,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        notes: notes,
        couponIssueSource: couponIssueSource,
        fromScreen: fromScreen,
        initialAddStamp: initialAddStamp,
      ),
    ),
  );
}

/// 만료 임박 여부. 남은 기간이 짧을수록 사용 전환이 급해지므로
/// 사용 화면 진입을 이 축으로 나눠 본다.
String _expiryState(UserCoupon coupon) {
  final exp = coupon.expiresAt;
  if (exp == null) return 'unknown';
  final now = AppConfigService.now();
  final days = DateTime(exp.year, exp.month, exp.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days < 0) return 'expired';
  return days <= 3 ? 'soon' : 'normal';
}

class _RedeemPinDialog extends StatefulWidget {
  const _RedeemPinDialog({
    required this.coupon,
    this.restaurantId,
    this.restaurantName,
    this.notes,
    this.couponIssueSource,
    this.fromScreen = 'unknown',
    this.initialAddStamp = false,
  });

  /// QR 재방문에서 "쿠폰 쓰고 스탬프도 찍기"로 들어왔을 때 스탬프 적립을 미리 켠다.
  final bool initialAddStamp;

  final UserCoupon coupon;
  final int? restaurantId;
  final String? restaurantName;
  final String? notes;
  final String? couponIssueSource;
  final String fromScreen;

  @override
  State<_RedeemPinDialog> createState() => _RedeemPinDialogState();
}

enum _RedeemPhase { input, done }

class _RedeemPinDialogState extends State<_RedeemPinDialog> {
  static const Color _primary = Color(0xFF5146E5);
  static const Color _lav = Color(0xFFEEEDFC);
  static const Color _bg = Color(0xFFF6F6FA);
  static const Color _ink = Color(0xFF1B1D24);
  static const Color _sub = Color(0xFF7C8090);
  static const Color _line = Color(0xFFECECF3);
  static const Color _red = Color(0xFFE5484D);
  static const Color _redBg = Color(0xFFFDECEC);

  String _pin = '';
  // 쿠폰 사용 자체가 이미 마일리지(COUPON_USE)를 적립하므로, 기본값을 꺼 둬서
  // 스탬프 적립(STAMP_VISIT)까지 얹혀 100+100=200으로 이중 적립되지 않게 한다.
  // 점주가 방문 스탬프도 별도로 인정해 줄 때만 명시적으로 켜서 쓴다. (10/2 결정 7)
  bool _addStamp = false;
  int _stampCount = 1;
  String? _error;
  int? _attemptsLeft;
  bool _locked = false;
  bool _isLoading = false;
  AffiliateRestaurantSummary? _pickedStore;

  // 사용 완료 단계: 쿠폰은 이미 사용됐고, "스탬프도 찍을까요?"를 묻는다.
  // 직원이 방금 입력한 PIN을 이 화면 안에서만 잠깐 들고 있다가 적립에 한 번 쓰고 버린다.
  _RedeemPhase _phase = _RedeemPhase.input;
  String? _usedPin;
  int? _doneRestaurantId;
  UserCoupon? _doneBonusCoupon;
  DateTime? _doneAt;
  bool _stampBusy = false;
  String? _stampPromptError;

  @override
  void initState() {
    super.initState();
    _addStamp = widget.initialAddStamp;
  }

  bool get _needsStorePick => widget.restaurantId == null;
  int get _pinLength => AppConfigService.pinLength;

  String? get _storeName =>
      _pickedStore?.name ??
      widget.restaurantName ??
      widget.coupon.benefit?.restaurantNameText;

  String get _title => widget.coupon.benefit?.resolvedTitle ?? '할인 쿠폰';

  String? get _subtitle {
    final s = widget.coupon.benefit?.resolvedSubtitle;
    return (s != null && s.isNotEmpty) ? s : null;
  }

  ({String text, bool urgent})? get _dday {
    final exp = widget.coupon.expiresAt;
    if (exp == null) return null;
    final now = AppConfigService.now();
    final days = DateTime(exp.year, exp.month, exp.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) return (text: '기한이 지났어요', urgent: true);
    if (days == 0) {
      return (text: '오늘 ${_two(exp.hour)}:${_two(exp.minute)}까지', urgent: true);
    }
    return (text: 'D-$days', urgent: days <= 3);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  void _onDigit(String d) {
    if (_isLoading || _locked || _pin.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == _pinLength) _submit();
  }

  void _onBackspace() {
    if (_isLoading || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _submit() async {
    final targetId = widget.restaurantId ?? _pickedStore?.id;
    if (targetId == null) {
      setState(() {
        _error = '사용할 매장을 먼저 선택해 주세요.';
        _pin = '';
      });
      return;
    }
    final pin = _pin;
    if (pin.length != _pinLength) {
      setState(() => _error = 'PIN은 $_pinLength자리 숫자여야 합니다.');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    AnalyticsLogger.logEvent(
      AnalyticsEvents.couponRedeemAttempt,
      parameters: {
        AnalyticsEvents.paramFromScreen: widget.fromScreen,
        AnalyticsEvents.paramCouponCode: widget.coupon.code,
        AnalyticsEvents.paramRestaurantId: targetId,
        AnalyticsEvents.paramCouponIssueSource:
            widget.couponIssueSource ?? widget.coupon.couponIssueSource,
        AnalyticsEvents.paramWithStamp: _addStamp ? 1 : 0,
      },
    );

    final redeem = await CouponService.redeemCouponWithoutThrow(
      couponCode: widget.coupon.code,
      restaurantId: targetId,
      pin: pin,
    );
    if (!mounted) return;
    if (!redeem.isSuccess) {
      AnalyticsLogger.logEvent(
        AnalyticsEvents.couponRedeemFailed,
        parameters: {
          AnalyticsEvents.paramFromScreen: widget.fromScreen,
          AnalyticsEvents.paramCouponCode: widget.coupon.code,
          AnalyticsEvents.paramRestaurantId: targetId,
          AnalyticsEvents.paramFailReason: redeem.failReason ?? 'unknown',
        },
      );
      setState(() {
        _error = redeem.errorMessage ?? 'PIN이 올바르지 않아요. 다시 확인해 주세요.';
        _attemptsLeft = redeem.attemptsLeft;
        _locked = redeem.locked;
        _pin = '';
        _isLoading = false;
      });
      return;
    }

    AnalyticsLogger.logEvent(
      AnalyticsEvents.couponRedeemed,
      parameters: {
        AnalyticsEvents.paramFromScreen: widget.fromScreen,
        AnalyticsEvents.paramCouponCode: widget.coupon.code,
        AnalyticsEvents.paramRestaurantId: targetId,
        AnalyticsEvents.paramRestaurantName: _storeName ?? '',
        AnalyticsEvents.paramCouponIssueSource:
            widget.couponIssueSource ?? widget.coupon.couponIssueSource,
      },
    );

    // 스탬프 체크 없이 쓴 경우: 바로 닫지 않고 "스탬프도 찍을까요?"로 이어 준다.
    if (!_addStamp) {
      setState(() {
        _phase = _RedeemPhase.done;
        _usedPin = pin;
        _doneRestaurantId = targetId;
        _doneBonusCoupon = redeem.result?.bonusCoupon;
        _doneAt = DateTime.now();
        _isLoading = false;
        _pin = '';
      });
      return;
    }

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
            AnalyticsEvents.paramRestaurantName: _storeName ?? '',
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
        bonusCoupon: redeem.result?.bonusCoupon,
      ),
    );
  }

  CouponRedeemOutcome _doneOutcome({
    StampActionResult? stampResult,
    String? stampError,
    bool stampRequested = false,
  }) =>
      CouponRedeemOutcome(
        redeemed: true,
        restaurantId: _doneRestaurantId ?? widget.restaurantId ?? 0,
        addStampRequested: stampRequested,
        stampCount: _stampCount,
        stampResult: stampResult,
        stampError: stampError,
        bonusCoupon: _doneBonusCoupon,
      );

  /// "괜찮아요" / 닫기. 쿠폰은 이미 사용됐으므로 취소(null)가 아니라 사용 결과를 돌려준다.
  void _doneSkip() {
    if (_stampBusy) return;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.couponDoneStampPrompt,
      parameters: {
        AnalyticsEvents.paramCouponCode: widget.coupon.code,
        AnalyticsEvents.paramAction: 'skip',
      },
    );
    _usedPin = null;
    Navigator.of(context).pop(_doneOutcome());
  }

  Future<void> _doneAddStamp() async {
    final pin = _usedPin;
    final targetId = _doneRestaurantId;
    if (pin == null || targetId == null || _stampBusy) return;
    setState(() {
      _stampBusy = true;
      _stampPromptError = null;
    });
    AnalyticsLogger.logEvent(
      AnalyticsEvents.couponDoneStampPrompt,
      parameters: {
        AnalyticsEvents.paramCouponCode: widget.coupon.code,
        AnalyticsEvents.paramAction: 'add_stamp',
      },
    );
    final stamp = await CouponService.addStamp(
      restaurantId: targetId,
      pin: pin,
      count: _stampCount,
    );
    if (!mounted) return;
    if (!stamp.isSuccess) {
      setState(() {
        _stampBusy = false;
        _stampPromptError = stamp.errorMessage ?? '스탬프를 적립하지 못했어요.';
      });
      return;
    }
    final result = stamp.result;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.stampIssued,
      parameters: {
        AnalyticsEvents.paramRestaurantId: targetId,
        AnalyticsEvents.paramRestaurantName: _storeName ?? '',
        AnalyticsEvents.paramStampCountAfter: result?.current ?? 0,
        AnalyticsEvents.paramStampAddedCount: result?.added ?? _stampCount,
      },
    );
    _usedPin = null;
    Navigator.of(context).pop(
      _doneOutcome(stampResult: result, stampRequested: true),
    );
  }

  Widget _buildDone() {
    final points = AppConfigService.mileageCouponUsePoints;
    final at = _doneAt ?? DateTime.now();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final max = AppConfigService.stampMaxPerScan;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _ink),
          onPressed: _stampBusy ? null : _doneSkip,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 18),
              const Text(
                '사용 완료!',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (_storeName != null && _storeName!.isNotEmpty) _storeName!,
                  _title,
                  time,
                ].join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: _sub,
                ),
              ),
              if (points > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _lav,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '+${points}M 적립',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _primary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      '스탬프도 찍을까요?',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '방금 입력한 PIN으로 바로 적립돼요',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _sub,
                      ),
                    ),
                    if (max > 1) ...[
                      const SizedBox(height: 14),
                      const Text(
                        '몇 명이 함께 결제했나요?',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _sub,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(max, (i) {
                          final n = i + 1;
                          final selected = n == _stampCount;
                          return Expanded(
                            child: Padding(
                              padding:
                                  EdgeInsets.only(right: i == max - 1 ? 0 : 8),
                              child: GestureDetector(
                                onTap: _stampBusy
                                    ? null
                                    : () => setState(() => _stampCount = n),
                                child: Container(
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected ? _primary : _lav,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$n명',
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: selected ? Colors.white : _ink,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                    if (_stampPromptError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _stampPromptError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _stampBusy ? null : _doneAddStamp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFC7C3F5),
                          minimumSize: const Size.fromHeight(50),
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
                        child: _stampBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('스탬프 찍기'),
                      ),
                    ),
                    TextButton(
                      onPressed: _stampBusy ? null : _doneSkip,
                      child: const Text(
                        '괜찮아요',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _sub,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _RedeemPhase.done) {
      // 쿠폰은 이미 사용됐으니 뒤로가기도 "취소"가 아니라 "스탬프는 괜찮아요"로 처리한다.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _doneSkip();
        },
        child: _buildDone(),
      );
    }
    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: _bg,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: _ink),
            onPressed:
                _isLoading ? null : () => Navigator.of(context).maybePop(),
          ),
          title: const Text(
            '쿠폰 사용',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    _ticket(),
                    if (_needsStorePick) ...[
                      const SizedBox(height: 14),
                      StoreSelectField(
                        selected: _pickedStore,
                        enabled: !_isLoading,
                        onSelected: (store) => setState(() {
                          _pickedStore = store;
                          _error = null;
                        }),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _stampSection(),
                    if (widget.notes != null && widget.notes!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _notesBox(widget.notes!),
                    ],
                  ],
                ),
              ),
            ),
            _keypad(),
          ],
        ),
      ),
    );
  }

  Widget _ticket() {
    final dday = _dday;
    final storeName = _storeName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _ink.withOpacity(0.10),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          if (storeName != null && storeName.isNotEmpty)
            Text(
              storeName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _sub,
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
              letterSpacing: -0.8,
              color: _ink,
            ),
          ),
          if (_subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              _subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _sub,
              ),
            ),
          ],
          if (dday != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: dday.urgent ? _redBg : _lav,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                dday.text,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: dday.urgent ? _red : _primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const _DashedDivider(),
          const SizedBox(height: 14),
          const Text(
            '직원에게 이 화면을 보여주세요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '매장 PIN',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _sub,
            ),
          ),
          const SizedBox(height: 8),
          _pinBoxes(),
          const SizedBox(height: 8),
          _statusLine(),
        ],
      ),
    );
  }

  Widget _pinBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinLength, (i) {
        final filled = i < _pin.length;
        final active = i == _pin.length && !_isLoading && !_locked;
        return Container(
          width: 44,
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? _lav : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _error != null
                  ? _red
                  : (filled || active ? _primary : const Color(0xFFDADBE4)),
              width: 1.5,
            ),
          ),
          child: filled
              ? const Text(
                  '•',
                  style: TextStyle(fontSize: 26, height: 1, color: _ink),
                )
              : null,
        );
      }),
    );
  }

  /// PIN 입력창 아래 한 줄: 처리 중 · 오류 · 잠금 경고 · 도움말 중 하나만 보여준다.
  Widget _statusLine() {
    if (_isLoading) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
      );
    }
    if (_error != null) {
      final warn = !_locked && _attemptsLeft != null && _attemptsLeft! <= 2;
      return Column(
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _red,
            ),
          ),
          if (warn && _attemptsLeft! > 0) ...[
            const SizedBox(height: 4),
            Text(
              '$_attemptsLeft번 더 틀리면 10분간 멈춰요 · 쿠폰은 그대로 있어요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _sub,
              ),
            ),
          ],
        ],
      );
    }
    return const Text(
      'PIN은 계산대 안내문에 있어요',
      style: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: _sub,
      ),
    );
  }

  Widget _stampSection() {
    final max = AppConfigService.stampMaxPerScan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      decoration: BoxDecoration(
        color: _lav,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '스탬프도 함께 적립',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _addStamp,
                activeTrackColor: _primary,
                onChanged:
                    _isLoading ? null : (v) => setState(() => _addStamp = v),
              ),
            ],
          ),
          if (_addStamp) ...[
            const Text(
              '몇 명이 함께 결제했나요?',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _sub,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(max, (i) {
                final n = i + 1;
                final selected = n == _stampCount;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == max - 1 ? 4 : 8),
                    child: GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () => setState(() => _stampCount = n),
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? _primary : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$n명',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : _ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              '스탬프 $_stampCount개가 함께 적립돼요.',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _primary,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _notesBox(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '사용 조건',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _sub,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            notes,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  /// 시스템 키보드 대신 화면 하단 숫자 패드. 계산대에서 직원이 바로 누른다.
  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    final disabled = _isLoading || _locked;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        18,
        6,
        18,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.6,
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          final isBack = k == '⌫';
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap:
                disabled ? null : (isBack ? _onBackspace : () => _onDigit(k)),
            child: Center(
              child: isBack
                  ? Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color: disabled ? _line : _ink,
                    )
                  : Text(
                      k,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: disabled ? _line : _ink,
                      ),
                    ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashW = 6.0;
        const gap = 5.0;
        final count = (constraints.maxWidth / (dashW + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dashW,
              height: 1.5,
              color: const Color(0xFFD9DAE4),
            ),
          ),
        );
      },
    );
  }
}
