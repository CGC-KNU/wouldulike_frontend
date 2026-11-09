import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/services/app_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppSession.changing = false;
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'app-access',
      'jwt_refresh_token': 'app-refresh',
      'user_id': 1,
      'access_expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    });
  });
  final uri = Uri.parse(
      'https://app.wouldulike.kr/api/app/owner/benefit-requests?restaurant_id=1');
  test('점주 403은 일반 앱 토큰을 변경하거나 세션을 종료하지 않는다', () async {
    final revision = AppSession.revision.value;
    final result = await ApiClient.ownerRequest(uri,
        method: 'POST', body: {'action': 'OTHER', 'note': '문의'},
        transport: MockClient((req) async {
      expect(req.followRedirects, false);
      expect(req.headers['authorization'], 'Bearer app-access');
      return http.Response('{"code":"owner_access_revoked"}', 403);
    }));
    expect(result.statusCode, 403);
    expect(
        (await SharedPreferences.getInstance()).getString('jwt_access_token'),
        'app-access');
    expect(AppSession.revision.value, revision);
  });
  test('쓰기 통신 실패를 자동 재전송하지 않는다', () async {
    var calls = 0;
    await expectLater(
        ApiClient.ownerRequest(uri, method: 'POST',
            transport: MockClient((_) async {
          calls++;
          throw http.ClientException('timeout');
        })),
        throwsA(isA<http.ClientException>()));
    expect(calls, 1);
  });
  test('로그아웃 이후 도착한 응답을 폐기한다', () async {
    final received = Completer<void>(), response = Completer<http.Response>();
    final pending = ApiClient.ownerRequest(uri, transport: MockClient((_) {
      received.complete();
      return response.future;
    }));
    await received.future;
    AppSession.beginChange();
    final expectation = expectLater(pending, throwsStateError);
    response.complete(http.Response('{}', 200));
    await expectation;
    AppSession.endChange();
  });
  test('임의 출처로 앱 JWT를 전송하지 않는다', () async {
    var calls = 0;
    await expectLater(
        ApiClient.ownerRequest(
            Uri.parse('https://evil.test/api/app/owner/home'),
            transport: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        })),
        throwsArgumentError);
    expect(calls, 0);
  });

  test('이전 세션의 늦은 인증 예외가 새 계정 토큰을 지우지 않는다', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final pending =
        ApiClient.ownerRequest(uri, transport: MockClient((_) async {
      entered.complete();
      await release.future;
      throw const ApiAuthException('old session');
    }));
    await entered.future;
    final prefs = await SharedPreferences.getInstance();
    AppSession.beginChange();
    await prefs.setString('jwt_access_token', 'account-b');
    await prefs.setString('jwt_refresh_token', 'refresh-b');
    AppSession.endChange();
    final revision = AppSession.revision.value;
    final expectation = expectLater(pending, throwsStateError);
    release.complete();
    await expectation;
    expect(prefs.getString('jwt_access_token'), 'account-b');
    expect(prefs.getString('jwt_refresh_token'), 'refresh-b');
    expect(AppSession.revision.value, revision);
  });
  test('세션 정리 시작 신호 중 새 로그인이 발생하면 이전 정리를 중단한다', () async {
    final prefs = await SharedPreferences.getInstance();
    var switched = false;
    void switchAccount() {
      if (!AppSession.changing || switched) return;
      switched = true;
      unawaited(prefs.setString('jwt_access_token', 'account-b'));
      unawaited(prefs.setString('jwt_refresh_token', 'refresh-b'));
      AppSession.endChange();
    }

    AppSession.revision.addListener(switchAccount);
    try {
      await expectLater(
          ApiClient.ownerRequest(uri, transport: MockClient((_) async {
            await prefs.remove('jwt_refresh_token');
            throw const ApiAuthException('expired');
          })),
          throwsA(isA<ApiAuthException>()));
      expect(switched, true);
      expect(prefs.getString('jwt_access_token'), 'account-b');
      expect(prefs.getString('jwt_refresh_token'), 'refresh-b');
      expect(AppSession.changing, false);
    } finally {
      AppSession.revision.removeListener(switchAccount);
    }
  });
}
