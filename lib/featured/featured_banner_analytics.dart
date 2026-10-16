import 'package:new1/config/analytics_events.dart';
import 'package:new1/services/promotion_service.dart';

/// 홈 기획전 세로배너 한 장을 가리키는 분석 파라미터.
///
/// 트렌드 가로배너와 **같은 이벤트**(home_banner_impression · home_banner_click)를 쓰고
/// banner_type 으로 가른다. 홈 배너 종류별 CTR 을 banner_type 으로 나누기로 한 그
/// 자리다(home.dart `_bannerParams`). 이 배너는 그동안 노출도 탭도 남기지 않아,
/// 한정쿠폰 시트로 가는 입구인데 몇 번 보이고 몇 번 눌렸는지 알 수 없었다(2026-10-15).
///
/// **노출과 클릭이 이 함수 하나를 같이 쓴다.** 키나 값이 어긋나면 붙여서 CTR 을 못 낸다.
Map<String, Object?> featuredBannerParams(
  FeaturedCampaign campaign,
  FeaturedCampaignItem item,
  int index,
) {
  final String title = item.benefitTitle.trim().isNotEmpty
      ? item.benefitTitle.trim()
      : campaign.title.trim();
  return {
    AnalyticsEvents.paramBannerType: 'featured',
    AnalyticsEvents.paramBannerIndex: index,
    AnalyticsEvents.paramBannerTitle: title,
    // 독립형 배너만 링크가 있다. 식당 연결형은 비고, 누르면 기획전 상세가 열린다.
    AnalyticsEvents.paramBannerUrl: item.linkUrl?.toString() ?? '',
    AnalyticsEvents.paramBannerSource: 'remote',
    AnalyticsEvents.paramCampaignCode: campaign.code,
    // 독립형 배너는 null — AnalyticsLogger 가 null 값은 빼고 보낸다.
    AnalyticsEvents.paramRestaurantId: item.restaurantId,
  };
}

/// 한 세션에 한 번만 노출로 세는 구분 키.
///
/// 자리(index)는 쓰지 않는다 — 서버 sort_order 로 순서가 바뀌면 같은 배너가 자리만
/// 옮겨도 다시 노출로 세게 된다. 기획전 코드 + 그 배너가 가리키는 대상으로 짓는다.
String featuredBannerDedupKey(FeaturedCampaign campaign, FeaturedCampaignItem item) {
  final String target = item.restaurantId?.toString() ??
      item.linkUrl?.toString() ??
      item.imageUrl ??
      item.benefitTitle;
  return 'featured:${campaign.code}:$target';
}
