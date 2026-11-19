import 'package:url_launcher/url_launcher.dart';

class PartnerReportLauncher {
  static Uri validate(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        !{'app.wouldulike.kr', 'wouldulike-dashboard.vercel.app'}
            .contains(uri.host) ||
        !RegExp(r'^/r/[0-9a-f]{40}$').hasMatch(uri.path) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('올바르지 않은 리포트 주소입니다.');
    }
    return uri;
  }

  static Future<void> open(String url) async {
    final uri = validate(url);
    final mode = await supportsLaunchMode(LaunchMode.inAppBrowserView)
        ? LaunchMode.inAppBrowserView
        : LaunchMode.externalApplication;
    if (!await launchUrl(uri, mode: mode)) throw Exception('리포트를 열지 못했습니다.');
  }
}
