import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/featured/featured_banner_analytics.dart';
import 'package:new1/services/promotion_service.dart';
import 'package:new1/utils/impression_tracker.dart';

/// 홈 기획전 세로배너의 노출·클릭 — 트렌드 배너와 같은 이벤트를 banner_type 으로 가른다.
///
/// 여기서 잡아야 하는 것:
///   ① 노출과 클릭이 같은 키·값을 싣는가. 어긋나면 붙여서 CTR 을 못 낸다.
///   ② 트렌드 배너(promo)와 섞이지 않게 banner_type 이 featured 인가.
///   ③ 구분 키가 자리(index)에 묶이지 않는가 — 순서가 바뀌어도 같은 배너는 한 번.
///   ④ 옆 장은 스와이프해서 보였을 때 센다(자동 넘김이 없다).
void main() {
  FeaturedCampaign campaign(String code, List<Map<String, dynamic>> items, {String title = ''}) =>
      FeaturedCampaign.fromJson({'code': code, 'title': title, 'items': items});

  final standalone = <String, dynamic>{
    'restaurant_id': null,
    'benefit_title': '한정쿠폰',
    'image_url': 'https://cdn.example.com/a.png',
    'link_url': 'https://www.instagram.com/p/first/',
    'sort_order': 0,
  };
  final linked = <String, dynamic>{
    'restaurant_id': 42,
    'benefit_title': '',
    'sort_order': 1,
  };

  test('① 노출과 클릭이 같은 파라미터 — 독립형은 링크, 식당 연결형은 매장', () {
    final c = campaign('BANNER_A', [standalone, linked], title: '10월 기획전');
    final a = featuredBannerParams(c, c.items[0], 0);
    expect(a[AnalyticsEvents.paramBannerType], 'featured');
    expect(a[AnalyticsEvents.paramBannerIndex], 0);
    expect(a[AnalyticsEvents.paramBannerTitle], '한정쿠폰');
    expect(a[AnalyticsEvents.paramBannerUrl], 'https://www.instagram.com/p/first/');
    expect(a[AnalyticsEvents.paramBannerSource], 'remote');
    expect(a[AnalyticsEvents.paramCampaignCode], 'BANNER_A');
    expect(a[AnalyticsEvents.paramRestaurantId], isNull);

    final b = featuredBannerParams(c, c.items[1], 1);
    expect(b[AnalyticsEvents.paramRestaurantId], 42);
    expect(b[AnalyticsEvents.paramBannerUrl], '', reason: '식당 연결형은 링크 없이 기획전 상세를 연다');
    expect(b[AnalyticsEvents.paramBannerTitle], '10월 기획전', reason: '혜택 문구가 비면 기획전 제목');
  });

  test('② 트렌드 배너와 같은 키를 쓰되 banner_type 으로 갈린다', () {
    final c = campaign('BANNER_A', [standalone]);
    final keys = featuredBannerParams(c, c.items[0], 0).keys.toSet();
    // 트렌드 배너(_bannerParams)가 싣는 다섯 키를 모두 싣는다 — 같은 쿼리로 종류만 바꿔 읽는다
    expect(keys, containsAll(<String>[
      AnalyticsEvents.paramBannerType,
      AnalyticsEvents.paramBannerIndex,
      AnalyticsEvents.paramBannerTitle,
      AnalyticsEvents.paramBannerUrl,
      AnalyticsEvents.paramBannerSource,
    ]));
    expect(featuredBannerParams(c, c.items[0], 0)[AnalyticsEvents.paramBannerType], isNot('promo'));
  });

  test('③ 구분 키는 기획전 + 대상 — 자리와 무관하고, 기획전·대상이 다르면 다르다', () {
    final c = campaign('BANNER_A', [standalone, linked]);
    final moved = campaign('BANNER_A', [{...linked, 'sort_order': 0}, {...standalone, 'sort_order': 1}]);
    expect(featuredBannerDedupKey(c, c.items[0]), featuredBannerDedupKey(moved, moved.items[1]));
    expect(featuredBannerDedupKey(c, c.items[0]), isNot(featuredBannerDedupKey(c, c.items[1])));
    final other = campaign('BANNER_B', [linked]);
    expect(featuredBannerDedupKey(c, c.items[1]), isNot(featuredBannerDedupKey(other, other.items[0])));
    expect(featuredBannerDedupKey(c, c.items[0]), startsWith('featured:'), reason: '트렌드 배너 키(banner:)와 겹치지 않는다');
  });

  testWidgets('④ 옆 장은 스와이프해서 보였을 때 센다', (tester) async {
    ImpressionSession.resetForTest();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = campaign('BANNER_A', [standalone, linked]);
    final log = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 460,
          child: PageView.builder(
            itemCount: c.items.length,
            itemBuilder: (context, i) => ImpressionDetector(
              dedupKey: featuredBannerDedupKey(c, c.items[i]),
              onImpression: () => log.add(featuredBannerParams(c, c.items[i], i)[AnalyticsEvents.paramBannerIndex]),
              child: ColoredBox(color: Colors.grey, child: Center(child: Text('slide $i'))),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(log, [0], reason: '첫 장만 보인다');

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(log, [0, 1]);
  });
}
