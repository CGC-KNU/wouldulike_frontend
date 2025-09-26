import React, { useCallback, useState } from 'react';
import styled from 'styled-components';
import type { RestaurantDetail } from '../types/affiliates';
import { StampBoard } from './StampBoard';
import { CouponList } from './CouponList';

interface RestaurantDetailProps {
  detail: RestaurantDetail;
  onStampCollect: (pin: string) => Promise<void>;
  onCouponUse: (couponId: string, pin: string) => Promise<void>;
  isStamping: boolean;
  isProcessingCoupon: boolean;
}

interface PinModalState {
  visible: boolean;
  mode: 'stamp' | 'coupon';
  couponId?: string;
}

const Wrapper = styled.section`
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  padding: 1.75rem;
  border-radius: 20px;
  border: 1px solid #E5E7EB;
  background: #FFFFFF;
  box-shadow: 0 20px 40px rgba(67, 56, 202, 0.08);
`;

const Hero = styled.div`
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 1.5rem;
  align-items: center;

  @media (max-width: 960px) {
    grid-template-columns: 1fr;
  }
`;

const HeroImage = styled.img`
  width: 100%;
  height: 200px;
  object-fit: cover;
  border-radius: 16px;
`;

const HeroContent = styled.div`
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
`;

const HeroTitle = styled.h2`
  margin: 0;
  font-size: 1.75rem;
  font-weight: 700;
  color: #1F2937;
`;

const HeroMeta = styled.span`
  font-size: 0.95rem;
  color: #4B5563;
`;

const SectionTitle = styled.h3`
  margin: 0 0 0.75rem;
  font-size: 1.1rem;
  font-weight: 700;
  color: #312E81;
`;

const Section = styled.div`
  display: flex;
  flex-direction: column;
  gap: 1rem;
`;

const Actions = styled.div`
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
`;

const PrimaryButton = styled.button`
  padding: 0.65rem 1.25rem;
  border-radius: 12px;
  border: none;
  background: linear-gradient(135deg, #4338CA, #6366F1);
  color: #FFFFFF;
  font-weight: 600;
  cursor: pointer;
  box-shadow: 0 10px 20px rgba(67, 56, 202, 0.18);
  transition: transform 0.2s ease;

  &:hover {
    transform: translateY(-2px);
  }

  &:disabled {
    opacity: 0.6;
    cursor: not-allowed;
    transform: none;
  }
`;

const ModalBackdrop = styled.div`
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
`;

const ModalCard = styled.div`
  width: min(360px, 92vw);
  background: #FFFFFF;
  border-radius: 16px;
  padding: 1.75rem;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  box-shadow: 0 20px 40px rgba(15, 23, 42, 0.2);
`;

const ModalTitle = styled.h4`
  margin: 0;
  font-size: 1.125rem;
  font-weight: 700;
  color: #1F2937;
`;

const ModalDescription = styled.p`
  margin: 0;
  font-size: 0.9rem;
  color: #6B7280;
`;

const PinInput = styled.input`
  padding: 0.65rem 0.75rem;
  border-radius: 10px;
  border: 1px solid #D1D5DB;
  font-size: 1rem;
  letter-spacing: 0.35rem;
  text-align: center;
`;

const ModalActions = styled.div`
  display: flex;
  gap: 0.75rem;
  justify-content: flex-end;
`;

const SecondaryButton = styled.button`
  padding: 0.55rem 1.1rem;
  border-radius: 10px;
  border: 1px solid #E5E7EB;
  background: #FFFFFF;
  color: #4B5563;
  font-weight: 500;
  cursor: pointer;
`;

const ErrorText = styled.span`
  font-size: 0.8rem;
  color: #DC2626;
`;

const Placeholder = styled.div`
  padding: 1.5rem;
  border-radius: 12px;
  border: 1px dashed #D1D5DB;
  background: #F9FAFB;
  color: #9CA3AF;
  font-size: 0.9rem;
`;

export const RestaurantDetailPanel: React.FC<RestaurantDetailProps> = ({
  detail,
  onStampCollect,
  onCouponUse,
  isStamping,
  isProcessingCoupon,
}) => {
  const [modalState, setModalState] = useState<PinModalState>({ visible: false, mode: 'stamp' });
  const [pinValue, setPinValue] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [localProcessing, setLocalProcessing] = useState(false);

  const openStampModal = useCallback(() => {
    setModalState({ visible: true, mode: 'stamp' });
    setPinValue('');
    setError(null);
  }, []);

  const openCouponModal = useCallback((couponId: string) => {
    setModalState({ visible: true, mode: 'coupon', couponId });
    setPinValue('');
    setError(null);
  }, []);

  const closeModal = useCallback(() => {
    setModalState((prev) => ({ ...prev, visible: false }));
    setPinValue('');
    setError(null);
    setLocalProcessing(false);
  }, []);

  const handleSubmit = useCallback(async () => {
    if (!pinValue.trim()) {
      setError('관리자 PIN을 입력해주세요.');
      return;
    }

    setLocalProcessing(true);

    try {
      if (modalState.mode === 'stamp') {
        await onStampCollect(pinValue);
      } else if (modalState.mode === 'coupon' && modalState.couponId) {
        await onCouponUse(modalState.couponId, pinValue);
      }
      closeModal();
    } catch (err) {
      setError(err instanceof Error ? err.message : '알 수 없는 오류가 발생했습니다.');
      setLocalProcessing(false);
    }
  }, [pinValue, modalState, onStampCollect, onCouponUse, closeModal]);

  return (
    <Wrapper>
      <Hero>
        <HeroImage src={detail.imageUrl} alt={detail.name} />
        <HeroContent>
          <HeroTitle>{detail.name}</HeroTitle>
          <HeroMeta>{detail.category} · {detail.address}</HeroMeta>
          <HeroMeta>거리 {detail.distanceKm.toFixed(1)}km</HeroMeta>
          <HeroMeta>스탬프 {detail.stampCount}/{detail.stampGoal} · 쿠폰 {detail.couponSummary.available}/{detail.couponSummary.total}</HeroMeta>
          {detail.description ? <HeroMeta>{detail.description}</HeroMeta> : null}
          <Actions>
            <PrimaryButton type="button" onClick={openStampModal} disabled={isStamping}>
              스탬프 적립하기
            </PrimaryButton>
          </Actions>
        </HeroContent>
      </Hero>

      <Section>
        <SectionTitle>혜택</SectionTitle>
        <StampBoard stampCount={detail.stampCount} stampGoal={detail.stampGoal} />
        <CouponList
          coupons={detail.coupons}
          onUseCoupon={openCouponModal}
          isProcessing={isProcessingCoupon}
        />
      </Section>

      <Section>
        <SectionTitle>매장정보</SectionTitle>
        <Placeholder>매장 상세 정보는 추후 API 연동 시 제공됩니다.</Placeholder>
      </Section>

      {modalState.visible ? (
        <ModalBackdrop>
          <ModalCard>
            <ModalTitle>{modalState.mode === 'stamp' ? '스탬프 적립' : '쿠폰 사용'}</ModalTitle>
            <ModalDescription>
              관리자 PIN을 입력해 {modalState.mode === 'stamp' ? '스탬프를 적립' : '쿠폰을 사용'}해 주세요.
            </ModalDescription>
            <PinInput
              type="password"
              maxLength={4}
              value={pinValue}
              onChange={(event) => setPinValue(event.target.value)}
              placeholder="0000"
            />
            {error ? <ErrorText>{error}</ErrorText> : null}
            <ModalActions>
              <SecondaryButton type="button" onClick={closeModal} disabled={localProcessing}>
                취소
              </SecondaryButton>
              <PrimaryButton type="button" onClick={handleSubmit} disabled={localProcessing}>
                확인
              </PrimaryButton>
            </ModalActions>
          </ModalCard>
        </ModalBackdrop>
      ) : null}
    </Wrapper>
  );
};
