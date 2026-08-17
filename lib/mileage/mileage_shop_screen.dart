import 'package:flutter/material.dart';

import 'package:new1/services/mileage_service.dart';

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
  static const _faint = Color(0xFF8B95A1);
  static const _line = Color(0xFFE7E9EF);
  static const _primary = Color(0xFF312E81);

  MileageSummary? _summary;
  List<Raffle> _raffles = const [];
  bool _isLoading = true;
  int? _submittingId;

  /// 응모 진행 중인 건의 멱등 키. 재시도해도 같은 키를 보내 중복 차감을 막는다.
  final Map<int, String> _pendingKeys = {};
  final Set<int> _enteredIds = {};

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '식사권에 응모할까요?',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        content: Text(
          '${_comma(raffle.costMileage)} M이 차감돼요.\n미당첨 시 마일리지는 환급되지 않아요.',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4E5968),
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
                      closesAt: r.closesAt,
                    )
                  : r)
              .toList();
        }
      });
      _snack(result.ok ? '응모를 완료했어요. 추첨 결과를 기다려 주세요.' : '이미 응모한 식사권이에요.');
      return;
    }

    // 잔액 부족은 다이얼로그 대신 스낵바로 안내 (스펙 7.2).
    if (result.code == 'INSUFFICIENT_MILEAGE') {
      final balance = result.balance;
      _snack(balance != null
          ? '마일리지가 부족해요. (보유 ${_comma(balance)} M)'
          : '마일리지가 부족해요.');
      return;
    }
    _snack(result.message ?? '응모하지 못했어요. 잠시 후 다시 시도해 주세요.');
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
      backgroundColor: const Color(0xFFFAFAFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const Text(
          '마일리지 상점',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        iconTheme: const IconThemeData(color: _ink),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : RefreshIndicator(
              color: const Color(0xFF6366F1),
              backgroundColor: Colors.white,
              strokeWidth: 2,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
                children: [
                  _buildHero(),
                  const SizedBox(height: 20),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '식사권 응모',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.48,
                          color: _ink,
                        ),
                      ),
                      Text(
                        '매주 추첨',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _faint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_raffles.isEmpty)
                    _buildEmpty()
                  else
                    GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var i = 0; i < _raffles.length; i++)
                          _buildRaffleCard(_raffles[i], i),
                      ],
                    ),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B47C4), Color(0xFF6A5AE6), Color(0xFF7C64EE)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C4A42C4),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '보유 마일리지',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xD1FFFFFF),
            ),
          ),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _comma(balance),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.84,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const TextSpan(
                  text: ' M',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '이번 달 +${_comma(monthEarned)} M 적립 · 응모에 사용해요',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Color(0xCCFFFFFF),
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
            '진행 중인 식사권 응모가 없어요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4E5968),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRaffleCard(Raffle raffle, int index) {
    const gradients = [
      [Color(0xFF4B47C4), Color(0xFF6A5AE6)],
      [Color(0xFF5A57CE), Color(0xFF8481EC)],
      [Color(0xFF3F3CA0), Color(0xFF5B57D6)],
    ];
    final gradient = gradients[index % gradients.length];
    final dday = _dday(raffle.closesAt);
    final isSoon = dday != null && dday <= 1;
    final entered = _enteredIds.contains(raffle.id);
    final isSubmitting = _submittingId == raffle.id;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 5 / 3,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        raffle.title,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xD9FFFFFF),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_comma(raffle.prizeAmount)}원',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.38,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (dday != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSoon
                            ? const Color(0xFFE11D48)
                            : const Color(0x5209071A),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        dday <= 0 ? '오늘 마감' : 'D-$dday',
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  raffle.restaurantName.isEmpty
                      ? '제휴 매장'
                      : raffle.restaurantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.27,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_comma(raffle.costMileage)} M',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _primary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '${_comma(raffle.entriesCount)}명 응모',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _faint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        entered || isSubmitting ? null : () => _enter(raffle),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFDDE0EF),
                      disabledForegroundColor: _faint,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(entered ? '응모 완료' : '응모하기'),
                  ),
                ),
              ],
            ),
          ),
        ],
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
