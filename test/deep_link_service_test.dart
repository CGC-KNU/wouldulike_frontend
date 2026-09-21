import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/deep_link_service.dart';

void main() {
  test('브릿지 type=restaurants 는 식당 탭만 연다', () {
    final target = resolveWouldUlikeDeepLink(
      Uri.parse(
        'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurants',
      ),
    );
    expect(target?.tabIndex, 1);
    expect(target?.screen, DeepLinkScreen.restaurants);
    expect(target?.restaurantId, isNull);
  });

  test('ID 없는 wouldulike://restaurant 는 식당 탭만 연다', () {
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://restaurant'))?.tabIndex,
      1,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike:///restaurant'))
          ?.tabIndex,
      1,
    );
  });

  test('특정 식당은 상세 id를 남긴다', () {
    final target = resolveWouldUlikeDeepLink(
      Uri.parse(
        'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=56',
      ),
    );
    expect(target?.tabIndex, 1);
    expect(target?.screen, DeepLinkScreen.restaurantDetail);
    expect(target?.restaurantId, 56);
  });

  test('쿠폰함 브릿지', () {
    final target = resolveWouldUlikeDeepLink(
      Uri.parse('https://cgc-knu.github.io/wouldulike_deeplink/?type=coupons'),
    );
    expect(target?.tabIndex, 2);
    expect(target?.walletTabIndex, 0);
  });

  test('지갑 하위 탭과 상점', () {
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://stamps'))?.walletTabIndex,
      1,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://mileage'))?.walletTabIndex,
      2,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://wallet/shop'))?.screen,
      DeepLinkScreen.shop,
    );
  });

  test('앱 안 화면 딥링크', () {
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://my'))?.screen,
      DeepLinkScreen.my,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://featured/spring'))
          ?.campaignCode,
      'spring',
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://mission'))?.screen,
      DeepLinkScreen.mission,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://invite'))?.screen,
      DeepLinkScreen.invite,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://raffle/winners'))
          ?.screen,
      DeepLinkScreen.raffleWinners,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://favorites'))?.screen,
      DeepLinkScreen.favorites,
    );
    expect(
      resolveWouldUlikeDeepLink(Uri.parse('wouldulike://profile'))?.screen,
      DeepLinkScreen.profile,
    );
    expect(
      resolveWouldUlikeDeepLink(
        Uri.parse(
          'https://cgc-knu.github.io/wouldulike_deeplink/?type=login',
        ),
      )?.screen,
      DeepLinkScreen.login,
    );
  });
}
