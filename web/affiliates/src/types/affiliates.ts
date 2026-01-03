export type CouponStatus = 'available' | 'used';

export interface CouponSummary {
  available: number;
  total: number;
  lastUsedAt?: string;
}

export interface Coupon {
  couponId: string;
  name: string;
  expiresAt: string;
  status: CouponStatus;
}

export interface StampHistoryEntry {
  id: string;
  accruedAt: string;
  delta: number;
  note?: string;
}

export interface RestaurantSummary {
  restaurantId: string;
  name: string;
  category: string;
  address: string;
  distanceKm: number;
  imageUrl: string;
  stampCount: number;
  stampGoal: number;
  couponSummary: CouponSummary;
  recentUsage?: string;
}

export interface RestaurantDetail extends RestaurantSummary {
  description?: string;
  coupons: Coupon[];
  stampHistory: StampHistoryEntry[];
}

export interface CategoryOption {
  id: string;
  label: string;
  icon?: string;
}
