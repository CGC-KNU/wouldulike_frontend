import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 이벤트 이름이 **Firebase 가 받아 주는 모양**인지, 그리고 `analytics_events.dart`
/// 가 「이 앱이 찍는 것의 목록」 구실을 계속 하는지 본다.
///
/// 규칙을 어기면 Firebase 는 **조용히 버린다.** 앱은 오류를 내지 않고 BigQuery
/// 에는 그 이벤트가 아예 없다 — 릴리스하고 며칠 뒤 "왜 0 이지"로 발견하게 되는
/// 종류다. 그래서 이름은 돌기 전에 여기서 막는다.
///
/// 목록은 **소스를 읽어서** 만든다. 손으로 관리하는 배열을 두면 새 이벤트를
/// 빠뜨려 검사에서 빠지고, 그게 바로 이 파일이 막으려는 문제다.
void main() {
  final source = File('lib/config/analytics_events.dart').readAsStringSync();

  final events = RegExp(r"AnalyticsEvent\._\('([a-zA-Z0-9_]+)'\)")
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toList();
  final params = RegExp(r"static const String param\w+ = '([a-zA-Z0-9_]+)';")
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toList();

  final shape = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
  const reserved = ['firebase_', 'google_', 'ga_'];

  void checkName(String name, String what) {
    expect(name, matches(shape), reason: '$what $name — 영문자로 시작해 영문/숫자/밑줄만');
    expect(name.length, lessThanOrEqualTo(40),
        reason: '$what $name — ${name.length}자. 40자를 넘으면 버려진다');
    for (final r in reserved) {
      expect(name.startsWith(r), isFalse,
          reason: '$what $name — $r 은 Firebase 예약 접두사다');
    }
  }

  test('목록을 읽어 냈다', () {
    // 정규식이 헛돌면 아래 검사가 전부 통과해 버린다 — 먼저 그걸 막는다.
    expect(events.length, greaterThan(40), reason: '이벤트를 못 읽었다');
    expect(params.length, greaterThan(40), reason: '파라미터를 못 읽었다');
  });

  test('이벤트 이름이 Firebase 규칙을 지킨다', () {
    for (final e in events) {
      checkName(e, '이벤트');
    }
  });

  test('파라미터 키가 Firebase 규칙을 지킨다', () {
    for (final p in params) {
      checkName(p, '파라미터');
    }
  });

  test('같은 이름을 두 상수가 쓰지 않는다', () {
    final dupes = events.where((n) => events.where((m) => m == n).length > 1).toSet();
    expect(dupes, isEmpty,
        reason: '이름이 겹치면 두 뜻이 한 칸에 섞여 들어와 분해할 수 없다: $dupes');
  });

  test('이벤트를 문자열로 찍는 곳이 없다', () {
    // logEvent 가 AnalyticsEvent 만 받으므로 지금은 컴파일에서 막힌다. 이 검사는
    // 그 문을 누가 다시 열었을 때(String 오버로드 등) 알려 주는 쪽이다.
    // 문자열로 찍으면 오타가 나도 컴파일이 통과하고 데이터만 사라진다.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      // 선언 파일 자신은 뺀다 — 주석에 "이렇게 쓰면 안 된다"는 예시가 들어 있다.
      if (f.path.endsWith('analytics_events.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in RegExp(r"logEvent\(\s*'([a-z0-9_]+)'").allMatches(text)) {
        offenders.add('${f.path} → ${m.group(1)}');
      }
    }
    expect(offenders, isEmpty,
        reason: '이벤트 이름은 analytics_events.dart 에 선언하고 상수로 부른다:\n'
            '${offenders.join('\n')}');
  });
}
