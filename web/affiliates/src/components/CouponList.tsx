import React from 'react';
import styled from 'styled-components';
import type { Coupon } from '../types/affiliates';

interface CouponListProps {
  coupons: Coupon[];
  onUseCoupon: (couponId: string) => void;
  isProcessing?: boolean;
}

const List = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
`;

const CouponCard = styled.div<{ $used: boolean }>`
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.85rem 1rem;
  border-radius: 12px;
  border: 1px solid ${({ $used }) => ($used ? '#E5E7EB' : '#C7D2FE')};
  background: ${({ $used }) => ($used ? '#F9FAFB' : '#EEF2FF')};
`;

const Info = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
`;

const Name = styled.span`
  font-weight: 600;
  color: #1F2937;
`;

const Meta = styled.span<{ $used: boolean }>`
  font-size: 0.8rem;
  color: ${({ $used }) => ($used ? '#9CA3AF' : '#4C1D95')};
`;

const UseButton = styled.button<{ $used: boolean }>`
  padding: 0.45rem 0.95rem;
  border-radius: 999px;
  border: none;
  background: ${({ $used }) => ($used ? '#E5E7EB' : '#4C1D95')};
  color: ${({ $used }) => ($used ? '#9CA3AF' : '#FFFFFF')};
  font-weight: 600;
  cursor: ${({ $used }) => ($used ? 'not-allowed' : 'pointer')};
  transition: transform 0.2s ease;

  &:hover {
    transform: ${({ $used }) => ($used ? 'none' : 'translateY(-1px)')};
  }
`;

export const CouponList: React.FC<CouponListProps> = ({ coupons, onUseCoupon, isProcessing }) => {
  if (!coupons.length) {
    return <Meta $used={false}>사용 가능한 쿠폰이 없습니다.</Meta>;
  }

  return (
    <List>
      {coupons.map((coupon) => {
        const used = coupon.status === 'used';
        const expires = new Date(coupon.expiresAt).toLocaleDateString();
        return (
          <CouponCard key={coupon.couponId} $used={used}>
            <Info>
              <Name>{coupon.name}</Name>
              <Meta $used={used}>만료일 {expires} · {used ? '사용완료' : '사용가능'}</Meta>
            </Info>
            <UseButton
              type="button"
              $used={used}
              onClick={() => !used && !isProcessing && onUseCoupon(coupon.couponId)}
              disabled={used || isProcessing}
            >
              {used ? '사용완료' : '사용하기'}
            </UseButton>
          </CouponCard>
        );
      })}
    </List>
  );
};
