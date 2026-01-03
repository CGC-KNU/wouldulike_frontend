import { affiliateMocks } from '../mocks/affiliateMocks';
import type { CategoryOption, RestaurantDetail, RestaurantSummary } from '../types/affiliates';

const PIN_CODE = '0000';

export const fetchAffiliateCategories = async (): Promise<CategoryOption[]> => {
  // TODO: backend 연결 시 구현 (restaurants_test 연동)
  return Promise.resolve(affiliateMocks.getCategories());
};

export const fetchAffiliateRestaurants = async (categoryId?: string): Promise<RestaurantSummary[]> => {
  // TODO: backend 연결 시 구현 (restaurants_test 연동)
  return Promise.resolve(affiliateMocks.listRestaurants(categoryId));
};

export const fetchRestaurantDetail = async (restaurantId: string): Promise<RestaurantDetail> => {
  // TODO: backend 연결 시 구현 (restaurants_test 연동)
  const detail = affiliateMocks.getRestaurantDetail(restaurantId);
  if (!detail) {
    throw new Error('Restaurant not found');
  }
  return Promise.resolve(detail);
};

export const postStampIncrement = async (
  restaurantId: string,
  adminPin: string,
): Promise<RestaurantDetail> => {
  // TODO: backend 연결 시 구현 (restaurants_test 연동)
  if (adminPin !== PIN_CODE) {
    return Promise.reject(new Error('관리자 PIN이 올바르지 않습니다.'));
  }
  const updated = affiliateMocks.incrementStamp(restaurantId);
  if (!updated) {
    throw new Error('적립에 실패했습니다. 매장 정보를 확인해주세요.');
  }
  return Promise.resolve(updated);
};

export const postCouponUse = async (
  restaurantId: string,
  couponId: string,
  adminPin: string,
): Promise<RestaurantDetail> => {
  // TODO: backend 연결 시 구현 (restaurants_test 연동)
  if (adminPin !== PIN_CODE) {
    return Promise.reject(new Error('관리자 PIN이 올바르지 않습니다.'));
  }
  const updated = affiliateMocks.useCoupon(restaurantId, couponId);
  if (!updated) {
    throw new Error('쿠폰 사용 처리에 실패했습니다.');
  }
  return Promise.resolve(updated);
};
