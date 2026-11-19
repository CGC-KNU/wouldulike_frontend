import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/partner/partner_access_controller.dart';
import 'package:new1/services/app_session.dart';

const ownerMe = {
  'is_partner': true,
  'stores': [
    {'restaurant_id': 1, 'name': '테스트 매장'}
  ]
};
void main() {
  setUp(() {
    AppSession.changing = false;
  });
  testWidgets('권한 확인 지연 및 설정 실패 중에는 점주를 노출하지 않는다', (tester) async {
    final me = Completer<Map<String, dynamic>>();
    final enabled = Completer<bool>();
    final c = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () => me.future,
        loadEnabled: () => enabled.future);
    c.start();
    await tester.pump();
    expect(c.isOwner, false);
    me.complete(ownerMe);
    await tester.pump();
    expect(c.isOwner, false);
    enabled.complete(false);
    await tester.pump();
    expect(c.isOwner, false);
    c.dispose();
  });
  testWidgets('비로그인·비점주·잘못된 매장 목록은 config를 조회하지 않는다', (tester) async {
    for (final data in [
      null,
      {'is_partner': false, 'stores': []},
      {
        'is_partner': true,
        'stores': [
          {'restaurant_id': -1, 'name': 'bad'}
        ]
      }
    ]) {
      var configCalls = 0;
      final c = PartnerAccessController(
          loadUser: () async => data == null ? null : 1,
          loadMe: () async => data!,
          loadEnabled: () async {
            configCalls++;
            return true;
          });
      c.start();
      await tester.pump();
      expect(c.isOwner, false);
      expect(configCalls, 0);
      c.dispose();
    }
  });
  testWidgets('중복 확인은 합치고 계정 변경 후 늦은 응답은 폐기한다', (tester) async {
    final me = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () {
          calls++;
          return me.future;
        },
        loadEnabled: () async => true);
    c.start();
    final a = c.check(), b = c.check();
    expect(identical(a, b), true);
    await tester.pump();
    AppSession.beginChange();
    me.complete(ownerMe);
    await tester.pump();
    expect(c.isOwner, false);
    expect(c.stores, isEmpty);
    expect(calls, 1);
    c.dispose();
    AppSession.endChange();
  });
  testWidgets('25초 정기 갱신은 깜빡이지 않고 30초 유효기간 후 가린다', (tester) async {
    final second = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () => ++calls == 1 ? Future.value(ownerMe) : second.future,
        loadEnabled: () async => true);
    c.start();
    await tester.pump();
    expect(c.isOwner, true);
    await tester.pump(const Duration(seconds: 25));
    expect(c.isOwner, true);
    await tester.pump(const Duration(seconds: 5));
    expect(c.isOwner, false);
    second.complete(ownerMe);
    await tester.pump();
    expect(c.isOwner, false);
    c.dispose();
  });
  testWidgets('background에서는 가리고 foreground에서 다시 확인한다', (tester) async {
    final resumed = Completer<Map<String, dynamic>>();
    var calls = 0;
    final c = PartnerAccessController(
        loadUser: () async => 1,
        loadMe: () => ++calls == 1 ? Future.value(ownerMe) : resumed.future,
        loadEnabled: () async => true);
    c.start();
    await tester.pump();
    expect(c.isOwner, true);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(c.isOwner, false);
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(c.isOwner, false);
    resumed.complete(ownerMe);
    await tester.pump();
    expect(c.isOwner, true);
    c.dispose();
  });
}
