import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/analytics_events.dart';
import 'onboarding/onboarding_prefs.dart';
import 'onboarding/onboarding_style.dart';
import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'services/coupon_service.dart';
import 'utils/analytics_logger.dart';

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
    final web =
        Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
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

  /// 로그인 게이트 이벤트. 첫 쿠폰 구간에서 넘어온 경우 조인 키를 함께 실어
  /// 온보딩 → 로그인 → 쿠폰 수령의 단계별 이탈을 이어서 볼 수 있게 한다.
  Future<Map<String, Object?>> _authParams(String method) async {
    final route = ModalRoute.of(context);
    final args = route?.settings.arguments;
    String entryPoint = 'app_start';
    if (args is Map) {
      final value = Map<String, dynamic>.from(args)['redirect'];
      if (value is String && value.isNotEmpty) entryPoint = value;
    }
    return {
      AnalyticsEvents.paramMethod: method,
      AnalyticsEvents.paramEntryPoint: entryPoint,
      AnalyticsEvents.paramFirstpickSessionId:
          await OnboardingPrefs.firstpickSessionId(),
    };
  }

  Future<void> _loginWithKakao() async {
    setState(() => _isLoggingIn = true);
    final authParams = await _authParams('kakao');
    AnalyticsLogger.logEvent(AnalyticsEvents.loginStart, parameters: authParams);
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
            _logLoginCompleted(authParams, 'cancelled');
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
          debugPrint(
              '[Kakao] loginWithKakaoAccount success (talk not installed)');
        } on PlatformException catch (e) {
          if (e.code == 'CANCELED') {
            if (!mounted) return;
            setState(() => _isLoggingIn = false);
            _logLoginCompleted(authParams, 'cancelled');
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
      await prefs.setBool('apple_logged_in', false);
      await prefs.setString('jwt_access_token', data['token']['access']);
      await prefs.setString('jwt_refresh_token', data['token']['refresh']);
      await prefs.setInt('user_id', data['user']['id']);
      await prefs.setString('user_nickname', data['user']['nickname'] ?? '');
      await prefs.setString(
        'user_profile_image_url',
        data['user']['profile_image_url'] ?? '',
      );
      // 카카오 ID 저장 (BigInteger이므로 String으로 저장)
      if (data['user']['kakao_id'] != null) {
        await prefs.setString(
            'user_kakao_id', data['user']['kakao_id'].toString());
      }

      // 로그인 후 토큰 갱신 타이머 설정
      try {
        await ApiClient.scheduleTokenRefresh();
      } catch (e) {
        // 타이머 설정 실패는 조용히 처리
        debugPrint('[LoginScreen] Failed to schedule token refresh: $e');
      }

      _logLoginCompleted(
        authParams,
        'success',
        isNewUser: data['user']?['is_new_user'],
      );

      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      // 로그인 진입 경로에 따라 후처리를 다르게 수행한다.
      final route = ModalRoute.of(context);
      final args = route?.settings.arguments;
      String? redirect;
      if (args is Map) {
        final map = Map<String, dynamic>.from(args);
        final value = map['redirect'];
        if (value is String && value.isNotEmpty) {
          redirect = value;
        }
      }

      if (redirect == 'coupon_list') {
        // 쿠폰 리스트에서 진입한 경우:
        // 로그인 직후 쿠폰 목록을 미리 불러와서 함께 돌려준다.
        List<UserCoupon>? coupons;
        try {
          coupons = await CouponService.fetchMyCoupons();
        } catch (_) {
          // 쿠폰 동기화 실패는 로그인 성공 자체를 막지 않는다.
        }
        Navigator.of(context).pop(coupons ?? true);
      } else {
        // 일반 진입(앱 시작 등) 또는 재로그인: 스택을 비우고 메인 화면으로 이동
        Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
      }
    } catch (e) {
      _logLoginCompleted(authParams, 'error');
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      final msg = e is ReloginRequiredException
          ? '세션이 만료되어 다시 로그인이 필요해요.'
          : e.toString().contains('Auth server')
              ? '서버 로그인 오류가 발생했어요. 잠시 후 다시 시도해 주세요.'
              : '카카오 로그인 실패: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      debugPrint('[Kakao] login error: $e');
    }
  }

  /// 인증 종료를 성공·취소·오류 한 이벤트로 남긴다.
  /// 실패를 따로 떼지 않아야 GA4 퍼널에서 취소율을 그대로 읽을 수 있다.
  void _logLoginCompleted(
    Map<String, Object?> authParams,
    String result, {
    Object? isNewUser,
  }) {
    AnalyticsLogger.logEvent(
      AnalyticsEvents.loginCompleted,
      parameters: {
        ...authParams,
        AnalyticsEvents.paramResult: result,
        if (isNewUser is bool) AnalyticsEvents.paramIsNewUser: isNewUser,
      },
    );
  }

  Future<void> _loginWithApple() async {
    setState(() => _isLoggingIn = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      final guestUuid = prefs.getString('user_uuid');
      await AuthService.loginWithApple(
        credential.identityToken ?? '',
        authorizationCode: credential.authorizationCode,
        userIdentifier: credential.userIdentifier,
        email: credential.email,
        guestUuid: guestUuid,
      );

      try {
        await ApiClient.scheduleTokenRefresh();
      } catch (e) {
        debugPrint('[LoginScreen] Failed to schedule token refresh: $e');
      }

      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      final route = ModalRoute.of(context);
      final args = route?.settings.arguments;
      String? redirect;
      if (args is Map) {
        final map = Map<String, dynamic>.from(args);
        final value = map['redirect'];
        if (value is String && value.isNotEmpty) redirect = value;
      }
      if (redirect == 'coupon_list') {
        List<UserCoupon>? coupons;
        try {
          coupons = await CouponService.fetchMyCoupons();
        } catch (_) {}
        Navigator.of(context).pop(coupons ?? true);
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      if (e.code == AuthorizationErrorCode.canceled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple 로그인 실패: ${e.message}')),
      );
    } on ReloginRequiredException {
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세션이 만료되어 다시 로그인이 필요해요.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoggingIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apple 로그인 실패: $e')),
      );
      debugPrint('[Apple] login error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      // 하단 세이프에어리어까지 흰색으로 채워, 시트 아래 보라색이 비치지 않게 한다.
      backgroundColor: Colors.white,
      // 리브랜딩: 구 네이비(#1C203C) 대신 테마색 단색.
      body: Container(
        color: OnboardingStyle.primary,
        // bottom: false — 시트가 화면 맨 아래까지 닿도록 하단 인셋을 시트 내부에서 처리.
        child: SafeArea(
        bottom: false,
        child: _isLoggingIn
            ? const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
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
                    top: 20, // 상단 여백: 0 = 화면 최상단부터 시작
                    left: 0,
                    right: 0,
                    bottom: screenHeight * 0.3, // 하단 여백: 화면 높이의 34.4%
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Would',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.87),
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
                                    color: Colors.white.withOpacity(0.87),
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
                                    color: Colors.white.withOpacity(0.87),
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
                          SizedBox(
                              height: 5 *
                                  (screenHeight /
                                      844)), // 49에서 35로 줄여서 간격을 가깝게 조정

                          // 2. 서브텍스트
                          Text(
                            '내 주변 모든 혜택을 우주라이크와 함께',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFC7D2FE),
                              fontSize: 18, // 4. 텍스트 크기
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w600,
                              height: 3.33,
                              letterSpacing: -0.50, // 6. 글자 사이 간격
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
                    // 하단 인셋만큼 시트를 키워, 홈 인디케이터 영역까지 흰색으로 채운다.
                    height: screenHeight * 0.344 + bottomInset,
                    child: Container(
                      width: double.infinity,
                      // 리브랜딩 확정안: 흰색 바텀시트 + 상단 radius 28 (기존 비대칭 100 정리)
                      decoration: const ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(28),
                            topRight: Radius.circular(28),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: screenWidth * 0.08,
                          right: screenWidth * 0.08,
                          bottom: bottomInset,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // 시트 상단 그래버(회색 선)
                            Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(top: 10),
                              decoration: BoxDecoration(
                                color: OnboardingStyle.line,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            SizedBox(height: 62 * (screenHeight / 844)),

                            // 2. 버튼의 높이
                            //    현재: 50px로 조정하여 텍스트가 잘리지 않도록 함
                            SizedBox(
                              width: double.infinity,
                              height: 54, // 온보딩 버튼 규격과 통일
                              child: ElevatedButton(
                                onPressed: _loginWithKakao,
                                // 온보딩과 동일 규격(#FEE500 · radius 14 · 높이 54)
                                style: OnboardingStyle.kakaoButton(),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  // 5. Row 내부의 수직 정렬 (아이콘과 텍스트의 수직 정렬)
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                    // 텍스트가 잘리지 않도록 height를 1.0으로 설정하고 overflow 방지
                                    Flexible(
                                      child: Text(
                                        '카카오로 간편로그인',
                                        // 7. 텍스트의 수평 정렬 (텍스트 자체의 정렬)
                                        //    - center: 중앙 정렬 (현재)
                                        //    - left: 왼쪽 정렬
                                        //    - right: 오른쪽 정렬
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.visible,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16, // 온보딩 버튼 타이포 규격
                                          fontFamily: 'Pretendard',
                                          fontWeight: FontWeight.w700,
                                          // 9. 텍스트의 줄 간격 (높이)을 1.0으로 설정하여 실제 텍스트 높이만 사용
                                          height: 1.0,
                                          letterSpacing: -0.50, // 10. 글자 사이 간격
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.iOS) ...[
                              SizedBox(height: 12 * (screenHeight / 844)),
                              SignInWithAppleButton(
                                onPressed: _loginWithApple,
                                height: 54,
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ],
                            SizedBox(height: 17 * (screenHeight / 844)),
                            GestureDetector(
                              // 텍스트 line-height 때문에 글자가 박스 밖으로 밀려
                              // 탭 영역과 어긋나던 문제 수정. 터치 영역 44pt 이상 확보.
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                Navigator.pushReplacementNamed(
                                    context, '/main');
                              },
                              child: Container(
                                width: 168,
                                height: 48,
                                alignment: Alignment.center,
                                child: const Text(
                                  '지금은 괜찮아요',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: OnboardingStyle.muted,
                                    fontSize: 16,
                                    fontFamily: 'Pretendard',
                                    fontWeight: FontWeight.w400,
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
      ),
    );
  }
}
