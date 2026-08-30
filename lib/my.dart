import 'dart:convert';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:new1/config/analytics_events.dart';
import 'package:new1/utils/analytics_logger.dart';
import 'package:new1/profile_setup_screen.dart';
import 'package:new1/favorite_restaurants_screen.dart';

import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/coupon_service.dart';
import 'services/kakao_share_service.dart';
import 'services/user_service.dart';
import 'widgets/referral_code_sheet.dart';

const TextStyle _kSectionTitleStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: Color(0xFF111827),
);

const TextStyle _kItemTitleStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: Color(0x99111827),
);

const TextStyle _kPlaceholderItemStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w500,
  color: Color(0xFF9CA3AF),
);

const double _kItemIndent = 16;

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  bool isLoading = true;
  bool isKakaoLoggedIn = false;
  bool _isInviteLoading = false;
  bool _isShareInProgress = false;
  bool _isKakaoLogoutInProgress = false;
  bool _isAccountDeleteInProgress = false;
  String? inviteCode;
  String? _inviteError;
  String? _kakaoId;
  String? _appleId;

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  Future<void> _initializeState() async {
    await _refreshLoginState();
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _refreshLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    final kakaoLoggedIn = prefs.getBool('kakao_logged_in') ?? false;
    final appleLoggedIn = prefs.getBool('apple_logged_in') ?? false;
    final loggedIn = kakaoLoggedIn || appleLoggedIn;
    final kakaoId = prefs.getString('user_kakao_id');
    final appleId = prefs.getString('user_apple_id');
    if (!mounted) return;
    setState(() {
      isKakaoLoggedIn = loggedIn;
      _kakaoId = kakaoId;
      _appleId = appleId;
      if (!loggedIn) {
        inviteCode = null;
        _inviteError = null;
        _kakaoId = null;
        _appleId = null;
      }
    });
    if (loggedIn) {
      await _loadInviteCode();
    }
  }

  /// 로그아웃 후 재로그인 시 반드시 로그인 화면을 거쳐 카카오/애플 선택 가능하도록 이동
  Future<void> _navigateToLoginScreen() async {
    await Navigator.of(context).pushNamed('/login');
    if (!mounted) return;
    await _refreshLoginState();
  }

  Future<void> _handleKakaoLogout() async {
    if (_isKakaoLogoutInProgress) return;
    if (!mounted) return;
    setState(() {
      _isKakaoLogoutInProgress = true;
    });

    String? errorMessage;
    final prefs = await SharedPreferences.getInstance();
    final wasKakaoLoggedIn = prefs.getBool('kakao_logged_in') ?? false;
    // 카카오 로그인 사용자만 카카오 SDK 로그아웃 호출 (애플 로그인 시 불필요)
    if (wasKakaoLoggedIn) {
      try {
        await UserApi.instance.logout();
      } catch (_) {
        errorMessage ??= '카카오 로그아웃에 실패했어요. 다시 시도해주세요.';
      }
    }

    try {
      await AuthService.logout();
    } catch (_) {
      errorMessage ??= '로그아웃 처리 중 문제가 발생했어요. 다시 시도해주세요.';
    }

    await _refreshLoginState();

    if (!mounted) return;
    setState(() {
      _isKakaoLogoutInProgress = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? '로그아웃이 완료되었어요.'),
      ),
    );
  }

  Future<bool> _showAccountDeleteFirstConfirmDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              width: 358,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: ShapeDecoration(
                color: const Color(0xFFF2F2F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '계정 삭제',
                    style: TextStyle(
                      color: Color(0xFF39393E),
                      fontSize: 19,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w800,
                      height: 1.21,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 330,
                    child: Text(
                      '계정을 삭제하면 쿠폰/스탬프 내역 등 계정 데이터가 함께 정리되며 되돌릴 수 없어요.\n\n계속 진행할까요?',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 15,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w500,
                        height: 1.20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            foregroundColor: const Color(0xFF39393E),
                            side: const BorderSide(color: Color(0xFFBABAC0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1C203C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: -0.32,
                            ),
                          ),
                          child: const Text('계속'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<bool> _showAccountDeleteSecondConfirmDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              width: 358,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: ShapeDecoration(
                color: const Color(0xFFF2F2F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '정말로 삭제할까요?',
                    style: TextStyle(
                      color: Color(0xFF39393E),
                      fontSize: 19,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w800,
                      height: 1.21,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 330,
                    child: Text(
                      '이 작업은 되돌릴 수 없어요.\n계정을 삭제하시겠어요?',
                      style: TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 15,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w500,
                        height: 1.20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            foregroundColor: const Color(0xFF39393E),
                            side: const BorderSide(color: Color(0xFFBABAC0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB91C1C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: -0.32,
                            ),
                          ),
                          child: const Text('삭제'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleAccountDelete() async {
    if (_isAccountDeleteInProgress) return;
    if (!isKakaoLoggedIn) {
      _promptLoginRequired();
      return;
    }

    final first = await _showAccountDeleteFirstConfirmDialog();
    if (!first) return;
    final second = await _showAccountDeleteSecondConfirmDialog();
    if (!second) return;

    if (!mounted) return;
    setState(() {
      _isAccountDeleteInProgress = true;
    });

    try {
      await UserService.deleteMyAccount();
      await AuthService.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정이 삭제되었어요.')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } on ApiAuthException catch (e) {
      try {
        await AuthService.logout();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } on ApiHttpException catch (e) {
      String message;
      if (e.statusCode == 401) {
        message = '세션이 만료되었어요. 다시 로그인해 주세요.';
        try {
          await AuthService.logout();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        return;
      }

      final detail = _extractDetailMessage(e.body);
      if (e.statusCode >= 500) {
        message = '일시적인 오류로 탈퇴에 실패했어요. 잠시 후 다시 시도해주세요.';
      } else {
        message = detail ?? '계정 삭제에 실패했어요. 잠시 후 다시 시도해주세요.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on ApiNetworkException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네트워크 오류로 탈퇴에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정 삭제에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isAccountDeleteInProgress = false;
      });
      await _refreshLoginState();
    }
  }

  Future<String?> _loadInviteCode() async {
    if (!mounted) return inviteCode;
    setState(() {
      _isInviteLoading = true;
      _inviteError = null;
    });
    try {
      final result = await CouponService.fetchInviteCode();
      final code = readInviteCode(result);
      if (!mounted) {
        inviteCode = code;
        _isInviteLoading = false;
        return code;
      }
      setState(() {
        inviteCode = code;
        _isInviteLoading = false;
      });
      return code;
    } on ApiAuthException catch (e) {
      if (!mounted) {
        _isInviteLoading = false;
        _inviteError = e.message;
        return null;
      }
      setState(() {
        _isInviteLoading = false;
        _inviteError = e.message;
      });
      return null;
    } on ApiHttpException catch (e) {
      final message = _extractDetailMessage(e.body) ?? '초대 코드를 불러오지 못했어요.';
      if (!mounted) {
        _isInviteLoading = false;
        _inviteError = message;
        return null;
      }
      setState(() {
        _isInviteLoading = false;
        _inviteError = message;
      });
      return null;
    } on ApiNetworkException catch (e) {
      final message = '네트워크 오류: $e';
      if (!mounted) {
        _isInviteLoading = false;
        _inviteError = message;
        return null;
      }
      setState(() {
        _isInviteLoading = false;
        _inviteError = message;
      });
      return null;
    } catch (e) {
      final message = e.toString();
      if (!mounted) {
        _isInviteLoading = false;
        _inviteError = message;
        return null;
      }
      setState(() {
        _isInviteLoading = false;
        _inviteError = message;
      });
      return null;
    }
  }

  String? _extractDetailMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['detail'] != null) return decoded['detail'].toString();
        if (decoded['message'] != null) return decoded['message'].toString();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _copyInviteCode() async {
    final code = inviteCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대 코드를 복사했어요.')),
    );
  }

  Future<void> _shareInvite() async {
    if (!isKakaoLoggedIn) {
      _promptLoginRequired();
      return;
    }
    if (_isShareInProgress) return;
    if (!mounted) return;
    setState(() {
      _isShareInProgress = true;
    });
    try {
      final code =
          inviteCode != null && inviteCode!.isNotEmpty ? inviteCode! : null;
      final resolvedCode = code ?? await _loadInviteCode();
      if (!mounted) return;
      if (resolvedCode == null || resolvedCode.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초대 코드를 불러오지 못했어요. 다시 시도해주세요.')),
        );
        return;
      }
      await KakaoShareService.shareInvite(
        context,
        referralCode: resolvedCode,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('초대장을 공유하지 못했어요. $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isShareInProgress = false;
        });
      } else {
        _isShareInProgress = false;
      }
    }
  }

  Future<void> _showReferralCodeSheet() async {
    await presentReferralCodeSheet(context);
  }

  void _promptLoginRequired() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('카카오 로그인이 필요합니다.')),
    );
  }

  void _openFavoriteRestaurants() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FavoriteRestaurantsScreen(),
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    // 알림 옵트인율은 구매 유도 알림 효과의 상한이라 P0로 남긴다.
    // 다만 이 화면은 OS 설정으로 위임만 하므로 앱이 on/off 결과를 알 수 없다.
    // enabled를 채우려면 복귀 시점에 FirebaseMessaging의 권한 상태를 다시
    // 읽어 보강해야 한다 (후속 작업).
    AnalyticsLogger.logEvent(
      AnalyticsEvents.notificationSettingToggle,
      parameters: {
        AnalyticsEvents.paramChannel: 'event_promo',
        AnalyticsEvents.paramAction: 'open_os_settings',
      },
    );
    try {
      await AppSettings.openAppSettings(
        type: AppSettingsType.notification,
        asAnotherTask: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알림 설정을 열 수 없어요. $e')),
      );
    }
  }

  Future<void> _openKakaoTalkInquiry() async {
    try {
      final response = await ApiClient.get('/api/url/', authenticated: false);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url']?.toString() ?? '';

      if (url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카카오톡 1대1 문의 URL이 설정되지 않았어요.')),
        );
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카카오톡 1대1 문의를 열 수 없어요.')),
        );
      }
    } on ApiHttpException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오톡 1대1 문의 URL을 불러오지 못했어요.')),
      );
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('네트워크 오류: $e')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열 수 없어요: $e')),
      );
    }
  }

  static const _ownerDashboardUrl = 'https://wouldulike-dashboard.vercel.app/';

  Future<void> _openOwnerDashboard() async {
    final uri = Uri.parse(_ownerDashboardUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사장님 대시보드를 열 수 없어요.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열 수 없어요: $e')),
      );
    }
  }

  Future<void> _openProfileSetup() async {
    final profile = await UserService.fetchCurrentUserProfile();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileSetupScreen(
          initialProfile: profile,
          isRequiredFlow: false,
        ),
      ),
    );
  }

  Widget _buildAccountTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMenuRow(
          leading: Text(isKakaoLoggedIn ? '로그아웃' : '로그인', style: _kItemTitleStyle),
          trailing: _isKakaoLogoutInProgress
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _buildChevron(),
          onTap: _isKakaoLogoutInProgress
              ? null
              : (isKakaoLoggedIn ? _handleKakaoLogout : _navigateToLoginScreen),
          indent: _kItemIndent,
        ),
        _buildMenuRow(
          leading: const Text('프로필 설정/재설정', style: _kItemTitleStyle),
          trailing: _buildChevron(),
          onTap: isKakaoLoggedIn ? _openProfileSetup : _navigateToLoginScreen,
          indent: _kItemIndent,
        ),
        // 우주라이크 ID 표시 (로그인 상태일 때만, 프로필 설정과 시작점 맞춤)
        if (isKakaoLoggedIn &&
            ((_kakaoId != null && _kakaoId!.isNotEmpty) ||
                (_appleId != null && _appleId!.isNotEmpty)))
          Padding(
            padding: const EdgeInsets.only(
              left: _kItemIndent,
              top: 6,
              bottom: 6,
            ),
            child: Text(
              '우주라이크 ID: ${_kakaoId ?? _appleId ?? ''}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        if (isKakaoLoggedIn)
          _buildMenuRow(
            leading: Text(
              '계정 삭제',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            trailing: _isAccountDeleteInProgress
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _buildChevron(),
            onTap: _isAccountDeleteInProgress ? null : _handleAccountDelete,
            indent: _kItemIndent,
          ),
      ],
    );
  }

  Widget _buildInviteCodeInline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMenuRow(
          leading: Text(
            '내 초대코드',
            style: isKakaoLoggedIn ? _kItemTitleStyle : _kPlaceholderItemStyle,
          ),
          trailing: const SizedBox.shrink(),
          onTap: null,
          indent: _kItemIndent,
        ),
        Padding(
          padding: const EdgeInsets.only(left: _kItemIndent, top: 6),
          child: _buildInviteCodeBody(),
        ),
      ],
    );
  }

  Widget _buildReferralAcceptTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMenuRow(
          leading: const Text('코드 입력하기', style: _kItemTitleStyle),
          trailing: _buildChevron(),
          onTap: () {
            AnalyticsLogger.logEvent(AnalyticsEvents.referralCodeInputClick);
            if (!isKakaoLoggedIn) {
              _promptLoginRequired();
              return;
            }
            _showReferralCodeSheet();
          },
          indent: _kItemIndent,
        ),
      ],
    );
  }

  Widget _buildInviteCodeBody() {
    if (!isKakaoLoggedIn) {
      return const Text(
        '카카오 로그인을 하면 초대코드를 볼 수 있어요.',
        style: _kPlaceholderItemStyle,
      );
    }

    if (_isInviteLoading) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            '초대코드를 불러오는 중이에요.',
            style: _kPlaceholderItemStyle,
          ),
        ],
      );
    }

    if (_inviteError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _inviteError!,
            style: const TextStyle(
              color: Color(0xFFB91C1C),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadInviteCode,
            child: const Text('다시 불러오기'),
          ),
        ],
      );
    }

    final code = inviteCode;
    if (code == null || code.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '초대 코드를 불러오지 못했어요.',
            style: _kPlaceholderItemStyle,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadInviteCode,
            child: const Text('다시 시도'),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF312E81)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF312E81),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: '복사하기',
            onPressed: _copyInviteCode,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuRow({
    required Widget leading,
    Widget? trailing,
    VoidCallback? onTap,
    bool enabled = true,
    double indent = 0,
  }) {
    final rowContent = Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: leading),
          trailing ??
              Icon(
                Icons.chevron_right,
                color:
                    enabled ? const Color(0xFF9CA3AF) : const Color(0xFFD1D5DB),
              ),
        ],
      ),
    );

    final child =
        enabled ? rowContent : Opacity(opacity: 0.6, child: rowContent);
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: child,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: _kSectionTitleStyle),
    );
  }

  Widget _buildChevron() {
    return const Icon(
      Icons.chevron_right,
      color: Color(0xFF9CA3AF),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF312E81),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          24,
          20,
          24,
          140, // 제휴/혜택, 홈과 동일하게 하단 바 높이만큼 여백 부여
        ),
        children: [
          _buildSectionHeader('계정 정보'),
          _buildAccountTile(),
          const SizedBox(height: 24),
          _buildSectionHeader('활동 내역'),
          _buildMenuRow(
            leading: const Text('찜한 식당 모아보기', style: _kItemTitleStyle),
            trailing: _buildChevron(),
            onTap: _openFavoriteRestaurants,
            indent: _kItemIndent,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('환경 설정'),
          _buildMenuRow(
            leading: const Text('이벤트/프로모션 알림', style: _kItemTitleStyle),
            onTap: _openNotificationSettings,
            indent: _kItemIndent,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('친구 초대'),
          _buildMenuRow(
            leading: const Text('카카오톡 친구 초대하기', style: _kItemTitleStyle),
            trailing: _isShareInProgress
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _buildChevron(),
            onTap: () {
              AnalyticsLogger.logEvent(AnalyticsEvents.kakaoInviteClick);
              if (!isKakaoLoggedIn) {
                _promptLoginRequired();
                return;
              }
              _shareInvite();
            },
            indent: _kItemIndent,
          ),
          const SizedBox(height: 8),
          _buildReferralAcceptTile(),
          _buildInviteCodeInline(),
          const SizedBox(height: 24),
          _buildSectionHeader('고객 지원'),
          _buildMenuRow(
            leading: const Text('카카오톡 1대1 문의', style: _kItemTitleStyle),
            trailing: _buildChevron(),
            onTap: _openKakaoTalkInquiry,
            indent: _kItemIndent,
          ),
          _buildMenuRow(
            leading: const Text('식당 사장님 대시보드', style: _kItemTitleStyle),
            trailing: _buildChevron(),
            onTap: _openOwnerDashboard,
            indent: _kItemIndent,
          ),
          _buildMenuRow(
            leading: const Text('앱 버전: v2.5.0', style: _kItemTitleStyle),
            indent: _kItemIndent,
          ),
        ],
      ),
    );
  }
}
