import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      debugPrint('[Kakao] isKakaoTalkInstalled: $talkInstalled');
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
          debugPrint('[Kakao] loginWithKakaoTalk failed: $error');
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
      debugPrint('[Kakao] login error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFF1c203c),
      body: SafeArea(
        child: _isLoggingIn
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFEE500),
                ),
              )
            : Stack(
                children: [
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    bottom: screenHeight * 0.3,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Would',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.87),
                                    fontSize: 50,
                                    fontFamily: 'Alkatra',
                                    fontWeight: FontWeight.w400,
                                    height: 1.20,
                                    letterSpacing: -0.50,
                                  ),
                                ),
                                TextSpan(
                                  text: 'U',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.87),
                                    fontSize: 60,
                                    fontFamily: 'Alkatra',
                                    fontWeight: FontWeight.w500,
                                    height: 1,
                                    letterSpacing: -0.50,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Like',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.87),
                                    fontSize: 50,
                                    fontFamily: 'Alkatra',
                                    fontWeight: FontWeight.w500,
                                    height: 1.20,
                                    letterSpacing: -0.50,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 5 * (screenHeight / 844)),
                          Text(
                            '내 주변 모든 혜택을 우주라이크와 함께',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFDADCFF),
                              fontSize: 18,
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                              height: 3.33,
                              letterSpacing: -0.50,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: screenHeight * 0.344,
                    child: Container(
                      width: double.infinity,
                      decoration: const ShapeDecoration(
                        color: Color(0xFFF5F5FA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(100),
                            topRight: Radius.circular(100),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            SizedBox(height: 90 * (screenHeight / 844)),
                            SizedBox(
                              width: double.infinity,
                              height: 47.2,
                              child: ElevatedButton(
                                onPressed: _loginWithKakao,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFffe812),
                                  foregroundColor: const Color(0xFF000000),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  padding: EdgeInsets.only(
                                    top: 3,
                                    bottom: 12,
                                    left: 0,
                                    right: 0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 26,
                                      height: 24,
                                      child: Stack(
                                        children: [
                                          SvgPicture.asset(
                                            'assets/icons/kakaotalk.svg',
                                            width: 26,
                                            height: 24,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Transform.translate(
                                      offset: Offset(0, -6),
                                      child: Text(
                                        '카카오로  간편로그인 ',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 19,
                                          fontFamily: 'Pretendard',
                                          fontWeight: FontWeight.w700,
                                          height: 3.16,
                                          letterSpacing: -0.50,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 17 * (screenHeight / 844)),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacementNamed(context, '/main');
                              },
                              child: SizedBox(
                                width: 168,
                                height: 41,
                                child: Text(
                                  '지금은 괜찮아요',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: const Color(0xFF1C203C),
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                    height: 3.75,
                                    letterSpacing: -0.50,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}