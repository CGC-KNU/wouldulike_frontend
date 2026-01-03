import { CategoryOption, Coupon, RestaurantDetail, RestaurantSummary, StampHistoryEntry } from '../types/affiliates';

const mockCategories: CategoryOption[] = [
  { id: 'all', label: '전체', icon: '⭐' },
  { id: 'korean', label: '한식', icon: '🍚' },
  { id: 'cafe', label: '카페', icon: '☕' },
  { id: 'japanese', label: '일식', icon: '🍣' },
  { id: 'western', label: '양식', icon: '🥗' },
  { id: 'dessert', label: '디저트', icon: '🧁' },
];

const buildStampHistory = (count: number): StampHistoryEntry[] =>
  Array.from({ length: count }, (_, index) => ({
    id: `stamp-${index + 1}`,
    accruedAt: new Date(Date.now() - (index + 1) * 86_400_000).toISOString(),
    delta: 1,
    note: index % 2 === 0 ? '방문 적립' : '이벤트 적립',
  })).reverse();

const buildCoupons = (restaurantId: string): Coupon[] => [
  {
    couponId: `${restaurantId}-cp-1`,
    name: '10% 할인 쿠폰',
    expiresAt: new Date(Date.now() + 7 * 86_400_000).toISOString(),
    status: 'available',
  },
  {
    couponId: `${restaurantId}-cp-2`,
    name: '음료 무료 쿠폰',
    expiresAt: new Date(Date.now() + 14 * 86_400_000).toISOString(),
    status: 'used',
  },
];

const restaurantStore: Record<string, RestaurantDetail> = {
  'rest-001': {
    restaurantId: 'rest-001',
    name: '한강 뷰 한식당',
    category: '한식',
    address: '서울시 영등포구 여의도동 123-45',
    distanceKm: 1.2,
    imageUrl: 'https://via.placeholder.com/320x180?text=Korean+Restaurant',
    stampCount: 7,
    stampGoal: 10,
    couponSummary: { available: 1, total: 3 },
    recentUsage: '2025-09-24T03:00:00.000Z',
    description: '한강 야경을 감상하며 정갈한 한식 코스를 즐길 수 있는 제휴 매장입니다.',
    coupons: buildCoupons('rest-001'),
    stampHistory: buildStampHistory(7),
  },
  'rest-002': {
    restaurantId: 'rest-002',
    name: '카페 달콤',
    category: '카페',
    address: '서울시 마포구 합정동 11-22',
    distanceKm: 3.4,
    imageUrl: 'https://via.placeholder.com/320x180?text=Cafe',
    stampCount: 3,
    stampGoal: 10,
    couponSummary: { available: 2, total: 4 },
    recentUsage: '2025-09-22T09:30:00.000Z',
    description: '스페셜티 커피와 다양한 디저트를 즐길 수 있는 합정 카페.',
    coupons: buildCoupons('rest-002'),
    stampHistory: buildStampHistory(3),
  },
  'rest-003': {
    restaurantId: 'rest-003',
    name: '스시 미도리',
    category: '일식',
    address: '서울시 강남구 역삼동 55-7',
    distanceKm: 5.9,
    imageUrl: 'https://via.placeholder.com/320x180?text=Sushi',
    stampCount: 9,
    stampGoal: 10,
    couponSummary: { available: 0, total: 2 },
    recentUsage: '2025-09-20T12:15:00.000Z',
    description: '프리미엄 오마카세를 제공하는 일식 제휴 레스토랑.',
    coupons: buildCoupons('rest-003'),
    stampHistory: buildStampHistory(9),
  },
};

const toSummary = (detail: RestaurantDetail): RestaurantSummary => ({
  restaurantId: detail.restaurantId,
  name: detail.name,
  category: detail.category,
  address: detail.address,
  distanceKm: detail.distanceKm,
  imageUrl: detail.imageUrl,
  stampCount: detail.stampCount,
  stampGoal: detail.stampGoal,
  couponSummary: detail.couponSummary,
  recentUsage: detail.recentUsage,
});

const refreshCouponSummary = (detail: RestaurantDetail): void => {
  const available = detail.coupons.filter((coupon) => coupon.status === 'available').length;
  detail.couponSummary = {
    available,
    total: detail.coupons.length,
    lastUsedAt: detail.coupons
      .filter((coupon) => coupon.status === 'used')
      .sort((a, b) => (a.expiresAt < b.expiresAt ? 1 : -1))[0]?.expiresAt,
  };
};

export const affiliateMocks = {
  getCategories(): CategoryOption[] {
    return mockCategories;
  },
  listRestaurants(categoryId?: string): RestaurantSummary[] {
    const entries = Object.values(restaurantStore);
    return entries
      .filter((detail) => categoryId === undefined || categoryId === 'all' || detail.category === categoryId)
      .map(toSummary);
  },
  getRestaurantDetail(restaurantId: string): RestaurantDetail | undefined {
    const detail = restaurantStore[restaurantId];
    return detail ? { ...detail, coupons: detail.coupons.map((coupon) => ({ ...coupon })) } : undefined;
  },
  incrementStamp(restaurantId: string): RestaurantDetail | undefined {
    const detail = restaurantStore[restaurantId];
    if (!detail) return undefined;

    detail.stampCount = Math.min(detail.stampCount + 1, detail.stampGoal);
    const historyEntry: StampHistoryEntry = {
      id: `stamp-${detail.stampHistory.length + 1}`,
      accruedAt: new Date().toISOString(),
      delta: 1,
      note: '관리자 적립',
    };
    detail.stampHistory = [historyEntry, ...detail.stampHistory].slice(0, 20);

    if (detail.stampCount === 5 || detail.stampCount === 10) {
      const newCoupon: Coupon = {
        couponId: `${restaurantId}-cp-${detail.coupons.length + 1}`,
        name: detail.stampCount === 10 ? '무료 메뉴 쿠폰' : '추가 적립 쿠폰',
        expiresAt: new Date(Date.now() + 30 * 86_400_000).toISOString(),
        status: 'available',
      };
      detail.coupons = [newCoupon, ...detail.coupons];
    }

    refreshCouponSummary(detail);
    detail.recentUsage = historyEntry.accruedAt;
    return { ...detail, coupons: detail.coupons.map((coupon) => ({ ...coupon })) };
  },
  useCoupon(restaurantId: string, couponId: string): RestaurantDetail | undefined {
    const detail = restaurantStore[restaurantId];
    if (!detail) return undefined;

    const target = detail.coupons.find((coupon) => coupon.couponId === couponId);
    if (!target) return detail;

    target.status = 'used';
    refreshCouponSummary(detail);
    detail.recentUsage = new Date().toISOString();
    return { ...detail, coupons: detail.coupons.map((coupon) => ({ ...coupon })) };
  },
};
