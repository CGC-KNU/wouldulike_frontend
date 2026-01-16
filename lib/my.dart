import 'dart:convert';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _referralInputLocked = false;
  ReferralSheetStatus? _lastReferralStatus;
  String? _lastReferralMessage;
  String? _kakaoId;

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
    final kakaoId = prefs.getString('user_kakao_id');
    if (!mounted) return;
    setState(() {
      isKakaoLoggedIn = loggedIn;
      _kakaoId = kakaoId;
      if (!loggedIn) {
        inviteCode = null;
        _inviteError = null;
        _referralInputLocked = false;
        _lastReferralStatus = null;
        _lastReferralMessage = null;
        _kakaoId = null;
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
      final message = _extractDetailMessage(e.body) ?? '추천 코드를 불러오지 못했어요.';
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

  Future<void> _showReferralCodeSheet() async {
    final initialStatus = _referralInputLocked ? _lastReferralStatus : null;
    final initialMessage = _referralInputLocked ? _lastReferralMessage : null;
    final result = await showModalBottomSheet<ReferralSheetResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ReferralCodeSheet(
        initialStatus: initialStatus,
        initialMessage: initialMessage,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    switch (result.status) {
      case ReferralSheetStatus.success:
        setState(() {
          _referralInputLocked = true;
          _lastReferralStatus = ReferralSheetStatus.alreadyAccepted;
          _lastReferralMessage = result.noticeMessage ?? '이미 추천 코드를 입력했어요.';
        });
        if (result.openCoupons) {
          _openCouponList();
        }
        break;
      case ReferralSheetStatus.alreadyAccepted:
        setState(() {
          _referralInputLocked = true;
          _lastReferralStatus = result.status;
          _lastReferralMessage = result.noticeMessage ?? '이미 추천 코드를 입력한 계정이에요.';
        });
        break;
      case ReferralSheetStatus.dismissed:
        break;
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

  Future<void> _openKakaoTalkInquiry() async {
    const url = 'https://open.kakao.com/o/s09ikE1h';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카카오톡 오픈채팅을 열 수 없어요.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('링크를 열 수 없어요: $e')),
      );
    }
  }

  Future<void> _openHomepage() async {
    try {
      final response = await ApiClient.get('/api/url/', authenticated: false);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url']?.toString() ?? '';

      if (url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('홈페이지 URL이 설정되지 않았어요.')),
        );
        return;
      }

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('홈페이지를 열 수 없어요.')),
        );
      }
    } on ApiHttpException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('홈페이지 URL을 불러오지 못했어요.')),
      );
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('네트워크 오류: $e')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('홈페이지를 열 수 없어요: $e')),
      );
    }
  }

  Widget _buildAccountTile() {
    final isBusy = _isKakaoLoginInProgress || _isKakaoLogoutInProgress;
    final label = isKakaoLoggedIn ? '로그아웃' : '로그인';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMenuRow(
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
        ),
        // 카카오 ID 표시 (로그인 상태일 때만)
        if (isKakaoLoggedIn && _kakaoId != null && _kakaoId!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: _kItemIndent + 44, // 아이콘 너비(32) + 간격(12) + 좌측 여백
              top: 6,
              bottom: 6,
            ),
            child: Text(
              '우주라이크 ID: $_kakaoId',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
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
            '내 추천코드',
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
          leading: const Text('추천 코드 입력하기', style: _kItemTitleStyle),
          trailing: _buildChevron(),
          onTap: () {
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          _buildSectionHeader('계정 정보'),
          _buildAccountTile(),
          const SizedBox(height: 24),
          _buildSectionHeader('활동 내역'),
          _buildMenuRow(
            leading: const Text('쿠폰 사용 내역', style: _kItemTitleStyle),
            trailing: _buildChevron(),
            onTap: _openCouponList,
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
            leading: const Text('홈페이지', style: _kItemTitleStyle),
            trailing: _buildChevron(),
            onTap: _openHomepage,
            indent: _kItemIndent,
          ),
          _buildMenuRow(
            leading: const Text('카카오톡 1대1 문의', style: _kItemTitleStyle),
            trailing: _buildChevron(),
            onTap: _openKakaoTalkInquiry,
            indent: _kItemIndent,
          ),
          _buildMenuRow(
            leading: const Text('앱 버전: v2.0.0', style: _kItemTitleStyle),
            indent: _kItemIndent,
          ),
        ],
      ),
    );
  }
}

enum ReferralSheetStatus { dismissed, success, alreadyAccepted }

class ReferralSheetResult {
  const ReferralSheetResult({
    required this.status,
    this.noticeMessage,
    this.openCoupons = false,
  });

  final ReferralSheetStatus status;
  final String? noticeMessage;
  final bool openCoupons;
}

enum _ReferralSheetMode { input, success, locked }

class _ReferralCodeSheet extends StatefulWidget {
  const _ReferralCodeSheet({
    super.key,
    this.initialStatus,
    this.initialMessage,
  });

  final ReferralSheetStatus? initialStatus;
  final String? initialMessage;

  @override
  State<_ReferralCodeSheet> createState() => _ReferralCodeSheetState();
}

class _ReferralCodeSheetState extends State<_ReferralCodeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _inputError;
  _ReferralSheetMode _mode = _ReferralSheetMode.input;
  String? _successMessage;
  String? _lockedMessage;

  @override
  void initState() {
    super.initState();
    final initialStatus = widget.initialStatus;
    if (initialStatus == ReferralSheetStatus.success) {
      _mode = _ReferralSheetMode.success;
      _successMessage = widget.initialMessage;
    } else if (initialStatus == ReferralSheetStatus.alreadyAccepted) {
      _mode = _ReferralSheetMode.locked;
      _lockedMessage = widget.initialMessage;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_mode != _ReferralSheetMode.input) return;
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _inputError = '추천 코드를 입력해 주세요.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _inputError = null;
    });

    try {
      await CouponService.acceptReferralCode(refCode: code);
      try {
        await CouponService.fetchMyCoupons();
      } catch (_) {
        // 쿠폰 목록 동기화 실패는 성공 흐름을 막지 않는다.
      }
      if (!mounted) return;
      setState(() {
        _mode = _ReferralSheetMode.success;
        _successMessage = '친구 추천 쿠폰이 발급되었어요!';
      });
    } on ApiHttpException catch (e) {
      final message = _parseApiError(e.body) ?? '추천 코드를 확인해 주세요.';
      if (!mounted) return;
      if (e.statusCode == 409) {
        setState(() {
          _mode = _ReferralSheetMode.locked;
          _lockedMessage = message;
        });
      } else {
        setState(() {
          _inputError = message;
        });
      }
    } on ApiAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _inputError = e.message;
      });
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _inputError = '네트워크 오류: $e';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _inputError = '추천 코드를 입력하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _completeSuccess(bool openCoupons) {
    if (!mounted) return;
    Navigator.of(context).pop(
      ReferralSheetResult(
        status: ReferralSheetStatus.success,
        noticeMessage: _successMessage ?? '이미 추천 코드를 입력했어요.',
        openCoupons: openCoupons,
      ),
    );
  }

  void _completeLocked() {
    if (!mounted) return;
    Navigator.of(context).pop(
      ReferralSheetResult(
        status: ReferralSheetStatus.alreadyAccepted,
        noticeMessage: _lockedMessage ?? '이미 추천 코드를 입력한 계정이에요.',
      ),
    );
  }

  String? _parseApiError(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['detail'] is String &&
            decoded['detail'].toString().isNotEmpty) {
          return decoded['detail'].toString();
        }
        if (decoded['message'] is String &&
            decoded['message'].toString().isNotEmpty) {
          return decoded['message'].toString();
        }
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) {
              return first;
            }
          } else if (value is String && value.isNotEmpty) {
            return value;
          }
        }
      } else if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is String && first.isNotEmpty) {
          return first;
        }
      }
    } catch (_) {}
    return null;
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildInputBody() {
    final canSubmit = !_isSubmitting && _controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        const SizedBox(height: 16),
        const Text(
          '추천 코드 입력하기',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '추천 코드를 입력하면 쿠폰 보상을 바로 받을 수 있어요!',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          enabled: !_isSubmitting,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: '추천 코드',
            hintText: '예: FRIEND1234',
            errorText: _inputError,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF312E81)),
            ),
          ),
          onChanged: (_) {
            setState(() {
              _inputError = null;
            });
          },
          onSubmitted: (_) {
            if (canSubmit) {
              _submit();
            }
          },
        ),
        const SizedBox(height: 4),
        const Text(
          '※ 추천 코드는 대소문자를 구분하지 않아요.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canSubmit ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF312E81),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isSubmitting
                  ? const SizedBox(
                      key: ValueKey('progress'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '쿠폰 받기',
                      key: ValueKey('label'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () {
                  Navigator.of(context).pop(
                    const ReferralSheetResult(
                      status: ReferralSheetStatus.dismissed,
                    ),
                  );
                },
          child: const Text('나중에 할게요'),
        ),
      ],
    );
  }

  Widget _buildSuccessBody() {
    final message = _successMessage ?? '친구 추천 쿠폰이 발급되었어요!';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: ShapeDecoration(
            color: const Color(0xFFF2F2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '친구 추천 쿠폰이 발급되었어요',
                style: TextStyle(
                  color: Color(0xFF39393E),
                  fontSize: 19,
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w800,
                  height: 1.21,
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF39393E),
                    fontSize: 14,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w500,
                    height: 1.29,
                  ),
                  children: [
                    TextSpan(
                      text: '친구의 추천 코드 입력이 완료되었어요.\n쿠폰함에서 ',
                    ),
                    const TextSpan(
                      text: '새로 발급된 쿠폰',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(
                      text: '을 바로 확인해 보세요.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 13,
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _completeSuccess(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFFBABAC0)),
                  foregroundColor: const Color(0xFF39393E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                child: const Text('닫기'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _completeSuccess(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C203C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: -0.32,
                  ),
                ),
                child: const Text('내 쿠폰 보기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLockedBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(),
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(36),
          ),
          child: const Icon(
            Icons.lock_outline,
            color: Color(0xFFB91C1C),
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '이미 추천 코드를 입력했어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _completeLocked,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF312E81),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '확인',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    Widget body;
    switch (_mode) {
      case _ReferralSheetMode.input:
        body = _buildInputBody();
        break;
      case _ReferralSheetMode.success:
        body = _buildSuccessBody();
        break;
      case _ReferralSheetMode.locked:
        body = _buildLockedBody();
        break;
    }

    body = KeyedSubtree(
      key: ValueKey<_ReferralSheetMode>(_mode),
      child: body,
    );

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: body,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: bottomInset + 24,
          top: 12,
        ),
        child: SingleChildScrollView(
          child: content,
        ),
      ),
    );
  }
}
