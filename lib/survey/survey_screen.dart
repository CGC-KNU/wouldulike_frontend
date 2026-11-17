import 'package:flutter/material.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/coupon/limited_coupon_offer_flow.dart';
import 'package:new1/coupon/limited_coupon_pick_sheet.dart';
import 'package:new1/onboarding/onboarding_style.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/services/survey_service.dart';
import 'package:new1/utils/analytics_logger.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';
import 'package:new1/widgets/coupon_ticket_card.dart';

/// 쿠폰까지 받고 설문을 끝냈을 때 화면이 돌려주는 값. 발급 팝업은 설문 화면을 닫은 뒤 띄운다.
class SurveyOutcome {
  const SurveyOutcome({required this.tag, required this.title, required this.issuedCodes});

  final String tag;
  final String title;
  final List<String> issuedCodes;
}

/// 앱 내 설문 화면 (목업 ④~⑦·⑩~⑫, 11/8 결정 반영).
///
/// 온보딩 첫 화면(onboarding_intro_screen.dart) 틀을 그대로 쓴다: 오른쪽 위 글자 버튼,
/// 28pt 제목, 쿠폰 카드 그림, 아래 버튼. 선택지는 식당 고르기 목록(RestaurantPickList) 항목 모양.
///
/// 11/8: 답은 화면에만 들고 있다가 쿠폰을 고르는 순간 쿠폰과 같이 저장한다.
/// 중간에 닫거나 쿠폰 고르기에서 나가면 아무것도 남지 않고, 다음에 처음부터 다시 답한다.
/// 로그인은 기존 방식 그대로 먼저 한다 — 설문 링크도 로그인 뒤 메인이 연다.
/// 로그인 안 한 채로 이 화면에 오면 안내만 보인다.
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key, required this.code, required this.entry});

  final String code;

  /// push · home_promo · home_featured · wallet_card · deeplink
  final String entry;

  /// 설문을 열고, 쿠폰까지 받았으면 닫은 뒤 발급 팝업을 띄운다.
  static Future<void> open(
    BuildContext context, {
    required String code,
    required String entry,
    VoidCallback? onCouponsChanged,
  }) async {
    final outcome = await Navigator.of(context).push<SurveyOutcome>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'survey'),
        builder: (_) => SurveyScreen(code: code, entry: entry),
      ),
    );
    if (outcome == null) return;
    onCouponsChanged?.call();
    if (!context.mounted) return;
    await showCouponIssuedDialog(
      context,
      tag: outcome.tag,
      title: outcome.title,
      issuedCodes: outcome.issuedCodes,
    );
  }

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

enum _Phase { loading, start, question, claiming, done, closed, notice, error }

// 온보딩 첫 화면 헤드라인과 같은 값
const TextStyle _headline = TextStyle(
  fontFamily: 'Pretendard',
  fontSize: 28,
  fontWeight: FontWeight.w800,
  height: 1.35,
  letterSpacing: -0.6,
  color: OnboardingStyle.ink,
);

class _SurveyScreenState extends State<SurveyScreen> {
  _Phase _phase = _Phase.loading;
  SurveyDetail? _detail;
  int _step = 0;
  late List<String?> _answers = const [];
  bool _submitting = false;
  String? _error;
  final DateTime _openedAt = DateTime.now();

  /// _Phase.notice 문구 (대상 아님·고를 식당 없음)
  String _noticeTitle = '';
  String _noticeBody = '';

  @override
  void initState() {
    super.initState();
    AnalyticsLogger.logScreen('survey');
    AnalyticsLogger.logEvent(
      AnalyticsEvents.surveyView,
      parameters: {'survey_code': widget.code, 'entry': widget.entry},
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    if (!await ApiClient.hasAccessToken()) {
      if (!mounted) return;
      setState(() {
        _noticeTitle = '로그인하면\n설문에 참여할 수 있어요';
        _noticeBody = '로그인한 뒤 다시 열어 주세요.';
        _phase = _Phase.notice;
      });
      return;
    }
    try {
      final detail = await SurveyService.fetchDetail(widget.code);
      if (!mounted) return;
      if (detail == null) {
        setState(() => _phase = _Phase.error);
        return;
      }
      setState(() {
        _detail = detail;
        _answers = List<String?>.filled(detail.questions.length, null);
        switch (detail.status) {
          case SurveyStatus.open:
            _phase = _Phase.start;
          case SurveyStatus.claimed:
            _phase = _Phase.done;
          case SurveyStatus.closed:
            _phase = _Phase.closed;
          case SurveyStatus.ineligible:
            _showIneligible();
          case SurveyStatus.unknown:
            _phase = _Phase.error;
        }
      });
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() => _phase = e.statusCode == 404 ? _Phase.closed : _Phase.error);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  void _showIneligible() {
    _noticeTitle = '지금은 참여할 수\n없는 설문이에요';
    _noticeBody = '이번 설문은 경북대 근처 사용자만 참여할 수 있어요.';
    _phase = _Phase.notice;
  }

  void _close() => Navigator.of(context).pop();

  void _begin() {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.surveyStart,
      parameters: {'survey_code': widget.code, 'entry': widget.entry},
    );
    setState(() {
      _step = 0;
      _phase = _Phase.question;
    });
  }

  Map<String, String> get _answerMap {
    final d = _detail!;
    return {
      for (var i = 0; i < d.questions.length; i++)
        if (_answers[i] != null) d.questions[i].code: _answers[i]!,
    };
  }

  Future<void> _next() async {
    final detail = _detail;
    if (detail == null || _submitting || _answers[_step] == null) return;
    if (_step < detail.questions.length - 1) {
      setState(() => _step++);
      return;
    }
    // 마지막 문항 — 답은 아직 보내지 않는다. 쿠폰을 고를 때 같이 저장한다.
    AnalyticsLogger.logEvent(
      AnalyticsEvents.surveySubmit,
      parameters: {'survey_code': widget.code, 'entry': widget.entry, ..._answerMap},
    );
    await _pickCoupon();
  }

  /// 보상 오퍼를 받아 쿠폰 고르기를 띄운다. 고르면 답과 쿠폰이 같이 저장되고,
  /// 그냥 나가면 설문 화면도 닫는다(답 초기화).
  Future<void> _pickCoupon({int depth = 0}) async {
    setState(() {
      _phase = _Phase.claiming;
      _error = null;
    });
    final reward = await SurveyService.fetchReward(widget.code);
    if (!mounted) return;
    if (reward.code == 'ineligible') {
      setState(_showIneligible);
      return;
    }
    if (reward.code == 'closed') {
      setState(() => _phase = _Phase.closed);
      return;
    }
    if (reward.status == SurveyStatus.claimed) {
      // 로그인한 계정이 이미 참여했다
      setState(() => _phase = _Phase.done);
      return;
    }
    final offer = reward.offer;
    if (offer == null) {
      setState(() {
        _phase = _Phase.question;
        _error = reward.message ?? '쿠폰을 불러오지 못했어요. 다시 시도해 주세요.';
      });
      return;
    }
    if (offer.needsCampusRegistration) {
      if (depth > 0) return _close();
      final registered = await LimitedCouponOfferFlow.presentCampusRequiredPrompt(context);
      if (!mounted) return;
      if (!registered) return _close();
      return _pickCoupon(depth: depth + 1);
    }
    if (offer.restaurants.isEmpty) {
      setState(() {
        _noticeTitle = '지금은 고를 수 있는\n식당이 없어요';
        _noticeBody = '내 대학가에 쿠폰을 받을 식당이 아직 없어요.';
        _phase = _Phase.notice;
      });
      return;
    }
    final answers = _answerMap;
    final result = await showLimitedCouponPickSheet(
      context,
      offer: offer,
      claim: (ids) => SurveyService.complete(
        widget.code,
        answers: answers,
        restaurantId: ids.first,
        entry: widget.entry,
        elapsedSeconds: DateTime.now().difference(_openedAt).inSeconds,
      ),
    );
    if (!mounted) return;
    if (result?.claimed != true) {
      // 쿠폰을 안 고르고 나갔다 — 아무것도 저장되지 않았으니 설문도 닫는다.
      return _close();
    }
    AnalyticsLogger.logEvent(
      AnalyticsEvents.surveyCouponClaim,
      parameters: {'survey_code': widget.code, 'entry': widget.entry},
    );
    Navigator.of(context).pop(
      SurveyOutcome(
        tag: offer.tagLabel,
        title: (result!.title != null && result.title!.isNotEmpty)
            ? result.title!
            : '${offer.tagLabel}을 받았어요',
        issuedCodes: result.issuedCodes,
      ),
    );
  }

  void _openWallet() {
    Navigator.of(context).pop();
    DeepLinkService.instance.tryHandle(Uri.parse('wouldulike://wallet/coupons'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting && _phase != _Phase.claiming,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
            child: _buildPhase(),
          ),
        ),
      ),
    );
  }

  Widget _topButton(String label) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _submitting ? null : _close,
        style: TextButton.styleFrom(
          foregroundColor: OnboardingStyle.muted,
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _message({
    required String top,
    required String title,
    required String subtitle,
    required Widget hero,
    required Widget button,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topButton(top),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(title, style: _headline),
        ),
        const SizedBox(height: 12),
        Text(subtitle, style: OnboardingStyle.subtitle),
        Expanded(child: hero),
        button,
      ],
    );
  }

  Widget _primary(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      style: OnboardingStyle.primaryButton(enabled: onPressed != null),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case _Phase.loading:
      case _Phase.claiming:
        return Column(
          children: [
            _topButton('닫기'),
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: OnboardingStyle.primary),
              ),
            ),
          ],
        );
      case _Phase.start:
        final d = _detail!;
        return _message(
          top: '다음에 할게요',
          title: d.headline.isNotEmpty ? d.headline : d.title,
          subtitle: d.description,
          hero: Center(child: _rewardTicket(d)),
          button: _primary('시작하기', _begin),
        );
      case _Phase.question:
        return _buildQuestion();
      case _Phase.done:
        return _message(
          top: '닫기',
          title: '이미 참여한\n설문이에요',
          subtitle: '설문은 한 번만 참여할 수 있어요.\n받은 쿠폰은 지갑에서 볼 수 있어요.',
          hero: const SizedBox.shrink(),
          button: _primary('내 지갑 바로가기', _openWallet),
        );
      case _Phase.closed:
        return _message(
          top: '닫기',
          title: '지금은 참여할 수\n없는 설문이에요',
          subtitle: '설문 기간이 끝났어요.',
          hero: const SizedBox.shrink(),
          button: _primary('확인', _close),
        );
      case _Phase.notice:
        return _message(
          top: '닫기',
          title: _noticeTitle,
          subtitle: _noticeBody,
          hero: const SizedBox.shrink(),
          button: _primary('확인', _close),
        );
      case _Phase.error:
        return _message(
          top: '닫기',
          title: '설문을 불러오지\n못했어요',
          subtitle: '잠시 후 다시 시도해 주세요.',
          hero: const SizedBox.shrink(),
          button: _primary('다시 시도', _load),
        );
    }
  }

  /// 지갑과 같은 쿠폰 카드 — 받을 쿠폰을 미리 보여 준다(버튼 없음).
  Widget _rewardTicket(SurveyDetail d) {
    final days = d.rewardValidDays;
    return SizedBox(
      width: 320,
      child: CouponTicketCard(
        iconPath: 'assets/icons/category/all.svg',
        storeLabel: '내 대학가 제휴 식당 중 1곳',
        title: d.rewardTitle ?? '설문 참여 감사 쿠폰',
        subtitle: '답하면 원하는 식당을 골라 받아요',
        expiryText: days != null ? '받은 날부터 $days일간' : null,
        showAction: false,
        margin: EdgeInsets.zero,
        borderColor: const Color(0xFFE1E5EA),
      ),
    );
  }

  Widget _buildQuestion() {
    final d = _detail!;
    final q = d.questions[_step];
    final selected = _answers[_step];
    final last = _step == d.questions.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topButton('닫기'),
        if (q.badge.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: OnboardingStyle.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                q.badge,
                style: OnboardingStyle.caption.copyWith(
                  color: OnboardingStyle.primary,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 16),
        Text(q.text, style: OnboardingStyle.title),
        const SizedBox(height: 8),
        const Text('하나만 골라 주세요.', style: OnboardingStyle.subtitle),
        const SizedBox(height: 20),
        for (final o in q.options) ...[
          _optionTile(o, selected == o.value),
          const SizedBox(height: 8),
        ],
        const Spacer(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: OnboardingStyle.caption.copyWith(color: OnboardingStyle.danger),
              ),
            ),
          ),
        _dots(d.questions.length),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: _primary(
            _submitting ? '보내는 중…' : (last ? '제출하고 쿠폰 받기' : '다음'),
            selected == null || _submitting ? null : _next,
          ),
        ),
      ],
    );
  }

  /// 식당 고르기 목록(RestaurantPickList) 항목과 같은 모양 — 글자만.
  Widget _optionTile(SurveyOption o, bool selected) {
    return Material(
      color: selected ? OnboardingStyle.accentSoft : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _submitting
            ? null
            : () => setState(() {
                  _answers[_step] = o.value;
                  _error = null;
                }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? OnboardingStyle.accent : OnboardingStyle.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  o.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? OnboardingStyle.primary : OnboardingStyle.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: OnboardingStyle.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 온보딩 점 표시와 같은 값.
  Widget _dots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? OnboardingStyle.primary : OnboardingStyle.line,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
