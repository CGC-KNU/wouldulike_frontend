import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/promotion_service.dart';

void main() {
  test('results 의 기획전을 모두 모아 세로 배너 순서를 유지한다', () {
    final campaigns = parseFeaturedCampaigns({
      'results': [
        {
          'code': 'A',
          'sort_order': 2,
          'items': [
            {
              'restaurant_id': null,
              'benefit_title': '두 번째',
              'image_url': 'https://cdn.example.com/b.png',
              'link_url': 'https://www.instagram.com/p/second/',
              'sort_order': 0,
            },
          ],
        },
        {
          'code': 'B',
          'sort_order': 1,
          'items': [
            {
              'restaurant_id': null,
              'benefit_title': '첫 번째',
              'benefit_subtitle': '부제',
              'image_url': 'https://cdn.example.com/a.png',
              'link_url': 'https://www.instagram.com/p/first/',
              'sort_order': 0,
            },
          ],
        },
      ],
    });

    expect(campaigns, hasLength(2));
    expect(campaigns.map((c) => c.code).toList(), ['B', 'A']);
    final slides = [
      for (final campaign in campaigns)
        for (final item in campaign.items) item.benefitTitle,
    ];
    expect(slides, ['첫 번째', '두 번째']);
    expect(campaigns.first.items.single.benefitSub, '부제');
  });

  test('단일 캠페인 객체 응답도 그대로 파싱한다', () {
    final campaigns = parseFeaturedCampaigns({
      'code': 'ONE',
      'items': [
        {
          'restaurant_id': 12,
          'image_url': 'https://cdn.example.com/store.png',
        },
      ],
    });
    expect(campaigns, hasLength(1));
    expect(campaigns.single.items.single.restaurantId, 12);
  });

  test('items 없는 캠페인은 버린다', () {
    expect(
      parseFeaturedCampaigns({
        'results': [
          {'code': 'EMPTY', 'items': []},
        ],
      }),
      isEmpty,
    );
  });
}
