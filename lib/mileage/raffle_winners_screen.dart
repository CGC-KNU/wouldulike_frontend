import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/mileage/mileage_shop_screen.dart' show FadeSlideIn;
import 'package:new1/mileage/raffle_terms_screen.dart';
import 'package:new1/services/mileage_service.dart';

const _ink = Color(0xFF191F28);
const _sub = Color(0xFF4E5968);
const _faint = Color(0xFF8B95A1);
const _line = Color(0xFFE7E9EF);
const _primary = Color(0xFF4F46E5);
const _tint = Color(0xFFEEF1FE);

/// 당첨자 발표 (GET /api/raffles/winners/).
/// 결과를 바로 노출하지 않고 사용자가 직접 열어 보게 한다. 닉네임은 서버가 마스킹해 내려준다.
class RaffleWinnersScreen extends StatefulWidget {
  const RaffleWinnersScreen({super.key});

  @override
  State<RaffleWinnersScreen> createState() => _RaffleWinnersScreenState();
}

class _RaffleWinnersScreenState extends State<RaffleWinnersScreen> {
  List<RaffleWinner> _winners = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final winners = await MileageService.fetchWinners();
    if (!mounted) return;
    setState(() {
      _winners = winners;
      _isLoading = false;
    });
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
          '당첨자 발표',
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
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                children: [
                  FadeSlideIn(child: _buildHeader()),
                  const SizedBox(height: 24),
                  const FadeSlideIn(
                    delayMs: 60,
                    child: Text(
                      '지난 추첨',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: _ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_winners.isEmpty)
                    _buildEmpty()
                  else
                    for (var i = 0; i < _winners.length; i++)
                      FadeSlideIn(
                        delayMs: 120 + i * 70,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WinnerCard(winner: _winners[i]),
                        ),
                      ),
                  const SizedBox(height: 6),
                  FadeSlideIn(delayMs: 260, child: _buildNotice()),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '매주 식사권\n당첨자 발표',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    height: 1.3,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  '카드를 열어 결과를 확인해보세요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: _sub,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          _FloatingTrophy(),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_outlined, size: 40, color: _faint),
          SizedBox(height: 12),
          Text(
            '아직 발표된 결과가 없어요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _sub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '닉네임은 개인정보 보호를 위해 첫 글자만 표시해요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              height: 1.45,
              color: _sub,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RaffleTermsScreen()),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '응모 유의사항',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 17, color: _primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 회차 카드. 닫힌 상태로 시작해 탭하면 롤링 연출 뒤 당첨자를 공개한다.
class _WinnerCard extends StatefulWidget {
  const _WinnerCard({required this.winner});

  final RaffleWinner winner;

  @override
  State<_WinnerCard> createState() => _WinnerCardState();
}

class _WinnerCardState extends State<_WinnerCard> with TickerProviderStateMixin {
  /// 롤링 중 스쳐 지나갈 성씨 풀. 실제 결과와 무관한 연출용이다.
  static const _pool = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임'];

  final _random = Random();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  Timer? _rollTimer;
  bool _rolling = false;
  bool _revealed = false;
  String _label = '???';

  @override
  void dispose() {
    _rollTimer?.cancel();
    _shake.dispose();
    _pop.dispose();
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    if (_rolling || _revealed) return;
    HapticFeedback.selectionClick();
    setState(() => _rolling = true);
    _shake.repeat(reverse: true);
    _rollTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted) return;
      setState(() => _label = '${_pool[_random.nextInt(_pool.length)]}**');
    });

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    _rollTimer?.cancel();
    _shake.stop();
    _shake.value = 0;
    setState(() {
      _rolling = false;
      _revealed = true;
      _label = widget.winner.winnerNickname;
    });
    _pop.forward(from: 0);
    _confetti.forward(from: 0);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final winner = widget.winner;
    final drawn = winner.drawnAt;
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
                  drawn == null
                      ? '추첨 완료'
                      : '${drawn.year}.${_two(drawn.month)}.${_two(drawn.day)}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _faint,
                  ),
                ),
              ),
              Text(
                '${_comma(winner.entriesCount)}명 응모',
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
                  text: '${_comma(winner.prizeAmount)}원 ',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: _ink,
                  ),
                ),
                TextSpan(
                  text: winner.title,
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
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_shake, _pop]),
                builder: (context, child) {
                  // 롤링 중에는 좌우로 떨리고, 공개 순간에 한 번 튀어오른다.
                  final dx = _rolling ? (_shake.value - 0.5) * 6 : 0.0;
                  final pop = _revealed
                      ? 1 + Curves.elasticOut.transform(_pop.value) * 0.06 - 0.06
                      : 1.0;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Transform.scale(scale: pop, child: child),
                  );
                },
                child: _buildResultBox(),
              ),
              if (_revealed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _confetti,
                      builder: (context, _) => CustomPaint(
                        painter: _ConfettiPainter(_confetti.value),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultBox() {
    final opened = _rolling || _revealed;
    return Material(
      color: _revealed ? _tint : const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _revealed ? null : _reveal,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: opened ? _primary : const Color(0xFFDDE1EC),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  opened ? _label.characters.first : '?',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: opened
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _label,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: _rolling ? _sub : _ink,
                              ),
                            ),
                            const TextSpan(
                              text: ' 님',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _sub,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const Text(
                        '결과 확인하기',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: _ink,
                        ),
                      ),
              ),
              if (_revealed)
                const Icon(Icons.emoji_events_rounded,
                    size: 18, color: _primary)
              else if (_rolling)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary,
                  ),
                )
              else
                const Icon(Icons.lock_open_rounded, size: 17, color: _faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// 헤더 트로피. 천천히 위아래로 떠 있어 화면이 정지 화면처럼 보이지 않게 한다.
class _FloatingTrophy extends StatefulWidget {
  const _FloatingTrophy();

  @override
  State<_FloatingTrophy> createState() => _FloatingTrophyState();
}

class _FloatingTrophyState extends State<_FloatingTrophy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          -3 * Curves.easeInOut.transform(_controller.value),
        ),
        child: child,
      ),
      child: Container(
        width: 52,
        height: 52,
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
        child: const Icon(Icons.emoji_events_rounded,
            size: 26, color: _primary),
      ),
    );
  }
}

/// 당첨 공개 순간 카드 위로 흩날리는 조각. 위치는 고정 시드라 매번 같은 모양이 나온다.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);

  final double progress;

  static final List<_ConfettiPiece> _pieces = () {
    final random = Random(7);
    const colors = [
      _primary,
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
      Color(0xFF22C55E),
    ];
    return List.generate(18, (i) {
      return _ConfettiPiece(
        angle: -pi + random.nextDouble() * pi,
        speed: 60 + random.nextDouble() * 90,
        color: colors[i % colors.length],
        rotation: random.nextDouble() * pi,
        spin: 4 + random.nextDouble() * 6,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final origin = Offset(size.width / 2, size.height / 2);
    final fade = (1 - progress).clamp(0.0, 1.0);
    for (final piece in _pieces) {
      final dx = cos(piece.angle) * piece.speed * progress;
      final dy = sin(piece.angle) * piece.speed * progress +
          140 * progress * progress;
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(piece.rotation + piece.spin * progress);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-1.5, -4, 3, 8),
          const Radius.circular(1),
        ),
        Paint()..color = piece.color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.color,
    required this.rotation,
    required this.spin,
  });

  final double angle;
  final double speed;
  final Color color;
  final double rotation;
  final double spin;
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
