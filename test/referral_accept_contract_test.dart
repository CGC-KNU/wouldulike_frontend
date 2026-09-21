import 'package:flutter_test/flutter_test.dart';
import 'package:new1/services/coupon_service.dart';

void main() {
  group('ReferralAcceptResponse', () {
    test('reads code_kind, event_kind, and issued_coupons', () {
      final result = ReferralAcceptResponse.fromJson({
        'ok': true,
        'referral_id': 123,
        'code_kind': 'event',
        'event_kind': 'student_council',
        'issued_coupons': [
          {
            'code': 'KNULIKE-1',
            'restaurant_id': 12,
            'issue_key': 'EVENT_REWARD:x',
            'campaign_code': 'KNULIKE_EVENT',
            'coupon_type_code': 'KNULIKE',
          },
        ],
      });

      expect(result.ok, isTrue);
      expect(result.referralId, 123);
      expect(result.isEvent, isTrue);
      expect(result.isStudentCouncil, isTrue);
      expect(result.issuedCouponCodes, ['KNULIKE-1']);
    });

    test('treats missing event_kind as friend referral when code_kind is referral',
        () {
      final result = ReferralAcceptResponse.fromJson({
        'ok': true,
        'code_kind': 'referral',
      });
      expect(result.isReferral, isTrue);
      expect(result.isEvent, isFalse);
      expect(result.eventKind, isNull);
    });
  });

  group('referralIssuedCopy', () {
    test('splits copy by server kinds only', () {
      expect(
        referralIssuedCopy(const ReferralAcceptResponse(
          ok: true,
          codeKind: 'event',
          eventKind: 'student_council',
        )).title,
        '학생회 쿠폰 발급',
      );
      expect(
        referralIssuedCopy(const ReferralAcceptResponse(
          ok: true,
          codeKind: 'event',
          eventKind: 'special',
        )).title,
        '이벤트 쿠폰 발급',
      );
      expect(
        referralIssuedCopy(const ReferralAcceptResponse(
          ok: true,
          codeKind: 'referral',
        )).title,
        '친구 초대 쿠폰 발급',
      );
    });
  });

  group('readInviteCode', () {
    test('prefers code then invite_code then coupon_code', () {
      expect(readInviteCode({'code': 'A1', 'invite_code': 'B2'}), 'A1');
      expect(readInviteCode({'invite_code': 'B2', 'coupon_code': 'C3'}), 'B2');
      expect(readInviteCode({'coupon_code': 'C3'}), 'C3');
      expect(readInviteCode({}), isNull);
    });
  });

  group('pickIssuedCouponCard', () {
    test('prefers matching issued code with benefit and latest issued_at', () {
      final older = UserCoupon(
        code: 'A',
        status: CouponStatus.issued,
        benefit: const CouponBenefitInfo(title: 'old'),
        issuedAt: DateTime(2026, 1, 1),
      );
      final newer = UserCoupon(
        code: 'B',
        status: CouponStatus.issued,
        benefit: const CouponBenefitInfo(title: 'new'),
        issuedAt: DateTime(2026, 8, 1),
      );
      final noBenefit = UserCoupon(
        code: 'B',
        status: CouponStatus.issued,
        issuedAt: DateTime(2026, 9, 1),
      );

      final picked = pickIssuedCouponCard(
        [older, noBenefit, newer],
        issuedCodes: ['B'],
      );
      expect(picked?.code, 'B');
      expect(picked?.benefit?.title, 'new');
    });
  });
}
