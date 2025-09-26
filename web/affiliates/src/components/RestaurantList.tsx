import React from 'react';
import styled from 'styled-components';
import type { RestaurantSummary } from '../types/affiliates';
import { RestaurantCard } from './RestaurantCard';

interface RestaurantListProps {
  restaurants: RestaurantSummary[];
  onSelect: (restaurantId: string) => void;
}

const Grid = styled.div`
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1.5rem;
  padding: 0.5rem 0;
`;

const EmptyState = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 3rem 1rem;
  border: 1px dashed #D1D5DB;
  border-radius: 16px;
  color: #6B7280;
  font-size: 0.95rem;
`;

export const RestaurantList: React.FC<RestaurantListProps> = ({ restaurants, onSelect }) => {
  if (!restaurants.length) {
    return <EmptyState>선택한 카테고리에 해당하는 제휴 매장이 없습니다.</EmptyState>;
  }

  return (
    <Grid>
      {restaurants.map((restaurant) => (
        <RestaurantCard key={restaurant.restaurantId} restaurant={restaurant} onSelect={onSelect} />
      ))}
    </Grid>
  );
};
