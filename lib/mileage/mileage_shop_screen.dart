import 'package:flutter/material.dart';

import 'package:new1/mileage/my_raffle_entries_screen.dart';
import 'package:new1/mileage/raffle_terms_screen.dart';
import 'package:new1/mileage/raffle_winners_screen.dart';
import 'package:new1/services/mileage_service.dart';
import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';
import '../widgets/ticket_shell.dart';

/// 마일리지 상점 (프로토타입 화면 11, 스펙 7.2).
/// 지갑 마일리지 히어로에서만 진입한다. 하단 탭에 노출하지 않는다.
class MileageShopScreen extends StatefulWidget {
  const MileageShopScreen({super.key, this.initialSummary});

  final MileageSummary? initialSummary;

  @override
  State<MileageShopScreen> createState() => _MileageShopScreenState();
}

class _MileageShopScreenState extends State<MileageShopScreen> {
  static const _ink = Color(0xFF191F28);
  static const _sub = Color(0xFF4E5968);
  static const _faint = Color(0xFF8B95A1);
  static const _line = Color(0xFFE7E9EF);
  static const _primary = Color(0xFF4F46E5);
  static const _tint = Color(0xFFEEF1FE);
  static const _bg = Color(0xFFFAFAFD);

  MileageSummary? _summary;
  List<Raffle> _raffles = const [];
  bool _isLoading = true;
  int? _submittingId;

  /// 응모 진행 중인 건의 멱등 키. 재시도해도 같은 키를 보내 중복 차감을 막는다.
  final Map<int, String> _pendingKeys = {};

  /// 티켓 노치를 절취선 높이에 맞추기 위한 앵커. 카드마다 하나씩 유지한다.
  final Map<int, GlobalKey> _notchKeys = {};
  final Set<int> _enteredIds = {};

  /// ticket_purchase_view는 목록 로드 뒤 1회만 보낸다 (새로고침마다 부풀지 않게).
  bool _viewLogged = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      MileageService.fetchSummary(),
      MileageService.fetchRaffles(),
    ]);
    if (!mounted) return;
    setState(() {
      _summary = (results[0] as MileageSummary?) ?? _summary;
      _raffles = results[1] as List<Raffle>;
      _enteredIds
        ..clear()
        ..addAll(_raffles.where((r) => r.entered).map((r) => r.id));
      _isLoading = false;
    });
    _logShopView();
  }

  /// 응모 화면 진입. 잔액 대비 응모 가능 건수를 함께 실어, 마일리지가 모자라
  /// 되돌아가는 이탈과 그냥 둘러보는 이탈을 구분할 수 있게 한다.
  void _logShopView() {
    if (_viewLogged) return;
    _viewLogged = true;
    final balance = _summary?.balance ?? 0;
    final affordable = _raffles
        .where((r) => !r.entered && r.costMileage <= balance)
        .length;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.ticketPurchaseView,
      parameters: {
        AnalyticsEvents.paramBalance: balance,
        'affordable_raffles': affordable,
        AnalyticsEvents.paramCount: _raffles.length,
      },
    );
  }

  /// 추첨 회차 식별자. 서버가 회차 개념을 내려주지 않아 마감일의 주차로
  /// 파생한다 (같은 주 마감 건을 한 회차로 묶는다).
  ///
  /// 주의: ISO 8601 주차가 아니라 1월 1일 기준 단순 주차다. 서버가 회차를
  /// 내려주기 시작하면 그 값으로 교체해야 하며, 그 전까지 BigQuery 집계는
  /// 이 규칙과 동일하게 맞춰야 한다.
  static String? _drawRound(DateTime? closesAt) {
    if (closesAt == null) return null;
    final d = DateTime.utc(closesAt.year, closesAt.month, closesAt.day);
    final week = ((d.difference(DateTime.utc(d.year, 1, 1)).inDays +
                DateTime.utc(d.year, 1, 1).weekday -
                1) ~/
            7) +
        1;
    return '${d.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// 마감까지 남은 일수. 서버가 준 closes_at 기준으로만 계산한다.
  int? _dday(DateTime? closesAt) {
    if (closesAt == null) return null;
    final diff = closesAt.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours ~/ 24;
  }

  Future<void> _enter(Raffle raffle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '응모할까요?',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        content: Text(
          '${_comma(raffle.costMileage)} M 차감 · 취소와 환급은 안 돼요.\n'
          '당첨되면 쿠폰함으로 발급해 드려요.',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _sub,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('응모하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submittingId = raffle.id);
    final key =
        _pendingKeys.putIfAbsent(raffle.id, () => generateRaffleKey(raffle.id));
    final result =
        await MileageService.enterRaffle(raffle.id, idempotencyKey: key);
    if (!mounted) return;

    setState(() => _submittingId = null);

    // 중복 응모 응답은 이미 응모한 상태로 해석한다 (스펙 7.2).
    if (result.ok || result.isAlreadyEntered) {
      _pendingKeys.remove(raffle.id);
      setState(() {
        _enteredIds.add(raffle.id);
        if (result.balanceAfter != null) {
          _summary = MileageSummary(
            balance: result.balanceAfter!,
            monthEarned: _summary?.monthEarned ?? 0,
          );
        }
        if (result.entriesCount != null) {
          _raffles = _raffles
              .map((r) => r.id == raffle.id
                  ? Raffle(
                      id: r.id,
                      title: r.title,
                      prizeAmount: r.prizeAmount,
                      costMileage: r.costMileage,
                      restaurantName: r.restaurantName,
                      entriesCount: result.entriesCount!,
                      entered: true,
                      allStores: r.allStores,
                      closesAt: r.closesAt,
                    )
                  : r)
              .toList();
        }
      });
      // 중복 응모(이미 응모함)는 마일리지 차감이 없으므로 구매로 세지 않는다.
      if (result.ok) {
        AnalyticsLogger.logEvent(
          AnalyticsEvents.ticketPurchase,
          parameters: {
            AnalyticsEvents.paramRaffleId: raffle.id,
            if (_drawRound(raffle.closesAt) != null)
              AnalyticsEvents.paramDrawRound: _drawRound(raffle.closesAt),
            AnalyticsEvents.paramPointsSpent: raffle.costMileage,
            if (result.balanceAfter != null)
              AnalyticsEvents.paramBalanceAfter: result.balanceAfter,
            if (result.entriesCount != null)
              AnalyticsEvents.paramEntriesCount: result.entriesCount,
            AnalyticsEvents.paramFaceValue: raffle.prizeAmount,
            AnalyticsEvents.paramEntryPoint: 'mileage_shop',
          },
        );
      }
      _snack(result.ok ? '응모 완료! 당첨되면 쿠폰함으로 드려요.' : '이미 응모했어요.');
      return;
    }

    // 잔액 부족은 다이얼로그 대신 스낵바로 안내 (스펙 7.2).
    if (result.code == 'INSUFFICIENT_MILEAGE') {
      final balance = result.balance;
      _logPurchaseFailed(
        raffle,
        reason: 'insufficient_points',
        balance: balance,
      );
      _snack(balance != null
          ? '마일리지가 부족해요. (보유 ${_comma(balance)} M)'
          : '마일리지가 부족해요.');
      return;
    }
    _logPurchaseFailed(raffle, reason: result.code ?? 'unknown');
    _snack(result.message ?? '응모하지 못했어요. 잠시 후 다시 시도해 주세요.');
  }

  /// 응모 실패. 성공 분기에서만 로깅하면 마일리지가 모자라 되돌아간 사용자가
  /// 통째로 보이지 않으므로, 사유별로 반드시 함께 남긴다.
  void _logPurchaseFailed(
    Raffle raffle, {
    required String reason,
    int? balance,
  }) {
    final shortfall = balance != null ? raffle.costMileage - balance : null;
    AnalyticsLogger.logEvent(
      AnalyticsEvents.ticketPurchaseFailed,
      parameters: {
        AnalyticsEvents.paramRaffleId: raffle.id,
        if (_drawRound(raffle.closesAt) != null)
          AnalyticsEvents.paramDrawRound: _drawRound(raffle.closesAt),
        AnalyticsEvents.paramFailReason: reason,
        AnalyticsEvents.paramPointsSpent: raffle.costMileage,
        if (balance != null) AnalyticsEvents.paramBalance: balance,
        if (shortfall != null && shortfall > 0) 'shortfall_points': shortfall,
      },
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '마일리지 상점',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: _ink,
          ),
        ),
        iconTheme: const IconThemeData(color: _ink),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyRaffleEntriesScreen()),
            ),
            child: const Text(
              '내 응모',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _primary,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : RefreshIndicator(
              color: _primary,
              backgroundColor: Colors.white,
              strokeWidth: 2,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                children: [
                  FadeSlideIn(delayMs: 0, child: _buildHero()),
                  const SizedBox(height: 26),
                  FadeSlideIn(
                    delayMs: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '식사권 응모',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: _ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _line),
                          ),
                          child: const Text(
                            '매주 추첨',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _sub,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_raffles.isEmpty)
                    _buildEmpty()
                  else
                    for (var i = 0; i < _raffles.length; i += 2)
                      FadeSlideIn(
                        delayMs: 120 + (i ~/ 2) * 70,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _buildRaffleCard(_raffles[i])),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: i + 1 < _raffles.length
                                      ? _buildRaffleCard(_raffles[i + 1])
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 6),
                  FadeSlideIn(delayMs: 240, child: _buildLinks()),
                ],
              ),
            ),
    );
  }

  Widget _buildHero() {
    final balance = _summary?.balance ?? 0;
    final monthEarned = _summary?.monthEarned ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '보유 마일리지',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _sub,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      // 잔액이 0에서 차오르며 카운트업된다.
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(balance),
                        tween: Tween(begin: 0, end: balance.toDouble()),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: _comma(value.round()),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.2,
                                  color: _ink,
                                  height: 1,
                                ),
                              ),
                              const TextSpan(
                                text: ' M',
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: _primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A312E81),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'M',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 17,
                  height: 17,
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'M',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '이번 달 +${_comma(monthEarned)} M · 전 매장 공통',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: _sub,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.confirmation_num_outlined, size: 44, color: _faint),
          SizedBox(height: 12),
          Text(
            '진행 중인 응모가 없어요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _sub,
            ),
          ),
        ],
      ),
    );
  }

  /// 티켓형 응모 카드. 가운데 절취선(점선 + 좌우 노치)으로 쿠폰 느낌을 준다.
  Widget _buildRaffleCard(Raffle raffle) {
    final dday = _dday(raffle.closesAt);
    final isSoon = dday != null && dday <= 1;
    final entered = _enteredIds.contains(raffle.id);
    final isSubmitting = _submittingId == raffle.id;

    return TicketShell(
      borderRadius: 20,
      notchRadius: 8,
      notchAnchorKey: _notchKeys.putIfAbsent(raffle.id, GlobalKey.new),
      shadows: const [
        BoxShadow(
          color: Color(0x0A191F28),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
        BoxShadow(
          color: Color(0x0F191F28),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _tint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          raffle.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: _primary,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    if (dday != null) ...[
                      const Spacer(),
                      Text(
                        dday <= 0 ? '오늘 마감' : 'D-$dday',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isSoon ? const Color(0xFFE11D48) : _faint,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 11),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _comma(raffle.prizeAmount),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                            color: _ink,
                            height: 1.1,
                          ),
                        ),
                        const TextSpan(
                          text: '원',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 13, color: _primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        raffle.allStores || raffle.restaurantName.isEmpty
                            ? '전 매장 공통'
                            : raffle.restaurantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: _sub,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TicketPerforation(
            key: _notchKeys[raffle.id],
            dashColor: _line,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_comma(raffle.costMileage)} M',
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: _primary,
                        ),
                      ),
                    ),
                    Text(
                      '${_comma(raffle.entriesCount)}명',
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _faint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed:
                        entered || isSubmitting ? null : () => _enter(raffle),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      // 응모 완료는 회색 대신 톤 배경으로 둬 완료 상태가 긍정적으로 읽히게 한다.
                      disabledBackgroundColor: _tint,
                      disabledForegroundColor: _primary,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : entered
                              ? const Row(
                                  key: ValueKey('done'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded, size: 16),
                                    SizedBox(width: 4),
                                    Text('응모 완료'),
                                  ],
                                )
                              : const Text('응모하기', key: ValueKey('idle')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinks() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildLinkRow(
            icon: Icons.emoji_events_rounded,
            title: '당첨자 발표',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RaffleWinnersScreen()),
            ),
          ),
          const Divider(height: 1, thickness: 1, indent: 58, color: _line),
          _buildLinkRow(
            icon: Icons.description_rounded,
            title: '응모 유의사항',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RaffleTermsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: _tint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: _primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: _ink,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _faint),
          ],
        ),
      ),
    );
  }
}

/// 진입 시 아래에서 살짝 올라오며 나타난다. 목록에 지연을 주면 순차 등장이 된다.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// 티켓 절취선의 점선. 좌우 노치는 [TicketShell]이 카드 모양에서 파낸다.
class TicketPerforation extends StatelessWidget {
  const TicketPerforation({super.key, required this.dashColor});

  final Color dashColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final count = (constraints.maxWidth / 7).floor().clamp(1, 40);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  count,
                  (_) => Container(width: 3, height: 1, color: dashColor),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

String _comma(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
