// Castor 캡처용 가짜 데이터. 매장 · 사람 이름은 모두 지어낸 것이다(실제 매장 · 사용자 아님).
// 사진 주소는 가짜 도메인 — 하네스가 테스트에서 그린 음식 사진으로 바꿔 준다.

const String kFakeToken = 'castor.fake.token';

/// 로그인 · 가입 완료 상태(토큰 만료 2100년 → 갱신 호출 없음).
Map<String, Object> loggedInPrefs([Map<String, Object> extra = const {}]) => {
      'jwt_access_token': kFakeToken,
      'access_expires_at': 4102444800,
      'user_id': 1001,
      'user_uuid': '00000000-castor-0000-0000-000000000001',
      'onboarding_intro_seen_v1': true,
      'onboarding_reward_done_v1': true,
      'onboarding_reward_pending_v1': false,
      'user_lat': 35.8906,
      'user_lon': 128.6121,
      'wallet_raffle_schedule_collapsed': true,
      'welcome_coupon_dialog_dismissed': true,
      'kakao_logged_in': true,
      'user_kakao_id': '4000000001',
      'recommended_foods': <String>['김치찌개', '돈가스', '라멘'],
      ...extra,
    };

const _kind = {
  '한식': 'korean', '중식': 'chinese', '일식': 'japanese', '양식': 'pizza', '돈가스': 'donkatsu',
  '햄버거': 'hamburger', '카페': 'cafe', '술집': 'pub', '분식': 'snack',
};
const _sub = {
  101: '백반', 102: '국밥', 103: '라멘', 104: '버거', 105: '마라탕',
  106: '돈가스', 107: '커피', 108: '떡볶이', 109: '파스타', 110: '포차',
};
String kindOf(FakeStore s) => _kind[s.category] ?? 'total';
String subOf(FakeStore s) => _sub[s.id] ?? s.category;

String img(String key) => 'https://castor-fake-images.s3.ap-northeast-2.amazonaws.com/store/$key.jpg';

DateTime get _now => DateTime.now();
String iso(Duration d) => _now.add(d).toIso8601String();

class FakeStore {
  const FakeStore(this.id, this.name, this.category, this.zone, this.desc,
      {this.stamp = 0, this.target = 10, this.coupon = '음료 1잔 무료'});
  final int id;
  final String name;
  final String category;
  final String zone;
  final String desc;
  final int stamp;
  final int target;
  final String coupon;
}

const fakeStores = <FakeStore>[
  FakeStore(101, '한솥가득 백반', '한식', '북문', '매일 바뀌는 집밥 백반과 제육볶음', stamp: 6, coupon: '공깃밥 + 계란후라이 무료'),
  FakeStore(102, '소담국밥', '한식', '정문', '24시간 끓인 돼지국밥 전문', stamp: 3, coupon: '국밥 1,000원 할인'),
  FakeStore(103, '미소라멘 연구소', '일식', '북문', '진한 돈코츠 라멘과 차슈덮밥', stamp: 8, coupon: '차슈 토핑 무료'),
  FakeStore(104, '버거스테이션', '햄버거', '쪽문', '수제 패티 스매시 버거', stamp: 2, coupon: '감자튀김 사이즈업'),
  FakeStore(105, '마라공방', '중식', '정문', '재료 골라 담는 마라탕 · 꿔바로우', coupon: '꿔바로우 미니 무료'),
  FakeStore(106, '카츠하우스 소소', '돈가스', '북문', '두툼한 등심카츠와 치즈카츠', stamp: 4, coupon: '음료 1잔 무료'),
  FakeStore(107, '카페 오후세시', '카페', '쪽문', '직접 로스팅한 원두와 수제 디저트', stamp: 9, coupon: '아메리카노 1+1'),
  FakeStore(108, '골목분식', '분식', '서문', '떡볶이 · 김밥 · 튀김 세트', coupon: '튀김 3종 무료'),
  FakeStore(109, '파스타공장 북문점', '양식', '북문', '생면 파스타와 화덕 피자', coupon: '에이드 1잔 무료'),
  FakeStore(110, '청춘포차', '술집', '정문', '대학가 감성 포차 · 닭볶음탕', coupon: '계란찜 서비스'),
];

Map<String, dynamic> storeJson(FakeStore s, {bool detail = false}) => {
      'restaurant_id': s.id,
      'id': s.id,
      'name': s.name,
      'description': s.desc,
      'address': '대구 북구 대학로 ${s.id - 40}길 ${s.id % 17 + 3}',
      'category': s.category,
      'zone': s.zone,
      'campus': '경북대',
      'phone_number': '053-000-0${s.id}',
      'url': null,
      's3_image_urls': [img('${s.id}_${kindOf(s)}_a'), img('${s.id}_${kindOf(s)}_b'), img('${s.id}_total_c')],
      'image_url': img('${s.id}_${kindOf(s)}_a'),
      'stamp_current': s.stamp,
      'stamp_target': s.target,
      'coupon_benefits_summary': benefitsSummary(s),
      if (detail) 'promotion_text': '10월 한정 · 시험기간 응원 이벤트 진행 중',
    };

List<Map<String, dynamic>> storesJson() => [for (final s in fakeStores) storeJson(s)];

Map<String, dynamic> couponJson(
  String code,
  FakeStore s, {
  String? title,
  String status = 'ISSUED',
  Duration expires = const Duration(days: 12),
  String issueKey = 'SIGNUP:1',
  String? subtitle,
}) =>
    {
      'code': code,
      'status': status,
      'restaurant_id': s.id,
      'restaurant_name': s.name,
      'restaurant_category': s.category,
      'issue_key': issueKey,
      'issued_at': iso(const Duration(days: -2)),
      'expires_at': iso(expires),
      'benefit': {
        'title': title ?? s.coupon,
        'subtitle': subtitle ?? '매장 방문 시 사용',
        'notes': '1인 1회 · 다른 쿠폰과 중복 사용 불가',
        'restaurant_id': s.id,
        'restaurant_name': s.name,
        'restaurant_category': s.category,
      },
    };

List<Map<String, dynamic>> myCoupons() => [
      couponJson('CSTR-A1', fakeStores[0], expires: const Duration(days: 2)),
      couponJson('CSTR-A2', fakeStores[6], issueKey: 'APP_OPEN:1'),
      couponJson('CSTR-A3', fakeStores[2], title: '라멘 2,000원 할인', expires: const Duration(days: 20)),
      couponJson('CSTR-A4', fakeStores[3], issueKey: 'REFERRAL:1'),
      couponJson('CSTR-A5', fakeStores[5], expires: const Duration(days: 6)),
    ];

Map<String, dynamic> stampsAll() => {
      'default_target': 10,
      'results': [
        for (final s in fakeStores.where((s) => s.stamp > 0))
          {
            'restaurant_id': s.id,
            'status': {
              'current': s.stamp,
              'target': s.target,
              'rewards': [
                {'stamps': 5, 'title': '음료 서비스'},
                {'stamps': 10, 'title': '${s.category == '카페' ? '디저트' : '메인 메뉴'} 1개 무료'},
              ],
              'notes': '',
            },
          },
      ],
    };

Map<String, dynamic> mileageSummary() => {'balance': 3200, 'month_earned': 1400};

Map<String, dynamic> walletOverview() => {
      'mileage': mileageSummary(),
      'coupons': {'usable': 5, 'expiring_soon': 1},
      'stamps': {'active_stores': 6},
    };

Map<String, dynamic> mileageHistory() => {
      'next': null,
      'results': [
        {'delta': 100, 'reason': 'VISIT', 'memo': '${fakeStores[0].name} 방문 적립', 'created_at': iso(const Duration(hours: -3))},
        {'delta': 100, 'reason': 'COUPON_USE', 'memo': '${fakeStores[6].name} 쿠폰 사용', 'created_at': iso(const Duration(days: -1))},
        {'delta': -500, 'reason': 'RAFFLE', 'memo': '식사권 응모', 'created_at': iso(const Duration(days: -2))},
        {'delta': 300, 'reason': 'MISSION', 'memo': '환영 미션 완료', 'created_at': iso(const Duration(days: -3))},
        {'delta': 100, 'reason': 'STAMP_VISIT', 'memo': '${fakeStores[2].name} 스탬프 적립', 'created_at': iso(const Duration(days: -4))},
        {'delta': 100, 'reason': 'VISIT', 'memo': '${fakeStores[5].name} 방문 적립', 'created_at': iso(const Duration(days: -6))},
      ],
    };

Map<String, dynamic> raffles() => {
      'next_opens_at': null,
      'results': [
        {
          'id': 31, 'title': '식사권', 'prize_amount': 5000, 'cost_mileage': 500,
          'restaurant_name': null, 'restaurant_id': null, 'all_stores': true,
          'participant_count': 214, 'entered': true, 'my_tickets': 2, 'closes_at': iso(const Duration(days: 2, hours: 5)),
        },
        {
          'id': 32, 'title': '식사권', 'prize_amount': 10000, 'cost_mileage': 1000,
          'restaurant_name': null, 'restaurant_id': null, 'all_stores': true,
          'participant_count': 133, 'entered': false, 'my_tickets': 0, 'closes_at': iso(const Duration(days: 2, hours: 5)),
        },
      ],
    };

Map<String, dynamic> myRaffleEntries() => {
      'results': [
        {'raffle_id': 31, 'title': '식사권', 'prize_amount': 5000, 'cost_mileage': 500, 'status': 'OPEN', 'won': false, 'all_stores': true, 'closes_at': iso(const Duration(days: 2)), 'created_at': iso(const Duration(hours: -5))},
        {'raffle_id': 29, 'title': '식사권', 'prize_amount': 10000, 'cost_mileage': 1000, 'status': 'DRAWN', 'won': true, 'all_stores': true, 'closes_at': iso(const Duration(days: -5)), 'created_at': iso(const Duration(days: -8))},
        {'raffle_id': 28, 'title': '식사권', 'prize_amount': 5000, 'cost_mileage': 500, 'status': 'DRAWN', 'won': false, 'all_stores': true, 'closes_at': iso(const Duration(days: -5)), 'created_at': iso(const Duration(days: -9))},
      ],
    };

Map<String, dynamic> raffleWinners() => {
      'results': [
        {'raffle_id': 29, 'title': '식사권', 'prize_amount': 10000, 'cost_mileage': 1000, 'participant_count': 188, 'winner_nickname': '박**', 'all_stores': true, 'restaurant_name': null, 'drawn_at': iso(const Duration(days: -5))},
        {'raffle_id': 28, 'title': '식사권', 'prize_amount': 5000, 'cost_mileage': 500, 'participant_count': 241, 'winner_nickname': '최**', 'all_stores': true, 'restaurant_name': null, 'drawn_at': iso(const Duration(days: -5))},
        {'raffle_id': 26, 'title': '식사권', 'prize_amount': 5000, 'cost_mileage': 500, 'participant_count': 197, 'winner_nickname': '정**', 'all_stores': true, 'restaurant_name': null, 'drawn_at': iso(const Duration(days: -12))},
      ],
    };

Map<String, dynamic> limitedOffer() => {
      'coupon_type_code': 'SPECIAL_OCT',
      'coupon_type_title': '10월 한정쿠폰',
      'valid_days': 7,
      'claimed': false,
      'redeem_bonus': true,
      'period': 'ONCE',
      'restaurants': [
        for (final s in fakeStores.take(7))
          {
            'restaurant_id': s.id, 'name': s.name, 'category': s.category, 'zone': s.zone,
            'campus': '경북대', 'title': s.coupon, 'subtitle': '메인 메뉴 주문 시',
          },
      ],
    };

Map<String, dynamic> userMe() => {
      'id': 1001,
      'nickname': '배고픈다람쥐',
      'campus': '경북대',
      'college_code': null,
      'department_code': null,
    };

List<Map<String, dynamic>> randomFoods() => <Map<String, dynamic>>[
      {'food_name': '김치찌개', 'description': '칼칼하고 든든한 한 끼', 'food_image_url': img('food_korean')},
      {'food_name': '돈가스', 'description': '바삭한 튀김옷의 정석', 'food_image_url': img('food_donkatsu')},
      {'food_name': '라멘', 'description': '진한 국물이 생각날 때', 'food_image_url': img('food_japanese')},
      {'food_name': '짜장면', 'description': '실패 없는 중식 대표 메뉴', 'food_image_url': img('food_chinese')},
      {'food_name': '햄버거', 'description': '간단하지만 확실한 만족', 'food_image_url': img('food_hamburger')},
    ];

Map<String, dynamic> randomRestaurants() => {
      'random_restaurants': [
        for (final s in fakeStores.take(6))
          {
            'name': s.name,
            'road_address': '대구 북구 대학로 ${s.id - 40}길 ${s.id % 17 + 3}',
            'category_1': s.category,
            'category_2': subOf(s),
            'x': '${128.6100 + (s.id % 7) * 0.0012}',
            'y': '${35.8890 + (s.id % 5) * 0.0010}',
          },
      ],
    };

Map<String, dynamic> benefitsSummary(FakeStore s) => {
      'restaurant_id': s.id,
      'generated_at': '2026-10-01T00:00:00+00:00',
      'signup': {
        'eligible': true, 'excluded': false, 'coupon_type_code': 'WELCOME_3000',
        'items': [
          {'title': s.coupon, 'subtitle': '신규가입 고객 전용', 'notes': '메인 메뉴 1개 주문 시', 'benefit': {'description': '신규가입 쿠폰'}, 'sort_order': 0},
        ],
      },
      'referral': {
        'referrer': {
          'eligible': true, 'excluded': false, 'coupon_type_code': 'REFERRAL_BONUS_REFERRER',
          'items': [
            {'title': '음료 1잔 무료', 'subtitle': '친구 초대(추천인) 보상', 'notes': '메인 메뉴 주문 시', 'benefit': {'description': '추천인'}, 'sort_order': 0},
          ],
        },
        'referee': {
          'eligible': true, 'excluded': false, 'coupon_type_code': 'REFERRAL_BONUS_REFEREE',
          'items': [
            {'title': '1,000원 할인', 'subtitle': '친구 초대(피추천인) 보상', 'notes': '메인 메뉴 주문 시', 'benefit': {'description': '피추천인'}, 'sort_order': 0},
          ],
        },
      },
      'stamp': {
        'enabled': true, 'notes': '', 'rule_type': 'THRESHOLD', 'cycle_target': s.target,
        'rewards': [
          {'title': '음료 서비스', 'stamps': 5, 'subtitle': '', 'notes': '', 'benefit': {'type': 'fixed', 'value': 2000}, 'coupon_type_code': 'STAMP_REWARD_5'},
          {'title': '메인 메뉴 1개 무료', 'stamps': s.target, 'subtitle': '', 'notes': '', 'benefit': {'type': 'fixed', 'value': 8000}, 'coupon_type_code': 'STAMP_REWARD_10'},
        ],
      },
    };

Map<String, dynamic> stampStatus(FakeStore s) => {
      'current': s.stamp,
      'target': s.target,
      'updated_at': iso(const Duration(days: -1)),
      'notes': '',
      'rewards': [
        {'stamps': 5, 'title': '음료 서비스', 'subtitle': '5번째 방문 시'},
        {'stamps': s.target, 'title': '메인 메뉴 1개 무료', 'subtitle': '${s.target}번째 방문 시'},
      ],
      'reward_coupons': [],
    };

Map<String, dynamic> featuredCampaign() => {
      'code': 'CASTOR_OCT',
      'title': '시험기간 든든 한 끼',
      'subtitle': '중간고사 기간, 북문 · 정문 제휴 식당 특별 혜택',
      'region': '경대',
      'starts_at': iso(const Duration(days: -3)),
      'ends_at': iso(const Duration(days: 11)),
      'sort_order': 0,
      'items': [
        for (final (i, s) in fakeStores.take(5).indexed)
          {
            'restaurant_id': s.id,
            'badge': i == 0 ? 'BEST' : '시험기간',
            'benefit_title': s.coupon,
            'benefit_sub': '쿠폰 제시 시 · 10월 한정',
            'image_url': img('${s.id}_${kindOf(s)}_feat'),
            'sort_order': i,
          },
      ],
    };

Map<String, dynamic> missionTrack() {
  final now = DateTime.now().toUtc();
  return {
    'stage': 'WELCOME',
    'server_time': now.toIso8601String(),
    'welcome': {
      'ends_at': now.add(const Duration(hours: 47, minutes: 59, seconds: 59, milliseconds: 500)).toIso8601String(),
      'missions': [
        {'code': 'WELCOME_COUPON_USE', 'title': '우주라이크 쿠폰 사용하기', 'reward_text': '보유한 쿠폰은 모두 인정돼요', 'status': 'CLAIMED', 'progress': 1, 'target': 1},
        {'code': 'WELCOME_STAMP_2', 'title': '스탬프 2회 적립하기', 'reward_text': '어느 매장이든 상관없어요', 'status': 'OPEN', 'progress': 1, 'target': 2},
      ],
      'reward': {'code': 'WELCOME_ALL', 'title': '환영 미션 완주 리워드', 'reward_text': '제휴 매장 쿠폰 1장', 'status': 'LOCKED', 'progress': 0, 'target': 1},
    },
    'promo_block': null,
  };
}

Map<String, dynamic> tabRestaurants() => {
      'affiliate_restaurants': storesJson(),
      'general_restaurants': [
        for (final (i, n) in const ['북문 칼국수집', '정문 김밥천하', '대학로 순두부'].indexed)
          {
            'restaurant_id': 501 + i,
            'name': n,
            'road_address': '대구광역시 북구 대학로 ${70 + i}',
            'category_1': '한식',
            'category_2': '식사',
            'campus': '경북대',
          },
      ],
      'general_pagination': {'limit': 20, 'offset': 0, 'next_offset': null, 'returned_count': 3, 'total_count': 3, 'has_more': false},
      'search_query': '',
    };

List<Map<String, dynamic>> trends() => [
      {'image_url': img('trend_1'), 'blog_link': 'https://example.com/a', 'title': '북문 가성비 점심 TOP 5', 'description': '만 원 이하로 든든하게'},
      {'image_url': img('trend_2'), 'blog_link': 'https://example.com/b', 'title': '시험기간 야식 지도', 'description': '밤 11시 이후에도 여는 곳'},
    ];

List<Map<String, dynamic>> wishlistRestaurants() => [
      for (final s in fakeStores.take(5))
        {
          'name': s.name,
          'road_address': '대구광역시 북구 대학로 ${s.id - 40}길 ${s.id % 17 + 3}',
          'category_1': s.category,
          'category_2': subOf(s),
          'x': '${128.6100 + (s.id % 7) * 0.0012}',
          'y': '${35.8890 + (s.id % 5) * 0.0010}',
        },
    ];
