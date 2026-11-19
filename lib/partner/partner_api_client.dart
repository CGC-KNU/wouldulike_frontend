import '../config/analytics_events.dart';
import '../utils/analytics_logger.dart';
import 'dart:convert';
import '../services/api_client.dart';
import '../services/app_config_service.dart';

class PartnerApiException implements Exception {
  const PartnerApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => message;
}

class PartnerApiClient {
  static Uri canonicalOrigin(String configured) {
    final uri = Uri.parse(configured);
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !{'app.wouldulike.kr', 'wouldulike-dashboard.vercel.app'}
            .contains(uri.host)) {
      throw const FormatException('지원하지 않는 사장님 서비스 주소입니다.');
    }
    return Uri.parse('https://app.wouldulike.kr');
  }

  Future<Map<String, dynamic>> request(String route,
      {int? restaurantId,
      String method = 'GET',
      Map<String, dynamic>? body}) async {
    if (!RegExp(r'^[a-z0-9/-]+$').hasMatch(route)) throw ArgumentError('route');
    final uri = canonicalOrigin(AppConfigService.dashboardUrl).replace(
      path: '/api/app/owner/$route',
      queryParameters:
          restaurantId == null ? null : {'restaurant_id': '$restaurantId'},
    );
    final response =
        await ApiClient.ownerRequest(uri, method: method, body: body)
            .timeout(const Duration(seconds: 40));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('응답을 읽지 못했습니다.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AnalyticsLogger.logEvent(AnalyticsEvents.partnerRequestFailed,
          parameters: {
            'status': response.statusCode,
            'operation': route.startsWith('reports/') ? 'report_open' : route
          });
      throw PartnerApiException(
          response.statusCode,
          decoded['code']?.toString() ?? '',
          decoded['detail']?.toString() ?? '요청을 처리하지 못했습니다.');
    }
    return decoded;
  }
}
