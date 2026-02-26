# AdMob 설정 가이드

## 2단계: 광고 단위 생성 (AdMob 콘솔)

### 1. AdMob 콘솔 접속
[https://admob.google.com](https://admob.google.com) → 로그인

### 2. 앱 추가 (아직 없다면)
- **앱** → **앱 추가** → **Android** / **iOS** 선택
- 패키지명(Bundle ID) 입력:
  - Android: `com.coggiri.new1`
  - iOS: `com.coggiri.wouldulike0117` (또는 실제 Bundle ID)

### 3. 광고 단위 생성
1. 앱 선택 → **광고 단위** → **광고 단위 추가**
2. **배너** 선택 → 이름 입력 (예: "메인 배너") → **광고 단위 만들기**
3. (선택) **전면 광고** 또는 **보상형 광고** 추가

### 4. 광고 단위 ID 확인
생성 후 표시되는 **광고 단위 ID**를 복사해 두세요.
- 형식: `ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy`

---

## 7단계: 실제 광고 ID로 교체

앱 배포 후 `lib/config/ad_config.dart`에서:

1. **앱 ID 교체** (AndroidManifest.xml, Info.plist)
   - AdMob 콘솔 → 앱 설정 → 앱 ID 확인
   - Android: `android/app/src/main/AndroidManifest.xml`
   - iOS: `ios/Runner/Info.plist`

2. **광고 단위 ID 교체** (`lib/config/ad_config.dart`)
   - `bannerAdUnitId` 반환값의 `ca-app-pub-XXXXX/XXXXX` 부분을 실제 ID로 교체
   - `interstitialAdUnitId`, `rewardedAdUnitId`도 동일하게 교체

---

## 테스트 광고 ID (개발용)

현재 개발 모드에서는 Google 공식 테스트 ID를 사용 중입니다.
- 배포 시 반드시 실제 ID로 교체하세요.
