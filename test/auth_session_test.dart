import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/services/app_session.dart';
import 'package:new1/services/auth_service.dart';
import 'package:new1/partner/partner_access_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AppSession.changing = false;
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'account-a',
      'jwt_refresh_token': 'refresh-a',
      'user_id': 1,
    });
  });
  tearDown(() => AppSession.endChange());

  Future<Map<String, dynamic>> login(String provider) => provider == 'kakao'
      ? AuthService.loginWithKakao('provider-token')
      : AuthService.loginWithApple('provider-token');
  http.Response success() => http.Response(
      jsonEncode({
        'token': {'access': 'new-access', 'refresh': 'new-refresh'},
        'user': {'id': 2, 'nickname': 'new-user'},
      }),
      200);

  for (final provider in ['kakao', 'apple']) {
    for (final failure in [
      'network',
      'server',
      'json',
      'missing_token',
      'relogin'
    ]) {
      test('$provider $failure 실패 후 세션 확인을 재개한다', () async {
        await http.runWithClient(() async {
          await expectLater(login(provider), throwsA(isA<Exception>()));
        },
            () => MockClient((_) async {
                  return switch (failure) {
                    'network' => throw http.ClientException('offline'),
                    'server' => http.Response('{}', 500),
                    'json' => http.Response('invalid json', 200),
                    'missing_token' => http.Response('{}', 200),
                    _ => http.Response('{"relogin_required":true}', 401),
                  };
                }));
        expect(AppSession.changing, isFalse);
        var loaded = false;
        final access = PartnerAccessController(loadUser: () async {
          loaded = true;
          return null;
        });
        await access.check();
        expect(loaded, isTrue);
        access.dispose();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('jwt_access_token'),
            failure == 'relogin' ? null : 'account-a');
      });
    }

    for (final status in [200, 401]) {
      test('$provider 이전 $status 응답이 새 로그인과 토큰을 건드리지 않는다', () async {
        final entered = Completer<void>(),
            response = Completer<http.Response>();
        await http.runWithClient(() async {
          final pending = login(provider);
          final expectation = expectLater(pending, throwsStateError);
          await entered.future;
          final newer = AppSession.beginChange();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_access_token', 'account-b');
          await prefs.setString('jwt_refresh_token', 'refresh-b');
          response.complete(status == 200
              ? success()
              : http.Response('{"relogin_required":true}', 401));
          await expectation;
          expect(prefs.getString('jwt_access_token'), 'account-b');
          expect(prefs.getString('jwt_refresh_token'), 'refresh-b');
          expect(AppSession.revision.value, newer);
          expect(AppSession.changing, isTrue);
        },
            () => MockClient((_) {
                  entered.complete();
                  return response.future;
                }));
      });
    }

    test('$provider 성공 시 토큰 저장을 마친 뒤 전환을 종료한다', () async {
      await http.runWithClient(
          () => login(provider), () => MockClient((_) async => success()));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_access_token'), 'new-access');
      expect(prefs.getString('jwt_refresh_token'), 'new-refresh');
      expect(prefs.getInt('user_id'), 2);
      expect(AppSession.changing, isFalse);
    });

    for (final next in ['login', 'logout']) {
      for (final outcome in ['success', 'relogin', 'network']) {
        test('$provider 이전 $outcome 결과가 완료된 새 $next 세션을 변경하지 않는다', () async {
          final entered = Completer<void>();
          final response = Completer<http.Response>();
          await http.runWithClient(() async {
            final old = login(provider);
            final expectation = expectLater(
                old,
                outcome == 'network'
                    ? throwsA(isA<Exception>())
                    : throwsStateError);
            await entered.future;
            if (next == 'login') {
              await login(provider);
            } else {
              await AuthService.logout();
            }
            final revision = AppSession.revision.value;
            if (outcome == 'network') {
              response.completeError(http.ClientException('late offline'));
            } else {
              response.complete(outcome == 'success'
                  ? success()
                  : http.Response('{"relogin_required":true}', 401));
            }
            await expectation;
            final prefs = await SharedPreferences.getInstance();
            expect(prefs.getString('jwt_access_token'),
                next == 'login' ? 'new-access' : null);
            expect(prefs.getString('jwt_refresh_token'),
                next == 'login' ? 'new-refresh' : null);
            expect(AppSession.revision.value, revision);
            expect(AppSession.changing, isFalse);
          },
              () => MockClient((_) {
                    if (!entered.isCompleted) {
                      entered.complete();
                      return response.future;
                    }
                    return Future.value(success());
                  }));
        });
      }
    }
  }

  for (final action in ['logout', 'unlink']) {
    test('$action 통신 실패도 로컬 세션 전환을 종료한다', () async {
      await http.runWithClient(
          () =>
              action == 'logout' ? AuthService.logout() : AuthService.unlink(),
          () => MockClient((_) async => throw http.ClientException('offline')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_access_token'), isNull);
      expect(prefs.getString('jwt_refresh_token'), isNull);
      expect(AppSession.changing, isFalse);
    });
  }
}
