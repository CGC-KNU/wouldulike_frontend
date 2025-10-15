import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack, kIsWeb;
import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';

class KakaoShareService {
  KakaoShareService._();

  static const String _androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.coggiri.new1&pcampaignid=web_share';
  static const String _iosStoreUrl =
      'https://apps.apple.com/kr/app/wouldulike/id6740640251';

  static Uri _resolvePlatformStoreUrl() {
    if (!kIsWeb && Platform.isIOS) {
      return Uri.parse(_iosStoreUrl);
    }
    return Uri.parse(_androidStoreUrl);
  }

  static TextTemplate buildTemplate({required String referralCode}) {
    final Uri androidUri = Uri.parse(_androidStoreUrl);
    final Uri iosUri = Uri.parse(_iosStoreUrl);
    final Uri platformUri = _resolvePlatformStoreUrl();

    final buffer = StringBuffer()
      ..writeln('WouldULike 친구초대 혜택 안내')
      ..writeln('내 추천코드: $referralCode')
      ..writeln()
      ..writeln('Android 설치: $androidUri')
      ..writeln('iOS 설치: $iosUri');

    return TextTemplate(
      text: buffer.toString(),
      link: Link(
        mobileWebUrl: platformUri,
        webUrl: platformUri,
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
