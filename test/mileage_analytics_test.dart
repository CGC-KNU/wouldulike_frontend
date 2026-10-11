import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/services/mileage_service.dart';

void main() {
  group('resolveDeepLinkSource', () {
    test('브릿지 링크의 src 를 읽는다', () {
      expect(
        resolveDeepLinkSource(
          Uri.parse(
            'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=56&src=QR',
          ),
        ),
        'qr',
      );
    });

    test('커스텀 스킴의 src 를 읽는다', () {
      expect(
        resolveDeepLinkSource(Uri.parse('wouldulike://restaurant/56?src=share')),
        'share',
      );
    });

    test('src 가 없으면 none', () {
      expect(
        resolveDeepLinkSource(Uri.parse('wouldulike://restaurant/56')),
        'none',
      );
      expect(
        resolveDeepLinkSource(Uri.parse('wouldulike://restaurant/56?src=')),
        'none',
      );
    });

    test('src 가 붙어도 목적지 해석은 그대로다', () {
      final target = resolveWouldUlikeDeepLink(
        Uri.parse(
          'https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=56&src=qr',
        ),
      );
      expect(target?.screen, DeepLinkScreen.restaurantDetail);
      expect(target?.restaurantId, 56);
    });
  });

  group('qrVisitServerSource', () {
    test('서버가 아는 값만 넘긴다', () {
      expect(qrVisitServerSource('qr'), 'qr');
      expect(qrVisitServerSource('share'), 'share');
    });

    // src 없는 옛 QR 인쇄물이 섞여 있어 share 로 추정하지 않는다.
    test('모르는 값·none 은 보내지 않는다', () {
      expect(qrVisitServerSource('none'), isNull);
      expect(qrVisitServerSource('insta'), isNull);
      expect(qrVisitServerSource('push'), isNull);
    });
  });

  group('drawRoundFromClosesAt', () {
    test('마감일이 없으면 null', () {
      expect(drawRoundFromClosesAt(null), isNull);
    });

    test('1월 1일 기준 단순 주차', () {
      expect(drawRoundFromClosesAt(DateTime(2026, 1, 1)), '2026-W01');
      expect(drawRoundFromClosesAt(DateTime(2026, 9, 16)), '2026-W38');
    });

    // 알려진 한계: 수·금 주 2회 추첨이 같은 주차로 묶인다. 서버 회차 id 로 바꾸기 전까지 유지.
    test('같은 주의 수·금 마감은 같은 값이다', () {
      expect(
        drawRoundFromClosesAt(DateTime(2026, 9, 16)),
        drawRoundFromClosesAt(DateTime(2026, 9, 18)),
      );
    });
  });
}
