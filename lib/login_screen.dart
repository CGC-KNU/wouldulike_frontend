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
<<<<<<< HEAD
    const backgroundColor = Color(0xFF10163A);
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ) ??
        const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        );
    const subtitleStyle = TextStyle(
      color: Color(0xCCFFFFFF),
      fontSize: 16,
      height: 1.5,
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _isLoggingIn
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 96),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('WouldULike', style: titleStyle),
                        const SizedBox(height: 16),
                        const Text(
                          '내 주변 모든 혜택을 우주라이크와 함께',
                          style: subtitleStyle,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loginWithKakao,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEE500),
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    '톡',
                                    style: TextStyle(
                                      color: Color(0xFFFEE500),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text('카카오로 간편로그인'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/main');
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xCCFFFFFF),
                            textStyle: const TextStyle(fontSize: 14),
                          ),
                          child: const Text('지금은 괜찮아요'),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ],
                ),
        ),
=======
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
                  // 상단 컨텐츠 영역
                  // Positioned: Stack 내에서 위젯의 위치와 크기를 지정
                  // - top: 상단에서 얼마나 떨어져 있는지 (0 = 화면 최상단)
                  // - bottom: 하단에서 얼마나 떨어져 있는지 (값이 클수록 영역이 작아짐)
                  //   현재: screenHeight * 0.344 = 화면 높이의 34.4%만큼 하단에서 떨어짐
                  //   즉, 상단 65.6% 영역을 사용 (하단 흰색 사각형이 34.4% 차지)
                  // 
                  // 위치 조정 팁:
                  // - 로고를 위로 올리려면: top 값을 음수로 (예: top: -30)
                  // - 로고를 아래로 내리려면: top 값을 양수로 (예: top: 50)
                  // - 영역을 더 크게 하려면: bottom 값을 줄이기 (예: 0.3)
                  // - 영역을 더 작게 하려면: bottom 값을 늘리기 (예: 0.4)
                  Positioned(
                    top: 20,  // 상단 여백: 0 = 화면 최상단부터 시작
                    left: 0,
                    right: 0,
                    bottom: screenHeight * 0.3,  // 하단 여백: 화면 높이의 34.4%
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                      child: Column(
                        // mainAxisAlignment: Column 내부의 자식들을 수직으로 정렬
                        // - center: 수직 중앙 정렬 (현재 설정)
                        // - start: 상단 정렬 (로고를 위로 올리고 싶을 때)
                        // - end: 하단 정렬 (로고를 아래로 내리고 싶을 때)
                        // - spaceBetween: 첫 요소는 상단, 마지막 요소는 하단에 배치
                        // - spaceAround: 각 요소 주변에 균등한 공간
                        // - spaceEvenly: 모든 요소 사이에 균등한 공간
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 로고 영역
                          // Figma: y=212
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
                          // ===== 서브텍스트 위치 조정 =====
                          // 1. 로고와 서브텍스트 사이의 간격
                          //    현재: 화면 높이의 49/844 비율 (약 5.8%)
                          //    조정: 값을 늘리면 서브텍스트가 아래로, 줄이면 위로 이동 (간격이 가까워짐)
                          //    예: 35-40으로 줄이면 간격이 더 가까워짐
                          // Figma: 서브텍스트 y=261, 로고 y=212
                          // 간격: 261-212 = 49px (전체 844 기준)
                          SizedBox(height: 5 * (screenHeight / 844)),  // 49에서 35로 줄여서 간격을 가깝게 조정
                          
                          // 2. 서브텍스트
                          Text(
                            '내 주변 모든 혜택을 우주라이크와 함께',
                            // 3. 텍스트의 수평 정렬
                            //    - center: 중앙 정렬 (현재)
                            //    - left: 왼쪽 정렬
                            //    - right: 오른쪽 정렬
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFDADCFF),
                              fontSize: 18,  // 4. 텍스트 크기
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                              // 5. 텍스트의 줄 간격 (높이)
                              //    현재: 3.33 (폰트 크기의 3.33배)
                              //    조정: 값을 줄이면 텍스트가 위로, 늘리면 아래로 이동
                              //    주의: 이 값은 줄 간격이므로 텍스트가 여러 줄일 때만 영향
                              height: 3.33,
                              letterSpacing: -0.50,  // 6. 글자 사이 간격
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 하단 흰색 사각형 영역 (Rectangle 56)
                  // Figma: y=554, height=290 (전체 844 중)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: screenHeight * 0.344, // 290/844 = 34.4%
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
                            // ===== 카카오 로그인 버튼 위치 조정 =====
                            // 1. 버튼 전체의 수직 위치 (하단 흰색 영역 내에서)
                            //    현재: 하단 사각형 상단에서 90px 떨어진 위치
                            //    조정: 값을 늘리면 버튼이 아래로, 줄이면 위로 이동
                            SizedBox(height: 90 * (screenHeight / 844)),
                            
                            // 2. 버튼의 높이
                            //    현재: 47.2px
                            //    조정: 값을 늘리면 버튼이 커지고 텍스트가 더 위아래로 이동 가능
                            SizedBox(
                              width: double.infinity,
                              height: 47.2,  // 버튼 높이 조정
                              child: ElevatedButton(
                                onPressed: _loginWithKakao,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFffe812),
                                  foregroundColor: const Color(0xFF000000),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  // 버튼 내부 패딩 조정: 위쪽은 작게, 아래쪽은 크게 설정하여 텍스트를 위로 올림
                                  // 위쪽 패딩을 줄이면 텍스트가 위로, 아래쪽 패딩을 늘리면 텍스트가 위로 올라감
                                  padding: EdgeInsets.only(
                                    top: 3,      // 위쪽 패딩 (값을 줄이면 텍스트가 더 위로)
                                    bottom: 12,  // 아래쪽 패딩 (값을 늘리면 텍스트가 위로 올라감)
                                    left: 0,
                                    right: 0,
                                  ),
                                ),
                                child: Row(
                                  // 4. Row 내부 정렬 (아이콘과 텍스트의 수평 정렬)
                                  //    - center: 중앙 정렬 (현재)
                                  //    - start: 왼쪽 정렬
                                  //    - end: 오른쪽 정렬
                                  //    - spaceBetween: 양 끝 정렬
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  // 5. Row 내부의 수직 정렬 (아이콘과 텍스트의 수직 정렬)
                                  //    crossAxisAlignment: CrossAxisAlignment.center,  // 기본값
                                  //    - center: 중앙 정렬
                                  //    - start: 상단 정렬
                                  //    - end: 하단 정렬
                                  children: [
                                    // 카카오톡 아이콘 SVG
                                    Container(
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
                                    // 6. 아이콘과 텍스트 사이 간격
                                    //    현재: 8px
                                    //    조정: 값을 늘리면 간격이 넓어짐
                                    const SizedBox(width: 8),
                                    // 텍스트만 위로 올리기: Transform.translate로 y축 이동
                                    // dy 값을 음수로 하면 위로, 양수로 하면 아래로 이동
                                    // 아이콘은 그대로 두고 텍스트만 이동합니다
                                    Transform.translate(
                                      offset: Offset(0, -6),  // y축으로 -2px 위로 이동 (값을 조정하여 위치 변경)
                                      child: Text(
                                        '카카오로  간편로그인 ',
                                        // 7. 텍스트의 수평 정렬 (텍스트 자체의 정렬)
                                        //    - center: 중앙 정렬 (현재)
                                        //    - left: 왼쪽 정렬
                                        //    - right: 오른쪽 정렬
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 19,  // 8. 텍스트 크기
                                          fontFamily: 'Pretendard',
                                          fontWeight: FontWeight.w700,
                                          // 9. 텍스트의 줄 간격 (높이)
                                          //    현재: 3.16 (폰트 크기의 3.16배)
                                          //    조정: 값을 줄이면 텍스트가 위로, 늘리면 아래로 이동
                                          //    주의: 이 값은 줄 간격이므로 텍스트가 여러 줄일 때만 영향
                                          height: 3.16,
                                          letterSpacing: -0.50,  // 10. 글자 사이 간격
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Figma: "지금은 괜찮아요" y=721, 카카오 버튼 하단 y=704 (644+60)
                            // 간격: (721-704)/844 = 2.0% 또는 고정값 17px
                            SizedBox(height: 17 * (screenHeight / 844)),
                            // 지금은 괜찮아요 버튼
                            // Figma: y=721, height=41
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
>>>>>>> b9dffe8ab503eebcc1a2a71c4e688b4fcb434fe5
      ),
    );
  }
}
