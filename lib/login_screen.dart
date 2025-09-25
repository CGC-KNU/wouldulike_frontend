import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoggingIn = false;
  bool _isDialogOpen = false;

  Future<void> _openStore(String packageName) async {
    final market = Uri.parse('market://details?id=$packageName');
    final web = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    try {
      if (await canLaunchUrl(market)) {
        await launchUrl(market, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _showCanceledHelpDialog({required bool talkInstalled}) async {
    if (_isDialogOpen) return;
    _isDialogOpen = true;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그인이 취소되었어요'),
        content: Text(
          talkInstalled
              ? '다시 시도해 주세요. 반복되면 카카오톡/브라우저 업데이트 또는 캐시 삭제 후 재시도해 주세요.'
              : '기기에 KakaoTalk이 없으면 웹 로그인(Chrome Custom Tabs) 경로로 진행되어 취소로 끝날 수 있어요. KakaoTalk 또는 Chrome 설치/업데이트 후 다시 시도해 주세요.',
        ),
        actions: [
          if (!talkInstalled)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openStore('com.kakao.talk');
              },
              child: const Text('KakaoTalk 설치'),
            ),
          if (!talkInstalled)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openStore('com.android.chrome');
              },
              child: const Text('Chrome 설치'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    _isDialogOpen = false;
  }

  Future<void> _loginWithKakao() async {
    setState(() => _isLoggingIn = true);
    try {
      final talkInstalled = await isKakaoTalkInstalled();
      debugPrint('[Kakao] isKakaoTalkInstalled: ' + talkInstalled.toString());
      OAuthToken token;

      if (talkInstalled) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
          debugPrint('[Kakao] loginWithKakaoTalk success');
        } catch (error) {
          // 사용자가 권한 화면에서 취소한 경우
          if (error is PlatformException && error.code == 'CANCELED') {
            if (!mounted) return;
            setState(() => _isLoggingIn = false);
            await _showCanceledHelpDialog(talkInstalled: talkInstalled);
            return;
          }
          // 기타 오류 시 계정(웹) 로그인으로 폴백
          debugPrint('[Kakao] loginWithKakaoTalk failed: ' + error.toString());
          token = await UserApi.instance.loginWithKakaoAccount();
          debugPrint('[Kakao] loginWithKakaoAccount fallback success');
        }
      } else {
        try {
          token = await UserApi.instance.loginWithKakaoAccount();
          debugPrint('[Kakao] loginWithKakaoAccount success (talk not installed)');
        } on PlatformException catch (e) {
          if (e.code == 'CANCELED') {
            if (!mounted) return;
            setState(() => _isLoggingIn = false);
            await _showCanceledHelpDialog(talkInstalled: false);
            return;
          }
          rethrow;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final guestUuid = prefs.getString('user_uuid');
      final data = await AuthService.loginWithKakao(
        token.accessToken,
        guestUuid: guestUuid,
      );

      await prefs.setString('kakao_access_token', token.accessToken);
      await prefs.setBool('kakao_logged_in', true);
      await prefs.setString('jwt_access_token', data['token']['access']);
      await prefs.setString('jwt_refresh_token', data['token']['refresh']);
      await prefs.setInt('user_id', data['user']['id']);
      await prefs.setString('user_nickname', data['user']['nickname'] ?? '');
      await prefs.setString(
        'user_profile_image_url',
        data['user']['profile_image_url'] ?? '',
      );

      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      final msg = e.toString().contains('Auth server')
          ? '서버 로그인 오류가 발생했어요. 잠시 후 다시 시도해 주세요.'
          : '카카오 로그인 실패: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      debugPrint('[Kakao] login error: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoggingIn
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: _loginWithKakao,
                    child: const Text('카카오로 로그인'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/main');
                    },
                    child: const Text('로그인 없이 이용하기'),
                  ),
                ],
              ),
      ),
    );
  }
}
