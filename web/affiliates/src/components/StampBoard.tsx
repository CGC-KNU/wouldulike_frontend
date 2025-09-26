import React from 'react';
import styled from 'styled-components';

interface StampBoardProps {
  stampCount: number;
  stampGoal: number;
}

const Board = styled.div`
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 0.5rem;
  padding: 1rem;
  background: #F9FAFB;
  border-radius: 16px;
  border: 1px solid #E5E7EB;
`;

const Cell = styled.div<{ $filled: boolean }>`
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem 0.5rem;
  border-radius: 12px;
  border: 1px dashed ${({ $filled }) => ($filled ? '#4338CA' : '#CBD5F5')};
  background: ${({ $filled }) => ($filled ? 'rgba(79, 70, 229, 0.1)' : '#FFFFFF')};
  color: ${({ $filled }) => ($filled ? '#312E81' : '#9CA3AF')};
  font-weight: 600;
  transition: all 0.2s ease;
`;

const Legend = styled.div`
  margin-top: 0.75rem;
  display: flex;
  gap: 1.25rem;
  font-size: 0.85rem;
  color: #4B5563;
`;

const Badge = styled.span`
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.3rem 0.6rem;
  border-radius: 999px;
  background: #EEF2FF;
  color: #4338CA;
  font-weight: 600;
`;

export const StampBoard: React.FC<StampBoardProps> = ({ stampCount, stampGoal }) => {
  const cells = Array.from({ length: stampGoal }, (_, index) => index + 1);
  const milestones = [5, 10].filter((milestone) => milestone <= stampGoal);

  return (
    <div>
      <Board>
        {cells.map((value) => (
          <Cell key={value} $filled={value <= stampCount}>
            {value <= stampCount ? '★' : value}
          </Cell>
        ))}
      </Board>
      <Legend>
        {milestones.map((milestone) => (
          <Badge key={milestone}>
            {milestone}개 적립 · 쿠폰 발급
          </Badge>
        ))}
      </Legend>
    </div>
  );
};
