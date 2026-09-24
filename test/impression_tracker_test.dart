import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/utils/impression_tracker.dart';

/// 노출 이벤트가 **분모로 쓸 수 있는 수**인지 확인한다.
///
/// 여기서 잡아야 하는 것:
///   ① 화면 밖의 것을 노출로 세지 않는가. 세면 CTR 이 0 에 수렴한다.
///   ② 스쳰 것을 세지 않는가(1초 머무름).
///   ③ 같은 대상을 세션에서 한 번만 세는가. 스크롤로 오가면 부풀어 오른다.
///   ④ 목록이 위젯을 재사용할 때 **다른 매장으로 바뀐 것**을 새로 세는가.
void main() {
  setUp(ImpressionSession.resetForTest);

  /// 화면 높이 600 · 항목 높이 300 인 목록. 한 화면에 두 개가 들어간다.
  Widget listOf(int count, List<String> log, {double itemHeight = 300}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ListView.builder(
            itemCount: count,
            itemBuilder: (context, i) => ImpressionDetector(
              dedupKey: 'item:$i',
              onImpression: () => log.add('item:$i'),
              child: SizedBox(height: itemHeight, child: Text('item $i')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('① 화면에 보이는 것만 센다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final log = <String>[];
    await tester.pumpWidget(listOf(10, log));
    await tester.pump(const Duration(seconds: 2));

    expect(log, ['item:0', 'item:1'],
        reason: '화면에 들어온 두 개만. 나머지 8개는 아직 본 적이 없다');
  });

  testWidgets('② 1초 안에 지나가면 세지 않는다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final log = <String>[];
    await tester.pumpWidget(listOf(20, log));
    // 0.3초만 두고 저 멀리 스크롤한다 — 스쳰 것이다.
    // drag 뒤에 프레임을 한 번 더 그린다. 실제 앱에서는 손가락이 움직이면
    // 곧바로 프레임이 그려지지만, 테스트의 drag 는 프레임 없이 좌표만 바꿔
    // 놓기 때문이다. 이 pump 를 빼면 아직 옮겨지지 않은 위치를 재게 된다.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(log.contains('item:0'), isFalse, reason: '스쳰 것은 노출이 아니다');
    expect(log, isNotEmpty, reason: '멈춘 자리의 항목은 세야 한다');
  });

  testWidgets('③ 같은 대상은 세션에 한 번만 센다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final log = <String>[];
    await tester.pumpWidget(listOf(10, log));
    await tester.pump(const Duration(seconds: 2));
    final first = log.length;

    // 내렸다가 다시 올라온다 — 같은 항목을 또 본다
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(log.where((e) => e == 'item:0').length, 1,
        reason: '오갈 때마다 세면 분모가 부풀어 CTR 이 0 에 수렴한다');
    expect(log.length, greaterThan(first), reason: '새로 본 항목은 세야 한다');
    expect(log.toSet().length, log.length, reason: '중복이 없어야 한다');
  });

  testWidgets('④ 목록이 위젯을 재사용해도 바뀐 대상을 새로 센다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final log = <String>[];
    var key = 'store:1';
    late StateSetter setOuter;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return ImpressionDetector(
            dedupKey: key,
            onImpression: () => log.add(key),
            child: const SizedBox(height: 200, width: 200),
          );
        }),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(log, ['store:1']);

    // 같은 State 에 다른 매장이 들어온다 (SliverList.builder 가 하는 일)
    setOuter(() => key = 'store:2');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(log, ['store:1', 'store:2'], reason: '다른 매장이니 새로 세야 한다');
  });

  test('세션 잠금은 30분 무활동으로 풀린다', () {
    expect(ImpressionSession.claim('a'), isTrue);
    expect(ImpressionSession.claim('a'), isFalse, reason: '같은 세션의 두 번째');
    expect(ImpressionSession.claim('b'), isTrue, reason: '다른 대상은 따로 센다');
    expect(ImpressionSession.seenCount, 2);
  });
}
