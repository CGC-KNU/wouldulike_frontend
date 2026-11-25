import 'package:flutter/material.dart';

import '../partner_design.dart';

const _metricLabels = {
  'views': '조회',
  'reach': '도달',
  'likes': '좋아요',
  'saved': '저장',
  'shares': '공유',
  'comments': '댓글',
};

String? _monthDay(Object? value) {
  if (value is! String || value.length < 10) return null;
  final date = DateTime.tryParse(value.substring(0, 10));
  return date == null ? null : '${date.month}/${date.day}';
}

class PartnerContentPost extends StatelessWidget {
  const PartnerContentPost(
      {super.key, required this.post, required this.openLink});

  final Map<String, dynamic> post;
  final ValueChanged<String> openLink;

  @override
  Widget build(BuildContext context) {
    final permalink = post['permalink'];
    final posted = _monthDay(post['posted_at']);
    final captured = _monthDay(post['captured_at']);
    final format = switch (post['format']) {
      'carousel' => '카드뉴스',
      'reel' => '릴스',
      'image' => '사진',
      _ => '게시물',
    };
    final note = switch ((post['status'], captured)) {
      ('pending', _) || (_, null) => '집계 준비 중',
      ('stale', final date) => '$date 수집 · 수집이 늦어지고 있습니다',
      (_, final date) => '$date 수집',
    };
    final localizations = MaterialLocalizations.of(context);
    final metrics = [
      for (final entry in _metricLabels.entries)
        if (post[entry.key] case final int value)
          (entry.value, localizations.formatDecimal(value)),
    ];
    const caption = TextStyle(fontSize: 11.5, color: PartnerDesign.muted);

    return PartnerPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(posted == null ? format : '$posted · $format',
                        style: caption),
                    const SizedBox(height: 4),
                    Text(post['title']?.toString() ?? '우주라이크 게시물',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (permalink is String && permalink.isNotEmpty)
                IconButton(
                  tooltip: '인스타그램에서 보기',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () => openLink(permalink),
                ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, box) {
              const spacing = 6.0;
              final columns = box.maxWidth < 230 ||
                      MediaQuery.textScalerOf(context).scale(13) > 19
                  ? 2
                  : 3;
              final width = (box.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final (label, value) in metrics)
                    Container(
                      width: width,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: PartnerDesign.tint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(children: [
                        Text(label,
                            style: caption, textAlign: TextAlign.center),
                        Text(value,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ],
              );
            }),
          ],
          const SizedBox(height: 8),
          Text(note, style: caption),
        ],
      ),
    );
  }
}
