import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoggingIn = false;

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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('로그인이 취소되었어요.')),
            );
            return;
          }
          // 기타 오류 시 계정(웹) 로그인으로 폴백
          debugPrint('[Kakao] loginWithKakaoTalk failed: ' + error.toString());
          token = await UserApi.instance.loginWithKakaoAccount();
          debugPrint('[Kakao] loginWithKakaoAccount fallback success');
        }
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
        debugPrint('[Kakao] loginWithKakaoAccount success (talk not installed)');
      }

      final prefs = await SharedPreferences.getInstance();
      final guestUuid = prefs.getString('user_uuid');
      final data = await AuthService.loginWithKakao(
        token.accessToken,
        guestUuid: guestUuid,
      );

      await prefs.setString('kakao_access_token', token.accessToken);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카카오 로그인 실패: $e')),
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
