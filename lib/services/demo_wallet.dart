/// 시뮬레이터 시연용 지갑 데이터 스텁.
/// `--dart-define=DEMO_WALLET=1` 로 실행할 때만 활성화되고, 기본 빌드에는 영향이 없다.
/// 운영 데이터를 건드리지 않고 "고니식탁 쿠폰 1장 + 스탬프 2개" 상태 UI를 확인하는 용도.
const bool kDemoWallet = bool.fromEnvironment('DEMO_WALLET');

/// 고니식탁 (운영 affiliate-restaurants 기준 restaurant_id)
const int kDemoRestaurantId = 30;

/// 고니식탁 스탬프 정책(운영 detail API와 동일): 3개 음료, 5개 계란말이, 10개 찌개
const List<(int, String)> kDemoStampTiers = [
  (3, '음료 서비스'),
  (5, '계란말이 서비스'),
  (10, '찌개 1인분 서비스'),
];
const int kDemoStampTarget = 10;

/// 데모 모드는 서버를 안 쓰므로 적립 상태를 메모리에 들고 있는다.
/// 이게 없으면 "적립하기"를 눌러도 도장이 안 찍힌다.
int _demoStamps = 2;
final List<Map<String, dynamic>> _demoRewardCoupons = <Map<String, dynamic>>[];

/// 기본 쿠폰 1장 + 데모 중 스탬프로 받은 리워드 쿠폰들
List<Map<String, dynamic>> demoCouponsJson() => <Map<String, dynamic>>[
      ..._demoRewardCoupons,
      demoCouponJson(),
    ];

Map<String, dynamic> demoCouponJson() {
  final now = DateTime.now();
  return <String, dynamic>{
    'code': 'DEMOGONI3000',
    'status': 'ISSUED',
    'restaurant_id': kDemoRestaurantId,
    'issued_at': now.toIso8601String(),
    'expires_at': now.add(const Duration(days: 14)).toIso8601String(),
    'issue_key': 'FLASH:DEMO',
    'benefit': <String, dynamic>{
      'title': '3,000원 할인 쿠폰',
      'subtitle': '고니식탁 제휴 혜택',
      'restaurant_id': kDemoRestaurantId,
      'restaurant_name': '고니식탁',
      'restaurant_category': '한식',
      'benefit': <String, dynamic>{'type': 'fixed', 'value': 3000},
    },
  };
}

/// 고니식탁 스탬프 정책(운영 detail API): 3개 음료, 5개 계란말이, 10개 찌개 1인분
Map<String, dynamic> demoStampStatusJson() => <String, dynamic>{
      'current': _demoStamps,
      // 서버와 동일하게 target 은 cycle_target(판 한 바퀴)이다.
      'target': kDemoStampTarget,
      'updated_at': DateTime.now().toIso8601String(),
      'rewards': <Map<String, dynamic>>[
        {
          'stamps': 3,
          'title': '음료 서비스',
          'coupon_type_code': 'STAMP_REWARD_3',
        },
        {
          'stamps': 5,
          'title': '계란말이 서비스',
          'coupon_type_code': 'STAMP_REWARD_5',
        },
        {
          'stamps': 10,
          'title': '찌개 1인분 서비스',
          'coupon_type_code': 'STAMP_REWARD_10',
        },
      ],
    };

/// 데모 적립. 백엔드 THRESHOLD 규칙과 같은 순서로 처리한다:
/// 1개씩 올리며 임계값을 넘으면 리워드 쿠폰 발급, 판 한 바퀴(라운드)에 닿으면 리셋.
Map<String, dynamic> demoAddStampJson(int count) {
  final top = kDemoStampTiers.last.$1;
  final roundLength = kDemoStampTarget > top ? kDemoStampTarget : top;
  final codes = <String>[];
  final rewards = <Map<String, dynamic>>[];

  for (var i = 0; i < count; i++) {
    final before = _demoStamps;
    _demoStamps += 1;
    for (final tier in kDemoStampTiers) {
      if (before < tier.$1 && tier.$1 <= _demoStamps) {
        final code = 'DEMOSTAMP${tier.$1}${_demoRewardCoupons.length}';
        codes.add(code);
        rewards.add(<String, dynamic>{
          'threshold': tier.$1,
          'coupon_code': code,
          'coupon_type': 'STAMP_REWARD_${tier.$1}',
        });
        _demoRewardCoupons.insert(0, _demoRewardCouponJson(code, tier));
      }
    }
    if (_demoStamps >= roundLength) {
      _demoStamps -= roundLength;
    }
  }

  return <String, dynamic>{
    'ok': true,
    'added': count,
    'current': _demoStamps,
    'target': kDemoStampTarget,
    'reward_coupon_code': codes.isNotEmpty ? codes.last : null,
    'reward_coupon_codes': codes,
    'reward_coupons': rewards,
  };
}

Map<String, dynamic> _demoRewardCouponJson(String code, (int, String) tier) {
  final now = DateTime.now();
  return <String, dynamic>{
    'code': code,
    'status': 'ISSUED',
    'restaurant_id': kDemoRestaurantId,
    'issued_at': now.toIso8601String(),
    'expires_at': now.add(const Duration(days: 30)).toIso8601String(),
    'issue_key': 'STAMP_REWARD:DEMO',
    'benefit': <String, dynamic>{
      'title': tier.$2,
      'subtitle': '스탬프 ${tier.$1}개 보상',
      'restaurant_id': kDemoRestaurantId,
      'restaurant_name': '고니식탁',
      'restaurant_category': '한식',
    },
  };
}
