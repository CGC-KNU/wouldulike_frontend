# Flutter 파트너 모드 구현 기록

## 앱 구조

- `partner/partner_access_controller.dart`: 기존 partner/me와 BFF config로 확인한다. 기본 숨김, 계정·세션 세대 격리, 중복 요청 합치기, 25초 주기/30초 만료, background 가림·foreground 재확인을 제공한다. 매장 목록은 이름·ID만 사용한다.
- `services/app_session.dart`: 로그인 시작·완료, 명시적 로그아웃, 연결 해제, ApiClient 만료 처리의 동기 신호다. 이전 세션의 요청·토큰 갱신·로그인 응답은 새 계정에 반영하지 않는다. 로그인 화면의 중복 JWT 저장을 제거했다.
- `partner/partner_api_client.dart`: AppConfigService.dashboardUrl을 검증하고 legacy Vercel 주소를 canonical HTTPS 주소로 정규화한다. 앱 JWT 갱신은 기존 ApiClient를 공유한다. 일반 API의 Django baseUrl은 유지한다. 인증 헤더 redirect를 금지하고, 결과가 불명확한 쓰기는 통신 실패만으로 재전송하지 않는다.
- `partner/partner_shell.dart`, `partner/partner_pages.dart`: 일반 4탭과 분리된 6메뉴(홈·매장·혜택·콘텐츠·리포트·플랜). 매장·계정 문맥 변경 시 늦은 응답을 폐기한다. 일반 모드 복귀, 편집 폐기 확인, 권한 해제 강제 정리, 다매장 재선택을 제공한다.
- `main2.dart`: 앱 진입 시 점주 권한과 BFF 활성화 설정을 확인하고 점주이면 파트너 모드를 자동으로 연다. 확인 중에는 로딩 화면을 표시해 일반 홈 팝업이 먼저 뜨지 않게 한다. 일반 모드로 전환한 뒤에는 주기적 권한 검사나 앱 재개만으로 자동 복귀하지 않는다. 앱을 새로 열면 점주 기본 진입을 다시 적용한다. 명시적 딥링크는 지정한 일반 앱 화면을 우선한다.
- `partner/widgets/partner_mode_toggle.dart`: 점주에게만 일반 홈 상단과 파트너 홈·매장 선택 상단에 사장님 모드 토글을 표시한다. 일반 모드에서 다시 들어갈 때도 권한을 재검증하고, 파트너에서 나올 때는 편집 폐기 확인을 거친다. 마이페이지는 기존 탭 기능을 사용하며 하단 바의 손잡이·세로 전환 제스처는 제거했다.
- 리포트는 BFF가 돌려준 허용 출처·정확한 `/r/<40자리 hex>`만 기존 url_launcher로 연다. JWT URL·웹 쿠키·새 읽음 배지는 없다.

## 의존성·플랫폼 변경

| 항목 | 변경·이유 |
| --- | --- |
| `image_picker` | 1.2.0 고정. 매장 사진을 갤러리에서 한 장씩 선택하고 1600px·quality 85로 제한한다. JPEG/PNG/WebP 확인 후 BFF presign → S3 직접 PUT → 매장 저장으로 구분한다. 최대 5장, 순서 변경·삭제를 제공한다. |
| iOS Info.plist | NSPhotoLibraryUsageDescription: 매장 사진 선택 목적. 카메라·마이크 권한은 추가하지 않는다. iOS CocoaPods 반영과 실기기 권한 흐름은 macOS에서 확인해야 한다. |
| Android | 시스템 사진 선택 사용. 저장소·카메라 권한을 추가하지 않는다. 기존 minSdk는 유지한다. flutter build apk --debug --no-pub 빌드에 성공했다. 실기기 권한·사진 선택은 별도 확인한다. |
| 데스크톱 등록 파일 | flutter pub get으로 생성되는 image_picker/file_selector 플러그인 등록을 반영한다. |
| 환경변수·URL scheme | Flutter 신규 변수·scheme 없음. 기존 dashboard_url만 검증·정규화한다. 허용 출처는 https://app.wouldulike.kr 및 기존 legacy Vercel 주소다. preview 출처는 운영 앱에서 허용하지 않는다. |

사진 패키지 설정 근거: [image_picker 공식 안내](https://pub.dev/packages/image_picker/versions/1.2.0).

## 설정·검증·미검증

- Next.js 서버 전용 `APP_OWNER_MODE_ENABLED`는 기본 false이며 true/1만 활성이다. 점주 권한 및 인증된 config 조회가 성공하고 enabled=true일 때만 자동 진입과 홈 토글을 제공한다. 비로그인·비점주·설정 비활성·조회 실패 시에는 일반 모드를 사용한다. 설정 변경에는 Next.js 재배포·반영 확인이 필요하다. 실제 운영 설정은 변경하지 않았다.
- 파트너 테스트는 권한·계정 경계·업무 화면·뒤로가기·로그아웃 정리와 반응형 렌더링을 포함한다. `test/partner_entry_test.dart`에서 점주 자동 진입, 일반 홈 토글 왕복, 수동 전환 후 유지, 비점주·설정 비활성·오류 시 일반 모드, 앱 재진입과 딥링크 우선을 검증한다.
- `dart analyze lib/partner lib/services/api_client.dart lib/services/auth_service.dart lib/services/app_session.dart`: 지적 없음. 전체 analyze의 기존 지적과 전체 Flutter 테스트 실패는 상위 명세 §16에서 구분한다.
- 실제 점주 계정으로 Django/BFF 왕복, 사진 업로드·저장 실패, PIN 잠금·최초 설정, 신청 저장/Slack, 웹 리포트 복귀, Android/iOS 시스템 제스처·스크린리더 실기기는 아직 확인하지 않았다. 앱·서버 배포와 커밋은 수행하지 않았다.

## 파트너 디자인 반영

- 웹의 `globals.css`, `PartnerHome.tsx`, `BottomNav.tsx`, 매장·리포트·플랜 화면을 기준으로 네이비 `#050072`, 페리윙클 `#6366E0`, 배경 `#F4F4F9`, Pretendard, 18px 카드와 얇은 테두리·그림자를 반영했다.
- `partner/partner_design.dart`의 전용 테마·패널·배지·빈 상태·아이콘 메뉴를 파트너 화면에 적용했다. 홈은 매장 헤더, PIN, 반응형 지표 격자, 전월 비교, 활동 배지로 구성한다. 매장·혜택에는 둥근 입력 필드, 스탬프 보상 표시를, 리포트에는 준비 진행률을, 플랜에는 앰버·보라 그라데이션과 현재 이용 표시를 적용했다.
- `partner_preview_test.dart`는 6개 화면을 390px, 320px/글자 2배, 1024px에서 끝까지 스크롤하며 검사한다. `build/castor_shots/partner.design.0.png`부터 `.5.png`까지 화면 캡처를 생성하며 혜택·플랜 하단은 `.2.bottom.png`, `.5.bottom.png`로 저장한다. 캡처는 예시 데이터를 사용한다.
- 실기기에서의 최종 시각 확인은 별도로 필요하다.

## 점주 자동 진입의 검은 화면 점검

- 빠른 권한 응답이 스플래시 → 메인 라우트 교체 애니메이션 중에 도착하는 경우를 재현했다. 메인 전환이 끝난 뒤 파트너 라우트를 열고, 대기 중 딥링크·세션 변경이 있으면 진입을 취소한다. 파트너 라우트의 snapshot 전환은 비활성화했다.
- Android 12 이상에서는 첫 화면 준비 후 네이티브 스플래시 뷰를 명시적으로 제거한다. Kotlin 변경은 APK 재빌드가 필요하다.
- 연결된 API 37 에뮬레이터에서 검은 화면일 때에도 점주 홈 위젯과 데이터는 생성되어 있었고 Android 시작 화면 레이어가 남아 있었다. Dart 수정·APK 재설치만으로는 해소되지 않았으며, 앱 데이터를 유지한 에뮬레이터 재부팅 후 실제 점주 홈 표시와 일반 모드 토글 왕복을 확인했다. 렌더러 변경만으로 해결되는 현상은 아니었으며 운영 렌더러 설정은 바꾸지 않았다.
- 확인: 파트너·딥링크 테스트 36개 통과, 진입 코드·재현 테스트 정적 분석 지적 없음, `flutter build apk --debug --no-pub` 성공. 실물 기기 검증은 별도로 필요하다.
