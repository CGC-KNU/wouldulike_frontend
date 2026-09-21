import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';

class KakaoShareService {
  KakaoShareService._();

  // 수신자 기기의 OS를 서버에서 감지해 앱스토어/플레이스토어로 보내주는 리다이렉트 URL.
  // (공유하는 사람 기기가 아니라 링크를 여는 사람 기기 기준으로 스토어가 갈려야 하므로
  // 클라이언트에서 Platform.isIOS로 미리 정하지 않고 서버 리다이렉트를 사용한다.)
  static const String _installRedirectUrl =
      'https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app/download/';

  static TextTemplate buildTemplate({required String referralCode}) {
    final Uri installUri = Uri.parse(_installRedirectUrl);

    final buffer = StringBuffer()
      ..writeln('🎁 WouldULike 친구초대 혜택')
      ..writeln()
      ..writeln('내 추천코드 [$referralCode] 를 입력하면')
      ..writeln('나와 친구 모두에게 제휴 맛집 할인 쿠폰을 드려요!');

    return TextTemplate(
      text: buffer.toString(),
      link: Link(
        mobileWebUrl: installUri,
        webUrl: installUri,
      ),
      buttonTitle: '앱 설치하기',
    );
  }

  static Future<void> shareInvite(
    BuildContext context, {
    required String referralCode,
  }) async {
    final template = buildTemplate(referralCode: referralCode);
    try {
      final bool isKakaoTalkInstalled =
          await ShareClient.instance.isKakaoTalkSharingAvailable();
      if (isKakaoTalkInstalled) {
        final Uri uri =
            await ShareClient.instance.shareDefault(template: template);
        await ShareClient.instance.launchKakaoTalk(uri);
        return;
      }
      final Uri webShareUri =
          await WebSharerClient.instance.makeDefaultUrl(template: template);
      await launchUrl(webShareUri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      debugPrint('Kakao share failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('카카오톡 공유에 실패했어요. 잠시 후 다시 시도해주세요.'),
        ),
      );
    }
  }
}
