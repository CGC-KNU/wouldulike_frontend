import 'dart:convert';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coupon_list_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/coupon_service.dart';
import 'services/kakao_share_service.dart';

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
  bool _isKakaoLoginInProgress = false;
  bool _isKakaoLogoutInProgress = false;
  String? inviteCode;
  String? _inviteError;

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
    final loggedIn = prefs.getBool('kakao_logged_in') ?? false;
    if (!mounted) return;
    setState(() {
      isKakaoLoggedIn = loggedIn;
      if (!loggedIn) {
        inviteCode = null;
        _inviteError = null;
      }
    });
    if (loggedIn) {
      await _loadInviteCode();
    }
  }

  Future<void> _handleKakaoLogin() async {
    if (_isKakaoLoginInProgress) return;
    if (!mounted) return;
    setState(() {
      _isKakaoLoginInProgress = true;
    });

    try {
      final installed = await isKakaoTalkInstalled();
      final token = installed
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
      final prefs = await SharedPreferences.getInstance();
      final guestUuid = prefs.getString('user_uuid');
      await AuthService.loginWithKakao(token.accessToken, guestUuid: guestUuid);
      await prefs.setBool('signup_coupon_checked', false);
      await _refreshLoginState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오 로그인이 완료되었어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카카오 로그인에 실패했어요. $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isKakaoLoginInProgress = false;
        });
      } else {
        _isKakaoLoginInProgress = false;
      }
    }
  }

  Future<void> _handleKakaoLogout() async {
    if (_isKakaoLogoutInProgress) return;
    if (!mounted) return;
    setState(() {
      _isKakaoLogoutInProgress = true;
    });

    String? errorMessage;
    try {
      await UserApi.instance.logout();
    } catch (_) {
      errorMessage ??= '카카오 로그아웃에 실패했어요. 다시 시도해주세요.';
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
        content: Text(errorMessage ?? '카카오 로그아웃이 완료되었어요.'),
      ),
    );
  }

  Future<String?> _loadInviteCode() async {
    if (!mounted) return inviteCode;
    setState(() {
      _isInviteLoading = true;
      _inviteError = null;
    });
    try {
      final result = await CouponService.fetchInviteCode();
      final code = result['code']?.toString() ??
          result['invite_code']?.toString() ??
          result['coupon_code']?.toString();
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
      final message =
          _extractDetailMessage(e.body) ?? '추천 코드를 불러오지 못했어요.';
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
      const SnackBar(content: Text('추천 코드를 복사했어요.')),
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
          const SnackBar(content: Text('추천 코드를 불러오지 못했어요. 다시 시도해주세요.')),
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

  void _promptLoginRequired() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('카카오 로그인이 필요합니다.')),
    );
  }

  void _openCouponList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CouponListScreen()),
    );
  }

  Future<void> _openNotificationSettings() async {
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

  Widget _buildAccountTile() {
    final isBusy = _isKakaoLoginInProgress || _isKakaoLogoutInProgress;
    final label = isKakaoLoggedIn ? '로그아웃' : '로그인';
    return _buildMenuRow(
      leading: Row(
        children: [
          _buildKakaoBadge(),
          const SizedBox(width: 12),
          Text(label, style: _kItemTitleStyle),
        ],
      ),
      trailing: isBusy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _buildChevron(),
      onTap: isBusy
          ? null
          : (isKakaoLoggedIn ? _handleKakaoLogout : _handleKakaoLogin),
      indent: _kItemIndent,
    );
  }

  Widget _buildInviteCodeInline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMenuRow(
          leading: Text(
            '내 추천코드',
            style: isKakaoLoggedIn
                ? _kItemTitleStyle
                : _kPlaceholderItemStyle,
          ),
          trailing: const SizedBox.shrink(),
          onTap: null,
          indent: _kItemIndent,
        ),
        Padding(
          padding: const EdgeInsets.only(left: _kItemIndent, top: 8),
          child: _buildInviteCodeBody(),
        ),
      ],
    );
  }

  Widget _buildInviteCodeBody() {
    if (!isKakaoLoggedIn) {
      return const Text(
        '카카오 로그인을 하면 추천코드를 볼 수 있어요.',
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
            '추천코드를 불러오는 중이에요.',
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
            '추천 코드를 불러오지 못했어요.',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 14),
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

    final child = enabled ? rowContent : Opacity(opacity: 0.6, child: rowContent);
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: _kSectionTitleStyle),
    );
  }

  Widget _buildChevron() {
    return const Icon(
      Icons.chevron_right,
      color: Color(0xFF9CA3AF),
    );
  }

  Widget _buildKakaoBadge() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/images/KakaoTalklogo.png',
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE812),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Text(
              '톡',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3C1E1E),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
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
        elevation: 0,
        centerTitle: true,
        foregroundColor: const Color(0xFF111827),
        title: const Text(
          '마이페이지',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFE5E7EB),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        children: [
          _buildSectionHeader('계정 정보'),
          _buildAccountTile(),
          const SizedBox(height: 40),
          _buildSectionHeader('활동 내역'),
          _buildMenuRow(
            leading: const Text('쿠폰 사용 내역', style: _kItemTitleStyle),
            onTap: _openCouponList,
            indent: _kItemIndent,
          ),
          const SizedBox(height: 40),
          _buildSectionHeader('환경 설정'),
          _buildMenuRow(
            leading:
                const Text('이벤트/프로모션 알림', style: _kItemTitleStyle),
            onTap: _openNotificationSettings,
            indent: _kItemIndent,
          ),
          const SizedBox(height: 40),
          _buildSectionHeader('친구 초대'),
          _buildMenuRow(
            leading:
                const Text('카카오톡 친구 초대하기', style: _kItemTitleStyle),
            trailing: _isShareInProgress
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _buildChevron(),
            onTap: () {
              if (!isKakaoLoggedIn) {
                _promptLoginRequired();
                return;
              }
              _shareInvite();
            },
            indent: _kItemIndent,
          ),
          _buildInviteCodeInline(),
          const SizedBox(height: 40),
          _buildSectionHeader('고객 지원'),
          _buildMenuRow(
            leading: const Text('고객센터', style: _kItemTitleStyle),
            indent: _kItemIndent,
          ),
          _buildMenuRow(
            leading:
                const Text('카카오톡 1대1 문의', style: _kItemTitleStyle),
            indent: _kItemIndent,
          ),
          _buildMenuRow(
            leading:
                const Text('앱 버전: v2.0.0', style: _kItemTitleStyle),
            indent: _kItemIndent,
          ),
        ],
      ),
    );
  }
}
