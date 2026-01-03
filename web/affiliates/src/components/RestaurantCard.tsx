import React from 'react';
import styled from 'styled-components';
import type { RestaurantSummary } from '../types/affiliates';

interface RestaurantCardProps {
  restaurant: RestaurantSummary;
  onSelect: (restaurantId: string) => void;
}

const Card = styled.article`
  display: flex;
  flex-direction: column;
  border: 1px solid #E5E7EB;
  border-radius: 16px;
  overflow: hidden;
  background: #FFFFFF;
  box-shadow: 0 8px 16px rgba(31, 41, 55, 0.06);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
  cursor: pointer;

  &:hover {
    transform: translateY(-4px);
    box-shadow: 0 12px 24px rgba(49, 46, 129, 0.15);
  }
`;

const Thumbnail = styled.img`
  width: 100%;
  height: 180px;
  object-fit: cover;
`;

const Content = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  padding: 1rem 1.25rem 1.5rem;
`;

const TitleRow = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
`;

const Name = styled.h3`
  margin: 0;
  font-size: 1.125rem;
  font-weight: 700;
  color: #1F2937;
`;

const Meta = styled.p`
  margin: 0;
  font-size: 0.9rem;
  color: #6B7280;
`;

const StatRow = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
`;

const ProgressBar = styled.div`
  height: 8px;
  border-radius: 999px;
  background: #EEF2FF;
  overflow: hidden;
`;

const Progress = styled.div<{ $percent: number }>`
  height: 100%;
  width: ${({ $percent }) => `${Math.min(100, $percent)}%`};
  background: linear-gradient(90deg, #4338CA, #4F46E5);
  transition: width 0.3s ease;
`;

const StatLabel = styled.span`
  font-size: 0.85rem;
  color: #4338CA;
  font-weight: 600;
`;

const Footer = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.8rem;
  color: #9CA3AF;
`;

export const RestaurantCard: React.FC<RestaurantCardProps> = ({ restaurant, onSelect }) => {
  const progressPercent = (restaurant.stampCount / restaurant.stampGoal) * 100;
  const recentDate = restaurant.recentUsage
    ? new Date(restaurant.recentUsage).toLocaleDateString()
    : '최근 이용 없음';

  return (
    <Card onClick={() => onSelect(restaurant.restaurantId)}>
      <Thumbnail src={restaurant.imageUrl} alt={restaurant.name} />
      <Content>
        <TitleRow>
          <Name>{restaurant.name}</Name>
          <Meta>{restaurant.category} · {restaurant.address}</Meta>
          <Meta>거리 {restaurant.distanceKm.toFixed(1)}km</Meta>
        </TitleRow>
        <StatRow>
          <div>
            <StatLabel>스탬프 {restaurant.stampCount}/{restaurant.stampGoal}</StatLabel>
            <ProgressBar>
              <Progress $percent={progressPercent} />
            </ProgressBar>
          </div>
          <Meta>
            쿠폰 보유 {restaurant.couponSummary.available}/{restaurant.couponSummary.total}
          </Meta>
        </StatRow>
        <Footer>최근 사용일: {recentDate}</Footer>
      </Content>
    </Card>
  );
};
