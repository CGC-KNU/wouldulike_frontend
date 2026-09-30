/// 대학가(상권) 목록. 백엔드 `Restaurant.CAMPUS_CHOICES`/`User.CAMPUS_CHOICES`와
/// 동일한 문자열을 그대로 사용한다(코드화하지 않음).
const List<String> kCampusOptions = ['경북대', '영남대', '계명대'];

/// 식당 탭 캠퍼스 드롭다운의 '전체' 옵션 값.
const String kCampusFilterAll = 'ALL';

bool isKnownCampus(String? value) {
  return value != null && kCampusOptions.contains(value);
}
