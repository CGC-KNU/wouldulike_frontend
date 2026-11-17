import 'package:flutter/material.dart';
import '../partner_design.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _number(dynamic value, String unit) => value is num
    ? '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}$unit'
    : '—';
String _status(dynamic value) => switch (value) {
      'pending' => '집계 준비 중',
      'partial' => '일부 데이터만 집계',
      'stale' => '수집 지연',
      'unavailable' => '집계 미확인',
      'unknown_start' => '입점 기준일 미등록',
      'unmapped' => '게시물 연결 확인 필요',
      _ => '',
    };
String _date(dynamic value) =>
    value is String && value.length >= 10 ? value.substring(0, 10) : '';

class PartnerHomeMetrics extends StatelessWidget {
  const PartnerHomeMetrics({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final metrics = _map(data['metrics']),
        fallback = _map(_map(data['stats'])['this']);
    final promo = _map(metrics['promotion']),
        month = _map(promo['month']),
        total = _map(promo['total']);
    final views = _map(metrics['store_views']),
        coupons = _map(metrics['coupon_used']),
        stamps = _map(metrics['stamp']);
    final stampOn = _map(data['store'])['stamp_enabled'] != false;
    final items = [
      _metric('홍보 게시물 도달·조회', '조회 ${_number(month['views'], '회')}',
          _number(total['views'], '회'),
          secondPair: (
            '도달 ${_number(month['reach'], '')}',
            _number(total['reach'], '')
          ),
          note: [
            _status(month['status'] ?? promo['status']),
            _status(total['status']),
            if (_date(month['captured_at']).isNotEmpty)
              '${_date(month['captured_at'])} 수집'
          ].where((s) => s.isNotEmpty).toSet().join(' · '),
          compact: true),
      _metric('매장 상세 열람', _number(views['month'], '회'),
          _number(views['total'], '회'),
          note: [
            _status(views['month_status']),
            _status(views['total_status']),
            if (views['through'] != null) '${views['through']}까지'
          ].where((s) => s.isNotEmpty).toSet().join(' · ')),
      _metric(
          '쿠폰 사용',
          _number(coupons['month'] ?? fallback['coupon_used'], '장'),
          _number(coupons['total'], '장')),
      _metric(
          '스탬프 적립',
          stampOn ? _number(stamps['month'] ?? fallback['stamp'], '개') : '미사용',
          stampOn ? _number(stamps['total'], '개') : '미사용',
          disabled: !stampOn),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth < 330 &&
                MediaQuery.textScalerOf(context).scale(13) > 19
            ? 1
            : 2;
        return Column(children: [
          for (var start = 0; start < items.length; start += columns)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      for (var i = start;
                          i < start + columns && i < items.length;
                          i++) ...[
                        if (i > start) const SizedBox(width: 10),
                        Expanded(child: items[i]),
                      ],
                    ]))),
        ]);
      }),
      Text(
          '홍보 성과는 매장에 연결된 게시물 중 각 기간에 게시한 글의 최신 수치입니다. 도달은 게시물 간 중복을 포함합니다. '
          '${metrics['since'] == null ? '입점 기준일이 등록되면 누적을 표시합니다.' : '누적 기준일 ${metrics['since']}(계약 시작일).'}'
          '${views['total_status'] == 'partial' ? ' 상세 열람은 ${views['available_from']}부터 집계한 일부 기간입니다.' : ''}',
          style: const TextStyle(
              fontSize: 11.5, height: 1.5, color: PartnerDesign.muted)),
      const SizedBox(height: 18),
    ]);
  }

  Widget _metric(String title, String month, String total,
          {String note = '',
          bool compact = false,
          bool disabled = false,
          (String, String)? secondPair}) =>
      PartnerPanel(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 13, color: PartnerDesign.muted)),
            const SizedBox(height: 12),
            _valuePair(title, month, total,
                compact: compact, disabled: disabled),
            if (secondPair != null) ...[
              const SizedBox(height: 5),
              _valuePair(title, secondPair.$1, secondPair.$2, compact: true),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MetricNote(note),
            ],
          ]));

  Widget _valuePair(String title, String month, String total,
          {bool compact = false, bool disabled = false}) =>
      Semantics(
        label: disabled ? '$title 미사용' : '$title, 이번 달 $month, 입점 후 누적 $total',
        child: ExcludeSemantics(
            child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: month),
                  if (!disabled) ...[
                    TextSpan(
                        text: ' / ',
                        style: TextStyle(
                            fontSize: compact ? 11.5 : 14,
                            color: PartnerDesign.muted,
                            fontWeight: FontWeight.w400)),
                    TextSpan(
                        text: '누적 $total',
                        style: TextStyle(
                            fontSize: compact ? 11.5 : 14,
                            color: PartnerDesign.navy,
                            fontWeight: FontWeight.w600)),
                  ],
                ]),
                style: TextStyle(
                    fontSize: compact ? 14 : 26,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5))),
      );
}

class _MetricNote extends StatelessWidget {
  const _MetricNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final unavailable = message.contains('집계 미확인');
    final text = Text(message,
        style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: unavailable ? PartnerDesign.red : PartnerDesign.muted,
            fontWeight: unavailable ? FontWeight.w600 : FontWeight.w400));
    if (!unavailable) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(7)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const ExcludeSemantics(
            child:
                Icon(Icons.error_outline, size: 15, color: PartnerDesign.red)),
        const SizedBox(width: 4),
        Expanded(child: text),
      ]),
    );
  }
}

class PartnerInstagramSummary extends StatelessWidget {
  const PartnerInstagramSummary({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final ig = _map(_map(data['metrics'])['instagram']);
    return PartnerPanel(
        color: PartnerDesign.tint,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('우주라이크 전체 인스타 성과',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PartnerDesign.navy)),
          const SizedBox(height: 9),
          Text('조회 ${_number(ig['views'], '회')}',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text('게시물 도달 합계 ${_number(ig['reach'], '')} · 게시물 간 중복 포함',
              style: const TextStyle(fontSize: 12, color: PartnerDesign.muted)),
          const SizedBox(height: 8),
          Text(
              '수집된 전체 게시물의 최신 누적 성과 · 내 매장 성과와 별도'
              '${_date(ig['captured_at']).isNotEmpty ? ' · ${_date(ig['captured_at'])} 수집' : ''}',
              style: const TextStyle(
                  fontSize: 11.5, height: 1.5, color: PartnerDesign.muted)),
          if (_status(ig['status']).isNotEmpty) ...[
            const SizedBox(height: 8),
            _MetricNote(_status(ig['status'])),
          ],
        ]));
  }
}
