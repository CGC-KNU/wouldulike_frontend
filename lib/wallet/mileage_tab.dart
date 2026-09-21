import 'package:flutter/material.dart';

import 'package:new1/services/mileage_service.dart';

/// 지갑 마일리지 탭: 최근 내역 목록 (스펙 7.1).
/// 적립은 양수 표기와 강조색, 사용은 음수 표기와 기본색. 커서 20건씩 로드.
class MileageTab extends StatefulWidget {
  const MileageTab({super.key});

  @override
  State<MileageTab> createState() => _MileageTabState();
}

class _MileageTabState extends State<MileageTab> {
  static const _ink = Color(0xFF191F28);
  static const _muted = Color(0xFF4E5968);
  static const _faint = Color(0xFF8B95A1);
  static const _primary = Color(0xFF312E81);

  final List<MileageEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final page = await MileageService.fetchHistory();
    if (!mounted) return;
    setState(() {
      _events
        ..clear()
        ..addAll(page.events);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null) return;
    setState(() => _isLoadingMore = true);
    final page = await MileageService.fetchHistory(cursor: _nextCursor);
    if (!mounted) return;
    setState(() {
      _events.addAll(page.events);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }

    return RefreshIndicator(
      color: const Color(0xFF6366F1),
      backgroundColor: Colors.white,
      strokeWidth: 2,
      onRefresh: _load,
      child: _events.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.35,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.savings_outlined, size: 48, color: _primary),
                SizedBox(height: 12),
                Text(
                  '아직 마일리지 내역이 없어요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '제휴 매장에 방문하면 마일리지가 쌓여요.',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
      itemCount: _events.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFF1F2F7),
      ),
      itemBuilder: (context, index) {
        if (index >= _events.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildRow(_events[index]);
      },
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
