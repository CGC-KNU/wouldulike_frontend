# UI/UX 개선 개발 계획 (앱 + 백엔드)

기준: 「UI/UX 개선 기획안 v0.2」 + 10/2 결정. 앱 = `new1`(Flutter), 백엔드 = `../wouldulike_backend`(Django).
코드 실측 결과(2026-10-09)를 반영해 기획안 요약과 다른 점은 아래 "실측 메모"에 적었다.

## 실측 메모
- `setUserId`는 이미 구현됨 (`main.dart`, `auth_service.dart` → `AnalyticsLogger.setUserId`). 남은 일은 GA4↔DB 매칭 검증뿐.
- 스탬프 한도는 **적립 개수 합계** 기준 (`coupons/service.py` `STAMP_DAILY_EARN_LIMIT`, env 기본 5, `add_stamp`).
  결정 9의 "같은 매장 하루 1회"는 **횟수** 기준이라 의미가 다르다 → 횟수 기준으로 바꾸고 1회당 1~4개는 유지하는 안으로 진행.
  (적립 개수 1~4의 원래 의도는 재민 확인 대기 항목이므로 UI 변경은 확인 후.)
- 마일리지 QR 방문 한도는 현재 "사용자 전체 하루 2회" (`mileage/service.py`, 관리자 설정값). 하루 300M 상한은 없음.
- 쿠폰 사용(`RedeemView`)은 403/409/410을 쓰지만 `code`·남은 시도 횟수가 없음. PIN 잠금(5회/10분)은 있음.
- 정책 값은 `/api/config/policy/`로 내려가므로 한도 문구는 서버 값을 따라가게 했다.

## 1단계 — 문구·데이터 결함, 정책 정합 (앱 출시 불필요 → 백엔드 우선)
| # | 영역 | 작업 | 상태 |
|---|---|---|---|
| 1-1 | 앱 | "관리자 비밀번호" → "매장 PIN", PIN 오류 문구 | 완료 |
| 1-2 | 앱 | 마일리지·쿠폰 빈 상태 문구, 한도 문구를 서버 정책 값 기반으로 | 완료 |
| 1-3 | 백 | ~~스탬프 한도 변경~~ — 변경하지 않기로 함 (현행 유지) | 취소 |
| 1-4 | 백 | ~~마일리지 하루 300M 상한~~ — 변경하지 않기로 함 (현행 유지) | 취소 |
| 1-5 | 백 | `RedeemView`·`AddStampView` 오류에 `code`(invalid_pin/pin_locked/coupon_used/coupon_expired/restaurant_mismatch)와 `attempts_left` 추가 (앱 표시는 2단계) | 백엔드 완료 |
| 1-6 | 백 | 기획전 게시 시 매장 0곳 차단, 보상명 필수·"제공" 자동 덧붙임 제거 (세틀라이트 등록 검사) | 예정 |
| 1-7 | 앱 | 스탬프 보상명 자리표시·"제공 제공" 중복 제거 (`cleanStampRewardName`, 매장 상세·지갑 공통) | 완료 |

## 2단계 — QR→쿠폰→스탬프 (앱 1회 출시)
- **진행 현황**
  - 쿠폰 사용 화면(`coupon.use`) 전체 화면화 — 완료 (`lib/coupon/redeem_pin_dialog.dart`, 시안 09 기준, 스탬프 체크는 결정 7대로 기본 꺼짐). PIN 오류 원인·남은 시도 안내 포함.
  - 매장 상세 혜택 탭(시안 11) — 완료: 쓸 쿠폰이 있으면 쿠폰 카드 맨 위, "다음 보상까지 N개 · 보상명", 스탬프 숫자 확대, 선물 아이콘은 다음 보상 칸만.
  - 지갑 스탬프 탭(시안 12) — 완료: 매장 카드를 "다음 보상 + 진행 막대"로 단순화, 보상 미등록 매장은 "준비 중".
  - 지갑 마일리지 탭(시안 13) — 완료: 쌓는 법 3줄(값은 서버 정책 `mileage.*`), 응모 없을 때 "다음 응모 ○월 ○일 ○시 시작"(`/api/raffles/`의 `next_opens_at`).
  - 홈(시안 10) 일부 — 완료: 맨 위 "내 혜택 한 줄 요약" 카드(`lib/widgets/my_benefit_summary_card.dart`), 배너 자동 넘김 5초, "1 / 2" 인디케이터. (노출 이벤트는 이미 코드에 있었음)
  - 홈 남음: 미션 항목별 바로 가기·수행 가능할 때만 노출(미션 화면 쪽 작업), 캠퍼스별 배너 풀.
  - QR 진입 분기(시안 14a·14b, 08) — 완료: 서버 `/api/mileage/qr-visit/` 응답에 `entry`(branch·스탬프 진행) 추가(`coupons/qr_entry.py`), 앱 `qr_entry_sheet.dart`(쿠폰 도착/갖고 계신 쿠폰/보상/스탬프 안내/오늘 완료), 식당 상세 위에 시트.
  - QR 규칙 보강: 쿠폰은 첫 방문에만(사용자×매장 평생 1장, 쓴 뒤·만료 뒤에도 재발급 없음, 동시 스캔은 락으로 1장). 재방문은 스탬프 적립 시트가 기본이고, 안 쓴 쿠폰이 있으면 "쿠폰 쓰고 스탬프도 찍기"(PIN 1회)로 유도.
  - 쿠폰 사용 → 사용 완료 + "스탬프도 찍을까요?"(같은 PIN 재사용, 이 화면 안에서만) — 완료.
  - 남음(앱 밖/별도): 웹 착지 `wouldulike.kr/s/{매장}`·deferred deeplink(설치 후 같은 매장 복귀), 스티커 QR 주소 확정(결정 대기), 보상 도착 전용 시트(현재는 기존 적립 완료 다이얼로그 재사용).
  - 시안 15 — 완료: (백) 푸시 사용자당 하루 1회 — 점심/저녁 쿠폰 알림은 사용자당 1건, D-2 만료 안내는 같은 날 이미 쿠폰 알림을 받은 사람 제외. (앱) 지갑 쿠폰 목록 24시간 이내 빨간 테두리(목록 [사용]·코드 입력·만료임박은 이미 있었음).
  - 시안 15 — 미착수/보류: 알림 고장 원인 진단(운영 로그 필요), 생년월일 수집(앱·서버 모두 필드 없음 — 개인정보 수집 추가라 결정 필요, 현 가입은 이미 닉네임+대학가 2항목), 직원용 1p 안내문(인쇄물; 시안에 "PIN은 매주 바뀐다"는 문구가 있어 결정 10과 충돌 — 수정 필요).
  - Castor 0단계 요청 반영: 화면 ID 라우트 이름(`config/screen_ids.dart`: store.detail·coupon.use·coupon.done·featured.detail·home.mission·wallet.coupon·sheet.coupon_arrived, 바텀시트도 screen_view), setUserId JWT 폴백, `qr_entry`·`qr_visit_result`·`featured_view` 이벤트, QR 쿠폰 발급 경로 `QR_VISIT` 분리(앱·대시보드 동일 규칙).
  - 2단계: Remote Config(`firebase_remote_config` 추가, `services/remote_text_service.dart`) — 쿠폰 사용 화면 문구·스탬프 기본값·배너 자동 넘김 초. 콘솔에 키 등록 필요.
  - 탭 화면 ID: home·store.list·my(하단 탭), wallet.coupon·wallet.stamp·wallet.mileage(지갑 안쪽 탭)을 screen_view 로 기록. 홈 블록 순서는 원격 `home_block_order`(promo,mission,featured,restaurants,banner; 빠진 블록은 뒤에 자동 보정).
  - QR 시나리오 테스트: 서버 `coupons/test_qr_scenarios.py`(API end-to-end 12건), 앱 `test/qr_scenarios_test.dart`(13건). 테스트로 발견·수정: QR 쿠폰 만료가 "받은 날 자정"이 아니라 발급일+1일 23:59(최대 2일)였던 것 → KST 당일 23:59:59 로 수정.
  - 1-6 일부: 기획전 "선별 매장 0곳" 방지는 게시 단계(세틀라이트 등록 검사)에서 막는다. 서버 쪽 "item 0개 기획전 제외"는 bannerlab 큐레이션 동작과 충돌해 되돌렸다(item 이 원래 없던 기획전은 예전처럼 내려간다). 앱은 `featured_view(store_count)` 로 0곳 진입을 계측한다.
  - 남음: 오늘 이미 적립했으면 "오늘 적립 완료" 표시(적립 현황 조회 필요), QR 진입 분기 시트, 사용 완료→스탬프 연결(PIN 재입력 없이는 서버 방문 토큰 필요).
- 백: QR 진입 API(매장+src → 분기 1~6 판정, QR 쿠폰 발급: 사용자×매장 평생 1장·당일 자정 만료, "QR 방문" 분류 분리), 쿠폰 사용 후 스탬프용 방문 토큰.
- 앱: 딥링크 `wouldulike.kr/s/{매장}?src=`, 진입 분기 시트(`sheet.coupon_arrived` 등), 쿠폰 사용 전체 화면(`coupon.use`), 사용 완료→스탬프 연결(`coupon.done`/`stamp.done`).
- 계측: QR 진입, QR 방문 결과, 스탬프 적립(쿠폰 후/단독), `coupon_redeem_attempt`, `stamp_add_attempt`.
- 스티커 QR 주소 형식은 결정 대기(1·2번) — 목적지를 서버에서 바꿀 수 있게 설계해 영향 최소화.

## 3단계 — 지갑·홈·알림·가입
지갑(실제 보상명·진행 막대·다음 응모 시각), 홈(내 혜택 요약·미션 바로가기·배너 자동 넘김·노출 이벤트), 푸시(하루 1회·쿠폰 보유자만·쿠폰 상세 딥링크, **알림 고장 수정 선행**), 가입 간소화, 실험 배정 API, Remote Config.

## 원칙
- 결정 기록 우선(스탬프 체크박스 기본 꺼짐, 고정 PIN, 위치 알림 없음 등).
- 정책 변경은 env/관리자 설정으로 되돌릴 수 있게.
- 푸시·배포·머지는 재민 승인 후.
