import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/coupon_list_screen.dart';
import 'package:new1/mileage/mileage_shop_screen.dart' show FadeSlideIn;
import 'package:new1/mileage/raffle_result_dialog.dart';
import 'package:new1/services/mileage_service.dart';

const _ink = Color(0xFF191F28);
const _sub = Color(0xFF4E5968);
const _faint = Color(0xFF8B95A1);
const _primary = Color(0xFF4F46E5);
const _tint = Color(0xFFEEF1FE);

/// 내 응모 내역 (GET /api/raffles/my/).
/// 추첨이 끝난 건은 결과를 바로 노출하지 않고, 사용자가 열어 볼 때 팝업으로 알려 준다.
class MyRaffleEntriesScreen extends StatefulWidget {
  const MyRaffleEntriesScreen({super.key});

  @override
  State<MyRaffleEntriesScreen> createState() => _MyRaffleEntriesScreenState();
}

class _MyRaffleEntriesScreenState extends State<MyRaffleEntriesScreen> {
  List<MyRaffleEntry> _entries = const [];
  bool _isLoading = true;

  /// 이번 화면에서 결과를 연 응모. 서버에 확인 여부를 저장하는 API가 없어 로컬로만 기억한다.
  final Set<int> _opened = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await MileageService.fetchMyEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _handleResult(MyRaffleEntry entry) async {
    setState(() => _opened.add(entry.raffleId));
    final action = await showRaffleResultDialog(
      context,
      won: entry.won,
      prizeAmount: entry.prizeAmount,
      title: entry.title,
      raffleId: entry.raffleId,
    );
    if (!mounted) return;

    switch (action) {
      case RaffleResultAction.openCoupons:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CouponListScreen(source: 'raffle_result'),
          ),
        );
      case RaffleResultAction.enterAgain:
        // 상점으로 돌아가 바로 다시 응모할 수 있게 한다.
        Navigator.of(context).pop();
      case RaffleResultAction.close:
        break;
    }
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
        centerTitle: true,
        iconTheme: const IconThemeData(color: _ink),
        title: const Text(
          '내 응모',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: _ink,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : RefreshIndicator(
              color: _primary,
              backgroundColor: Colors.white,
              strokeWidth: 2,
              onRefresh: _load,
              child: _entries.isEmpty
                  ? _buildEmpty()
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                      children: [
                        for (var i = 0; i < _entries.length; i++)
                          FadeSlideIn(
                            delayMs: i * 70,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _EntryCard(
                                entry: _entries[i],
                                opened: _opened.contains(_entries[i].raffleId),
                                onReveal: () => _handleResult(_entries[i]),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.confirmation_num_outlined, size: 44, color: _faint),
                SizedBox(height: 12),
                Text(
                  '아직 응모한 식사권이 없어요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _sub,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 응모 1건. 추첨이 끝났으면 잠긴 상태로 두고, 탭하면 롤링 뒤 결과 팝업을 띄운다.
class _EntryCard extends StatefulWidget {
  const _EntryCard({
    required this.entry,
    required this.opened,
    required this.onReveal,
  });

  final MyRaffleEntry entry;
  final bool opened;
  final VoidCallback onReveal;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard>
    with SingleTickerProviderStateMixin {
  static const _dots = ['두구', '두구두구', '두구두구두구'];

  final _random = Random();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );

  Timer? _rollTimer;
  bool _rolling = false;
  String _rollLabel = _dots.first;

  @override
  void dispose() {
    _rollTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (_rolling) return;
    HapticFeedback.selectionClick();
    setState(() => _rolling = true);
    _shake.repeat(reverse: true);
    _rollTimer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      if (!mounted) return;
      setState(() => _rollLabel = _dots[_random.nextInt(_dots.length)]);
    });

    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    _rollTimer?.cancel();
    _shake.stop();
    _shake.value = 0;
    setState(() => _rolling = false);
    widget.onReveal();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final created = entry.createdAt;
    final isDrawn = entry.status == 'DRAWN';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  created == null
                      ? '응모 완료'
                      : '${created.year}.${_two(created.month)}.${_two(created.day)} 응모',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _faint,
                  ),
                ),
              ),
              Text(
                '${_comma(entry.costMileage)} M 사용',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _faint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_comma(entry.prizeAmount)}원 ',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: _ink,
                  ),
                ),
                TextSpan(
                  text: entry.title,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: _sub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) => Transform.translate(
              offset: Offset(_rolling ? (_shake.value - 0.5) * 6 : 0, 0),
              child: child,
            ),
            child: _buildStatusBox(isDrawn),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBox(bool isDrawn) {
    // 추첨 전에는 결과를 확정 표기하지 않는다 (스펙 7.2).
    if (!isDrawn) {
      return _box(
        color: const Color(0xFFF7F8FC),
        icon: Icons.hourglass_bottom_rounded,
        iconColor: _faint,
        label: '추첨을 기다리고 있어요',
        labelColor: _sub,
      );
    }
    if (_rolling) {
      return _box(
        color: _tint,
        icon: Icons.casino_rounded,
        iconColor: _primary,
        label: _rollLabel,
        labelColor: _primary,
        trailing: const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
        ),
      );
    }
    if (!widget.opened) {
      return InkWell(
        onTap: _reveal,
        borderRadius: BorderRadius.circular(14),
        child: _box(
          color: const Color(0xFFF7F8FC),
          icon: Icons.card_giftcard_rounded,
          iconColor: _faint,
          label: '결과 확인하기',
          labelColor: _ink,
          trailing: const Icon(Icons.lock_open_rounded, size: 17, color: _faint),
        ),
      );
    }
    return _box(
      color: widget.entry.won ? _tint : const Color(0xFFF7F8FC),
      icon: widget.entry.won
          ? Icons.emoji_events_rounded
          : Icons.sentiment_dissatisfied_rounded,
      iconColor: widget.entry.won ? _primary : _faint,
      label: widget.entry.won ? '당첨 · 쿠폰함에서 확인하세요' : '미당첨 · 다음 기회에',
      labelColor: widget.entry.won ? _primary : _sub,
    );
  }

  Widget _box({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color labelColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: labelColor,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _comma(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
