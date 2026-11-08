import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:new1/config/analytics_events.dart';
import 'package:new1/coupon/limited_coupon_offer_flow.dart';
import 'package:new1/onboarding/onboarding_style.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/services/survey_service.dart';
import 'package:new1/utils/analytics_logger.dart';
import 'package:new1/widgets/coupon_ticket_card.dart';

/// 앱 내 설문 화면 (목업 ④~⑦·⑩~⑫).
///
/// 온보딩 첫 화면(onboarding_intro_screen.dart) 틀을 그대로 쓴다: 오른쪽 위 글자 버튼,
/// 28pt 제목, 쿠폰 카드 그림, 아래 버튼. 선택지는 식당 고르기 목록(RestaurantPickList) 항목 모양.
/// 제출하면 화면을 닫고 기존 한정쿠폰 흐름(LimitedCouponOfferFlow)이 쿠폰 고르기를 띄운다.
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key, required this.code, required this.entry});

  final String code;

  /// push · home_promo · home_featured · wallet_card · deeplink
  final String entry;

  /// 설문을 열고, 제출(또는 응답만 하고 쿠폰을 안 받은 상태)이면 닫은 뒤 쿠폰 고르기를 띄운다.
  static Future<void> open(
    BuildContext context, {
    required String code,
    required String entry,
    VoidCallback? onCouponsChanged,
  }) async {
    final needsOffer = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'survey'),
        builder: (_) => SurveyScreen(code: code, entry: entry),
      ),
    );
    if (needsOffer != true || !context.mounted) return;
    await LimitedCouponOfferFlow.maybePresent(
      context,
      onCouponsChanged: () {
        AnalyticsLogger.logEvent(
          AnalyticsEvents.surveyCouponClaim,
          parameters: {'survey_code': code, 'entry': entry},
        );
        SurveyService.changes.value++;
        onCouponsChanged?.call();
      },
    );
  }

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

enum _Phase { loading, guest, start, question, done, closed, error }

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
      if (mounted) setState(() => _phase = _Phase.guest);
      return;
    }
    try {
      final detail = await SurveyService.fetchDetail(widget.code);
      if (!mounted) return;
      if (detail == null) {
        setState(() => _phase = _Phase.error);
        return;
      }
      if (detail.status == SurveyStatus.answered) {
        // 응답만 하고 쿠폰을 안 고른 사람 — 설문 대신 쿠폰 고르기로 보낸다.
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _detail = detail;
        _answers = List<String?>.filled(detail.questions.length, null);
        _phase = switch (detail.status) {
          SurveyStatus.open => _Phase.start,
          SurveyStatus.claimed => _Phase.done,
          SurveyStatus.closed => _Phase.closed,
          _ => _Phase.error,
        };
      });
    } on ApiAuthException {
      if (mounted) setState(() => _phase = _Phase.guest);
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      setState(() => _phase = e.statusCode == 404 ? _Phase.closed : _Phase.error);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  void _close() => Navigator.of(context).pop(false);

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

  Future<void> _next() async {
    final detail = _detail;
    if (detail == null || _submitting || _answers[_step] == null) return;
    if (_step < detail.questions.length - 1) {
      setState(() => _step++);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final answers = <String, String>{
      for (var i = 0; i < detail.questions.length; i++)
        if (_answers[i] != null) detail.questions[i].code: _answers[i]!,
    };
    final result = await SurveyService.submit(widget.code, answers, entry: widget.entry);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _submitting = false;
        _error = result.message ?? '보내지 못했어요. 다시 시도해 주세요.';
        if (result.code == 'closed') _phase = _Phase.closed;
      });
      return;
    }
    AnalyticsLogger.logEvent(
      AnalyticsEvents.surveySubmit,
      parameters: {'survey_code': widget.code, 'entry': widget.entry, ...answers},
    );
    // 이미 쿠폰까지 받은 상태면(다른 기기에서 참여 등) 쿠폰 고르기를 띄울 필요가 없다.
    Navigator.of(context).pop(result.status != SurveyStatus.claimed);
  }

  Future<void> _login() async {
    final result = await Navigator.of(context).pushNamed(
      '/login',
      arguments: const {'redirect': 'survey'},
    );
    if (!mounted) return;
    if (result != null && result != false) await _load();
  }

  void _openWallet() {
    Navigator.of(context).pop(false);
    DeepLinkService.instance.tryHandle(Uri.parse('wouldulike://wallet/coupons'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
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
      case _Phase.guest:
        return _message(
          top: '다음에 할게요',
          title: '로그인하면\n설문에 참여할 수 있어요',
          subtitle: '답해 주시면 바로 쓸 쿠폰을 1장 드려요.',
          hero: const SizedBox.shrink(),
          button: ElevatedButton(
            style: OnboardingStyle.kakaoButton(),
            onPressed: _login,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset('assets/icons/kakaotalk.svg', width: 22, height: 20),
                const SizedBox(width: 8),
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('카카오 로그인하고 참여하기'),
                  ),
                ),
              ],
            ),
          ),
        );
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
            _submitting ? '보내는 중…' : (last ? '제출하기' : '다음'),
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
