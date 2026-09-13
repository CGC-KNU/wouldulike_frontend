import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/trend_service.dart';

void main() {
  test('empty or invalid banner images are not treated as displayable', () {
    expect(TrendItem.fromJson({'image_url': ''}).hasImage, isFalse);
    expect(TrendItem.fromJson({'image_url': '   '}).hasImage, isFalse);
    expect(TrendItem.fromJson({'image_url': '/local/banner.png'}).hasImage,
        isFalse);
    expect(
      TrendItem.fromJson({'image_url': 'javascript:alert(1)'}).hasImage,
      isFalse,
    );
  });

  test('https banner images from the server are displayable', () {
    expect(
      TrendItem.fromJson({
        'image_url': 'https://cdn.example.com/banners/wide.png',
      }).hasImage,
      isTrue,
    );
  });
}
