# Flutter 파트너 모드 구현 기록

## 앱 구조

- `partner/partner_access_controller.dart`: 기존 partner/me와 BFF config로 확인한다. 기본 숨김, 계정·세션 세대 격리, 중복 요청 합치기, 25초 주기/30초 만료, background 가림·foreground 재확인을 제공한다. 매장 목록은 이름·ID만 사용한다.
- `services/app_session.dart`: 로그인 시작·완료, 명시적 로그아웃, 연결 해제, ApiClient 만료 처리의 동기 신호다. 이전 세션의 요청·토큰 갱신·로그인 응답은 새 계정에 반영하지 않는다. 로그인 화면의 중복 JWT 저장을 제거했다.
- `partner/partner_api_client.dart`: AppConfigService.dashboardUrl을 검증하고 legacy Vercel 주소를 canonical HTTPS 주소로 정규화한다. 앱 JWT 갱신은 기존 ApiClient를 공유한다. 일반 API의 Django baseUrl은 유지한다. 인증 헤더 redirect를 금지하고, 결과가 불명확한 쓰기는 통신 실패만으로 재전송하지 않는다.
- `partner/partner_shell.dart`, `partner/partner_pages.dart`: 일반 4탭과 분리된 6메뉴(홈·매장·혜택·콘텐츠·리포트·플랜). 매장·계정 문맥 변경 시 늦은 응답을 폐기한다. 일반 모드 복귀, 편집 폐기 확인, 권한 해제 강제 정리, 다매장 재선택을 제공한다.
- `widgets/liquid_glass_bottom_bar.dart`: optional onOwnerMode가 있을 때만 손잡이·세로 인식기를 생성한다. 마이페이지 위 8px 노출, 별도 48×44 접근 영역, 위로 48px/가로의 1.5배 조건. 기존 탭·가로 드래그와 일반 딥링크 리스너를 유지한다. my.dart의 무조건 외부 dashboard 메뉴는 제거했다.
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

- Next.js 서버 전용 `APP_OWNER_MODE_ENABLED`는 기본 false이며 true/1만 활성이다. 인증된 config 조회가 성공하고 enabled=true일 때만 트리거를 표시한다. 설정 변경에는 Next.js 재배포·반영 확인이 필요하다. 실제 운영 설정은 변경하지 않았다.
- `flutter test --no-pub test/partner_access_test.dart test/partner_mode_test.dart test/partner_transport_test.dart test/partner_pages_test.dart test/partner_preview_test.dart test/partner_shell_test.dart`: 22개 통과. 권한·제스처·계정 경계·업무 화면·뒤로가기·로그아웃 정리와 홈·손잡이 렌더링을 포함한다.
- `dart analyze lib/partner lib/services/api_client.dart lib/services/auth_service.dart lib/services/app_session.dart`: 지적 없음. 전체 analyze의 기존 지적과 전체 Flutter 테스트 실패는 상위 명세 §16에서 구분한다.
- 실제 점주 계정으로 Django/BFF 왕복, 사진 업로드·저장 실패, PIN 잠금·최초 설정, 신청 저장/Slack, 웹 리포트 복귀, Android/iOS 시스템 제스처·스크린리더 실기기는 아직 확인하지 않았다. 앱·서버 배포와 커밋은 수행하지 않았다.
