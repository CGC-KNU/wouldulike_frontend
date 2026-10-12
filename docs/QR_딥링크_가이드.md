# 매장 QR 딥링크 가이드

매장 테이블 스티커·포스터·텐트에 넣는 QR 주소와, 그 QR이 앱에서 동작하는 방식을 정리한다.
(브릿지 저장소: `wouldulike_deeplink` — https://cgc-knu.github.io/wouldulike_deeplink/)

## 1. 한 줄 요약

매장마다 **아래 주소 하나**를 QR로 만든다. `id`만 매장 번호로 바꾼다.

```
https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id={restaurant_id}&src={인쇄물}
```

- `type=restaurant` 고정
- `id` = 매장의 `restaurant_id` (숫자)
- `src` = 인쇄물 종류: `sticker`(테이블 스티커) · `poster`(포스터) · `tent`(텐트). 일반 QR이면 `qr`.

예) 라라더(317) 테이블 스티커
`https://cgc-knu.github.io/wouldulike_deeplink/?type=restaurant&id=317&src=sticker`

## 2. 매장별 주소 (포스터 7개 매장 예시, 스티커용)

| restaurant_id | 매장 | QR 주소 |
|---|---|---|
| 317 | 라라더 | `…/?type=restaurant&id=317&src=sticker` |
| 316 | 웃찌커피 | `…/?type=restaurant&id=316&src=sticker` |
| 144 | 주비두루 향기롭다 | `…/?type=restaurant&id=144&src=sticker` |
| 320 | BHC 경대북문점 | `…/?type=restaurant&id=320&src=sticker` |
| 30 | 고니식탁 | `…/?type=restaurant&id=30&src=sticker` |
| 146 | 닭동가리 경북대점 | `…/?type=restaurant&id=146&src=sticker` |
| 145 | 통통주먹구이 경북대점 | `…/?type=restaurant&id=145&src=sticker` |

(`…` = `https://cgc-knu.github.io/wouldulike_deeplink`. 다른 매장은 같은 식으로 `id`만 바꾼다.)

**매장 번호 찾는 법**: 세틀라이트 매장 정보 또는 DB `restaurants_affiliate.restaurant_id`. 앱 딥링크 문서(`docs/딥링크.md`)의 "식당 상세" 예시(`id=56`)와 같은 번호다.

## 3. 인쇄물별 src

| src | 용도 | 서버 저장(`MileageEvent.source`) | GA4 `link_source` |
|---|---|---|---|
| `sticker` | 테이블 스티커 | `qr` | `sticker` |
| `poster` | 포스터 | `qr` | `poster` |
| `tent` | 테이블 텐트 | `qr` | `tent` |
| `qr` | 구분 없는 QR | `qr` | `qr` |
| (없음) | 옛 인쇄물 | 빈 값 | `none` |

인쇄물별 효과는 GA4에서 `link_source`로 나눠 본다. src가 없는 옛 QR도 쿠폰·적립은 똑같이 동작한다(출처 기록만 비어 있음).
허용 문자는 영문 소문자·숫자·`_`·`-` 20자까지.

## 4. 폰에서 일어나는 일

| 상황 | 동작 |
|---|---|
| 앱 설치됨 · Android | 브릿지가 `intent://` 로 앱을 열고, 앱이 없으면 같은 줄에서 Play 스토어로 보낸다. |
| 앱 설치됨 · iOS | 브릿지가 `wouldulike://restaurant/{id}?src=…` 로 앱을 연다. 앱이 열리면 스토어로 튕기지 않는다. |
| 앱 없음 · iOS | 1.5초 뒤 App Store로 이동. |
| 앱 없음 · Android | Play 스토어로 이동. |
| PC에서 열림 | 이동하지 않고 "휴대폰에서 QR을 다시 찍어 주세요" 안내. |

앱이 열리면 해당 매장 상세 위에 **QR 진입 시트**가 뜬다.
- 첫 방문: 쿠폰 도착(받은 날 23:59까지, 매장당 평생 1장)
- 이후: 스탬프 적립 시트 + 안 쓴 쿠폰이 있으면 "쿠폰 쓰고 스탬프도 찍기"

자동으로 안 열리는 환경(일부 인앱 브라우저)을 위해 브릿지 화면에 **"우주라이크 앱 열기"·"앱 설치하러 가기" 버튼**이 함께 있다.

## 5. 인쇄할 때

- 오류 정정 수준 **M 이상**, 여백(quiet zone) **4칸 이상** 유지.
- 최소 한 변 **2.5cm 이상** 권장(테이블에서 폰으로 바로 인식되는 크기).
- 주소가 길어 QR이 촘촘하다. 포스터 등 작은 인쇄는 더 크게 뽑거나 짧은 주소(향후 `wouldulike.kr/s/{id}`)를 쓴다.
- 인쇄 전 **실제 폰으로 한 번 스캔**해 매장 화면이 뜨는지 확인한다(아래 체크리스트).

## 6. 인쇄 전 체크리스트

1. iPhone 카메라로 스캔 → Safari에서 앱 열기 확인 → 해당 매장 상세 + QR 시트.
2. Android 카메라(또는 Google 렌즈)로 스캔 → 앱 열림 → 같은 화면.
3. 카카오톡 인앱 브라우저·네이버 앱의 QR 리더로 스캔 → 앱이 열리거나 "앱 열기" 버튼이 보이는지.
4. 앱 삭제 후 스캔 → 스토어로 이동하는지.
5. 같은 QR을 **두 번째** 스캔 → 쿠폰 재발급 없이 스탬프 시트가 뜨는지.
6. GA4(DebugView)에서 `qr_entry`(`link_source`=인쇄물 값), `qr_visit_result` 확인.

## 7. 알려진 한계 · 다음 단계

- **https 주소를 앱이 직접 받지는 못한다.** 지금은 브릿지를 거쳐 커스텀 스킴(`wouldulike://`)으로 넘어간다. iOS Universal Links / Android App Links를 쓰려면 도메인(`wouldulike.kr`)의 `apple-app-site-association`·`assetlinks.json`과 앱 네이티브 설정·출시가 필요하다.
- **설치 후 같은 매장으로 복귀(deferred deeplink)는 없다.** 앱이 없던 사람은 설치 뒤 홈으로 시작한다. Firebase Dynamic Links는 종료되어 Branch/AppsFlyer 등 외부 서비스 또는 Android 설치 리퍼러가 필요하다.
- 스티커 QR 주소 형식(`wouldulike.kr/s/{id}`)은 결정 대기 중. 확정되면 브릿지에서 같은 규칙으로 받도록 확장한다.
