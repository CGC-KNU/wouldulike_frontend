import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:new1/services/api_client.dart';
import 'package:new1/partner/partner_access_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('LAB에서는 권한 조회 전에 파트너 진입을 차단한다', () async {
    var requests = 0;
    final access = PartnerAccessController(loadUser: () async {
      requests++;
      return 1;
    });
    expect(await access.check(), isFalse);
    expect(requests, 0);
    expect(access.isOwner, isFalse);
    access.dispose();
  }, skip: !ApiClient.isLab);

  test('LAB 토큰은 직접 ownerRequest를 호출해도 운영 서버로 전송되지 않는다', () async {
    SharedPreferences.setMockInitialValues({'jwt_access_token': 'lab-token'});
    var requests = 0;
    await expectLater(
        ApiClient.ownerRequest(
            Uri.parse('https://app.wouldulike.kr/api/app/owner/config'),
            transport: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        })),
        throwsStateError);
    expect(requests, 0);
    expect(
        (await SharedPreferences.getInstance()).getString('jwt_access_token'),
        'lab-token');
  }, skip: !ApiClient.isLab);
}
