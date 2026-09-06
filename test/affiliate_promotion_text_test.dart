import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/affiliate_service.dart';

void main() {
  test('detail parser keeps promotion_text', () {
    final restaurant = AffiliateRestaurantSummary.fromJson({
      'restaurant_id': 12,
      'name': '행컵 경대점',
      'description': '',
      'address': '',
      'category': '분식',
      'zone': '경대',
      'phone_number': '',
      'url': '',
      's3_image_urls': const [],
      'promotion_text': '한 그릇당 1,000원 할인 적용',
    });
    expect(restaurant.promotionText, '한 그릇당 1,000원 할인 적용');
  });

  test('blank promotion_text is treated as missing', () {
    final restaurant = AffiliateRestaurantSummary.fromJson({
      'restaurant_id': 1,
      'name': '테스트',
      'promotion_text': '   ',
    });
    expect(restaurant.promotionText, isNull);
  });

  test('list-shaped payload without promotion_text stays null', () {
    final restaurant = AffiliateRestaurantSummary.fromJson({
      'restaurant_id': 1,
      'name': '리스트 식당',
    });
    expect(restaurant.promotionText, isNull);
  });
}
