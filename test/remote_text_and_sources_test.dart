import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/remote_text_service.dart';

void main() {
  homeBlockOrderTests();
  group('RemoteText (원격 설정이 없을 때 코드 기본값)', () {
    test('문구 기본값은 "매장 PIN" 등 확정 문구', () {
      expect(RemoteText.string('coupon_use_pin_label'), '매장 PIN');
      expect(RemoteText.string('coupon_use_show_staff'), '직원에게 이 화면을 보여주세요');
      expect(RemoteText.string('coupon_use_pin_help'), 'PIN은 계산대 안내문에 있어요');
    });

    test('스탬프 동시 적립 기본값은 꺼짐 (결정 7), 배너 5초', () {
      expect(RemoteText.boolValue('coupon_use_with_stamp_default'), isFalse);
      expect(RemoteText.intValue('banner_autoplay_seconds'), 5);
    });

    test('모르는 키는 빈 값/기본형', () {
      expect(RemoteText.string('nope'), '');
      expect(RemoteText.boolValue('nope'), isFalse);
      expect(RemoteText.intValue('nope'), 0);
    });

    test('키는 콘솔 규칙(영문·숫자·밑줄)을 지킨다', () {
      for (final key in RemoteText.defaults.keys) {
        expect(key, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      }
    });
  });

  group('coupon_issue_source', () {
    test('QR 방문 쿠폰은 캠페인 코드가 있어도 QR_VISIT', () {
      expect(
        resolveCouponIssueSourceFor(
          campaignCode: 'QR_VISIT_GENERAL_EVENT',
          issueKey: 'QR_VISIT_COUPON:12:7:0',
        ),
        'QR_VISIT',
      );
      expect(getCouponIssuanceSource('QR_VISIT_COUPON:12:7:0'), 'qr_visit');
    });

    test('다른 쿠폰은 기존 규칙 그대로 (캠페인 코드 우선)', () {
      expect(
        resolveCouponIssueSourceFor(
            campaignCode: 'FLASH_8PM', issueKey: 'FLASH:1'),
        'FLASH_8PM',
      );
      expect(
        resolveCouponIssueSourceFor(issueKey: 'SIGNUP:3'),
        'SIGNUP_WELCOME',
      );
    });
  });
}

void homeBlockOrderTests() {
  group('홈 블록 순서 (원격 home_block_order)', () {
    test('기본값은 지금 화면 순서', () {
      expect(RemoteText.resolveBlockOrder(RemoteText.string('home_block_order')),
          ['promo', 'mission', 'featured', 'restaurants', 'banner']);
    });

    test('적힌 순서를 앞에 두고 나머지는 기본 순서로 붙인다', () {
      expect(RemoteText.resolveBlockOrder('restaurants, banner'),
          ['restaurants', 'banner', 'promo', 'mission', 'featured']);
    });

    test('모르는 이름·중복·대소문자 공백은 무시해도 블록이 사라지지 않는다', () {
      final order = RemoteText.resolveBlockOrder(' Banner,nope,banner,,MISSION ');
      expect(order.first, 'banner');
      expect(order[1], 'mission');
      expect(order.toSet().length, 5);
    });

    test('빈 값이면 기본 순서', () {
      expect(RemoteText.resolveBlockOrder(''), RemoteText.homeBlockDefaultOrder);
    });
  });
}
