import 'package:flutter/material.dart';

import 'package:new1/services/mileage_service.dart';

/// 지갑 마일리지 탭 맨 아래 최근 마일리지 내역 (스펙 7.1).
/// 상점과 한 스크롤 안에 들어가므로 따로 스크롤하지 않고 최근 [maxItems]건만 보여준다.
/// 적립은 양수 표기와 강조색, 사용은 음수 표기와 기본색.
class MileageHistorySection extends StatefulWidget {
  const MileageHistorySection({super.key, this.maxItems = 15});

  final int maxItems;

  @override
  State<MileageHistorySection> createState() => _MileageHistorySectionState();
}

class _MileageHistorySectionState extends State<MileageHistorySection> {
  static const _ink = Color(0xFF191F28);
  static const _muted = Color(0xFF4E5968);
  static const _faint = Color(0xFF8B95A1);
  static const _primary = Color(0xFF312E81);
  static const _line = Color(0xFFE7E9EF);

  List<MileageEvent> _events = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final page = await MileageService.fetchHistory();
    if (!mounted) return;
    setState(() {
      _events = page.events.take(widget.maxItems).toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '마일리지 내역',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: _ink,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '최근 ${widget.maxItems}건까지',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _faint,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _line),
          ),
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
          ),
        ),
      );
    }
    if (_events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.savings_outlined, size: 36, color: _primary),
              SizedBox(height: 10),
              Text(
                '아직 마일리지 내역이 없어요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '제휴 매장에 방문하면 마일리지가 쌓여요.',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _events.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F2F7)),
          _buildRow(_events[i]),
        ],
      ],
    );
  }

  Widget _buildRow(MileageEvent event) {
    final created = event.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.label,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                if (created != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${created.year}.${_two(created.month)}.${_two(created.day)}',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _faint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${event.isEarn ? '+' : '-'}${_comma(event.delta.abs())} M',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: event.isEarn ? _primary : _muted,
            ),
          ),
        ],
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _comma(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
