import React from 'react';
import styled from 'styled-components';
import type { CategoryOption } from '../types/affiliates';

interface CategoryFilterProps {
  categories: CategoryOption[];
  selectedCategoryId: string;
  onSelect: (categoryId: string) => void;
}

const Container = styled.div`
  display: flex;
  gap: 0.75rem;
  overflow-x: auto;
  padding: 0.5rem 0.25rem 1rem;

  &::-webkit-scrollbar {
    height: 6px;
  }

  &::-webkit-scrollbar-thumb {
    background: #d1d5db;
    border-radius: 999px;
  }
`;

const Chip = styled.button<{ $active: boolean }>`
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.55rem 1rem;
  border-radius: 999px;
  border: 1px solid ${({ $active }) => ($active ? '#312E81' : '#E5E7EB')};
  background: ${({ $active }) => ($active ? '#EEF2FF' : '#FFFFFF')};
  color: ${({ $active }) => ($active ? '#1E1B4B' : '#4B5563')};
  font-size: 0.9rem;
  white-space: nowrap;
  cursor: pointer;
  transition: all 0.2s ease;

  &:hover {
    border-color: #4338CA;
    color: #312E81;
  }
`;

const Icon = styled.span`
  font-size: 1.1rem;
`;

export const CategoryFilter: React.FC<CategoryFilterProps> = ({ categories, selectedCategoryId, onSelect }) => {
  return (
    <Container>
      {categories.map((category) => (
        <Chip
          key={category.id}
          $active={selectedCategoryId === category.id}
          onClick={() => onSelect(category.id)}
          type="button"
        >
          {category.icon ? <Icon>{category.icon}</Icon> : null}
          {category.label}
        </Chip>
      ))}
    </Container>
  );
};
