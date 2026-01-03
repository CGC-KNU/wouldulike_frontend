import React, { useEffect, useMemo, useState } from 'react';
import styled from 'styled-components';
import {
  fetchAffiliateCategories,
  fetchAffiliateRestaurants,
  fetchRestaurantDetail,
  postCouponUse,
  postStampIncrement,
} from '../services/affiliates';
import type {
  CategoryOption,
  RestaurantDetail,
  RestaurantSummary,
} from '../types/affiliates';
import { CategoryFilter } from '../components/CategoryFilter';
import { RestaurantList } from '../components/RestaurantList';
import { RestaurantDetailPanel } from '../components/RestaurantDetailPanel';

const Page = styled.main`
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  padding: 2rem 3vw 3rem;
  background: #F3F4F6;
  min-height: 100vh;
`;

const Header = styled.header`
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
`;

const Title = styled.h1`
  margin: 0;
  font-size: 1.9rem;
  font-weight: 700;
  color: #1F2937;
`;

const Description = styled.p`
  margin: 0;
  color: #4B5563;
  font-size: 0.95rem;
`;

const Layout = styled.div`
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(0, 1.8fr);
  gap: 2rem;

  @media (max-width: 1200px) {
    grid-template-columns: 1fr;
  }
`;

const Card = styled.section`
  padding: 1.5rem;
  border-radius: 20px;
  background: #FFFFFF;
  border: 1px solid #E5E7EB;
  box-shadow: 0 16px 32px rgba(15, 23, 42, 0.08);
`;

const Placeholder = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 360px;
  border: 1px dashed #D1D5DB;
  border-radius: 16px;
  color: #9CA3AF;
  font-size: 0.95rem;
`;

const FeedbackToast = styled.div<{ $type: 'success' | 'error' }>`
  position: fixed;
  bottom: 24px;
  right: 24px;
  padding: 0.85rem 1.4rem;
  border-radius: 12px;
  color: #F9FAFB;
  background: ${({ $type }) => ($type === 'success' ? '#16A34A' : '#DC2626')};
  box-shadow: 0 12px 24px rgba(15, 23, 42, 0.18);
  font-weight: 600;
  z-index: 1500;
`;

const LoadingState = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 3rem 1rem;
  color: #6B7280;
`;

interface FeedbackState {
  type: 'success' | 'error';
  message: string;
}

export const AffiliatePage: React.FC = () => {
  const [categories, setCategories] = useState<CategoryOption[]>([]);
  const [selectedCategoryId, setSelectedCategoryId] = useState<string>('all');
  const [restaurants, setRestaurants] = useState<RestaurantSummary[]>([]);
  const [selectedRestaurantId, setSelectedRestaurantId] = useState<string | null>(null);
  const [restaurantDetail, setRestaurantDetail] = useState<RestaurantDetail | null>(null);
  const [isLoadingList, setIsLoadingList] = useState<boolean>(true);
  const [isLoadingDetail, setIsLoadingDetail] = useState<boolean>(false);
  const [isStamping, setIsStamping] = useState<boolean>(false);
  const [isUsingCoupon, setIsUsingCoupon] = useState<boolean>(false);
  const [feedback, setFeedback] = useState<FeedbackState | null>(null);

  useEffect(() => {
    let cancelled = false;

    const loadCategories = async () => {
      try {
        const data = await fetchAffiliateCategories();
        if (cancelled) return;
        setCategories(data);
        const initialCategory = data.find((category) => category.id === 'all')?.id ?? data[0]?.id ?? 'all';
        setSelectedCategoryId(initialCategory);
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setFeedback({ type: 'error', message: '카테고리 정보를 불러오지 못했습니다.' });
        }
      }
    };

    loadCategories();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!selectedCategoryId) return;
    let cancelled = false;

    const loadRestaurants = async () => {
      setIsLoadingList(true);
      try {
        const data = await fetchAffiliateRestaurants(selectedCategoryId === 'all' ? undefined : selectedCategoryId);
        if (cancelled) return;
        setRestaurants(data);
        if (data.length) {
          const nextSelection = data.some((item) => item.restaurantId === selectedRestaurantId)
            ? selectedRestaurantId
            : data[0].restaurantId;
          setSelectedRestaurantId(nextSelection ?? null);
        } else {
          setSelectedRestaurantId(null);
          setRestaurantDetail(null);
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setFeedback({ type: 'error', message: '제휴 매장 목록을 불러오지 못했습니다.' });
        }
      } finally {
        if (!cancelled) {
          setIsLoadingList(false);
        }
      }
    };

    loadRestaurants();
    return () => {
      cancelled = true;
    };
  }, [selectedCategoryId]);

  useEffect(() => {
    if (!selectedRestaurantId) return;
    let cancelled = false;

    const loadDetail = async () => {
      setIsLoadingDetail(true);
      try {
        const detail = await fetchRestaurantDetail(selectedRestaurantId);
        if (!cancelled) {
          setRestaurantDetail(detail);
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setFeedback({ type: 'error', message: '매장 정보를 불러오지 못했습니다.' });
        }
      } finally {
        if (!cancelled) {
          setIsLoadingDetail(false);
        }
      }
    };

    loadDetail();
    return () => {
      cancelled = true;
    };
  }, [selectedRestaurantId]);

  useEffect(() => {
    if (!feedback) return;
    const timer = setTimeout(() => setFeedback(null), 2500);
    return () => clearTimeout(timer);
  }, [feedback]);

  const handleStampCollect = async (pin: string) => {
    if (!restaurantDetail) return;
    setIsStamping(true);
    try {
      const updated = await postStampIncrement(restaurantDetail.restaurantId, pin);
      setRestaurantDetail(updated);
      setRestaurants((prev) =>
        prev.map((item) => (item.restaurantId === updated.restaurantId ? { ...item, ...updated } : item)),
      );
      setFeedback({ type: 'success', message: '스탬프가 적립되었습니다.' });
    } catch (error) {
      console.error(error);
      setFeedback({ type: 'error', message: error instanceof Error ? error.message : '스탬프 적립에 실패했습니다.' });
      throw error;
    } finally {
      setIsStamping(false);
    }
  };

  const handleCouponUse = async (couponId: string, pin: string) => {
    if (!restaurantDetail) return;
    setIsUsingCoupon(true);
    try {
      const updated = await postCouponUse(restaurantDetail.restaurantId, couponId, pin);
      setRestaurantDetail(updated);
      setRestaurants((prev) =>
        prev.map((item) => (item.restaurantId === updated.restaurantId ? { ...item, ...updated } : item)),
      );
      setFeedback({ type: 'success', message: '쿠폰 사용이 완료되었습니다.' });
    } catch (error) {
      console.error(error);
      setFeedback({ type: 'error', message: error instanceof Error ? error.message : '쿠폰 사용에 실패했습니다.' });
      throw error;
    } finally {
      setIsUsingCoupon(false);
    }
  };

  const detailPanel = useMemo(() => {
    if (isLoadingDetail) {
      return <LoadingState>매장 정보를 불러오는 중입니다...</LoadingState>;
    }
    if (!restaurantDetail) {
      return <Placeholder>매장을 선택하면 상세 혜택 정보를 확인할 수 있습니다.</Placeholder>;
    }
    return (
      <RestaurantDetailPanel
        detail={restaurantDetail}
        onStampCollect={(pin) => handleStampCollect(pin)}
        onCouponUse={(couponId, pin) => handleCouponUse(couponId, pin)}
        isStamping={isStamping}
        isProcessingCoupon={isUsingCoupon}
      />
    );
  }, [isLoadingDetail, restaurantDetail, isStamping, isUsingCoupon]);

  return (
    <Page>
      <Header>
        <Title>제휴 · 혜택 매장</Title>
        <Description>
          제휴된 매장의 혜택과 스탬프 적립 현황을 확인하세요. 관리자 PIN을 통해 스탬프 적립과 쿠폰 사용을 시뮬레이션할 수 있습니다.
        </Description>
      </Header>

      <CategoryFilter
        categories={categories}
        selectedCategoryId={selectedCategoryId}
        onSelect={setSelectedCategoryId}
      />

      <Layout>
        <Card>
          {isLoadingList ? (
            <LoadingState>제휴 매장을 불러오는 중입니다...</LoadingState>
          ) : (
            <RestaurantList restaurants={restaurants} onSelect={(id) => setSelectedRestaurantId(id)} />
          )}
        </Card>
        {detailPanel}
      </Layout>

      {feedback ? <FeedbackToast $type={feedback.type}>{feedback.message}</FeedbackToast> : null}
    </Page>
  );
};
