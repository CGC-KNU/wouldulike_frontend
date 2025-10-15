import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:new1/start_survey.dart';
import 'package:new1/wish.dart';

import 'services/auth_service.dart';
import 'services/coupon_service.dart';
import 'services/kakao_share_service.dart';
import 'services/api_client.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  String uuid = '';
  String typeCode = '정보 없음';
  String typeName = '정보 없음';
  String description = '설명 정보를 불러오지 못했어요.';
  String summary = '정보 없음';
  String menuMbti = '정보 없음';
  String mealExample = '정보 없음';
  String matchingType = '정보 없음';
  String nonMatching = '정보 없음';
  bool hasTypeInfo = false;
  bool isLoading = true;
  bool isKakaoLoggedIn = false;
  String? inviteCode;
  bool _isInviteLoading = false;
  bool _isShareInProgress = false;
  bool _isKakaoLogoutInProgress = false;
  String? _inviteError;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUuid = prefs.getString('user_uuid');
      final storedTypeCode = prefs.getString('user_type');
      final loggedIn = prefs.getBool('kakao_logged_in') ?? false;
      setState(() {
        uuid = _shortenUuid(storedUuid);
        typeCode = storedTypeCode ?? '정보 없음';
        typeName = prefs.getString('type_name') ?? '정보 없음';
        description =
            prefs.getString('type_description') ?? '설명 정보를 불러오지 못했어요.';
        summary = prefs.getString('type_summary') ?? '정보 없음';
        menuMbti = prefs.getString('menu_and_mbti') ?? '정보 없음';
        mealExample = prefs.getString('meal_example') ?? '정보 없음';
        matchingType = prefs.getString('matching_type') ?? '정보 없음';
        nonMatching = prefs.getString('non_matching') ?? '정보 없음';
        hasTypeInfo = storedTypeCode != null && storedTypeCode.trim().isNotEmpty;
        isKakaoLoggedIn = loggedIn;
        if (!loggedIn) {
          inviteCode = null;
          _inviteError = null;
        }
        isLoading = false;
      });
      if (loggedIn) {
        await _loadInviteCode();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  String _shortenUuid(String? value) {
    if (value == null || value.isEmpty) return '';
    final parts = value.split('-');
    return parts.isNotEmpty ? parts.first : value;
  }

  Future<void> _handleKakaoLogin() async {
    try {
      final installed = await isKakaoTalkInstalled();
      final token = installed
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
      final prefs = await SharedPreferences.getInstance();
      final guestUuid = prefs.getString('user_uuid');
      await AuthService.loginWithKakao(token.accessToken, guestUuid: guestUuid);
      await prefs.setBool('signup_coupon_checked', false);
      if (!mounted) return;
      setState(() {
        isKakaoLoggedIn = true;
      });
      await _loadInviteCode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카카오 로그인에 실패했어요: $e')),
      );
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
    } catch (e) {
      debugPrint('Error logging out from Kakao: ');
      errorMessage ??= '카카오 로그아웃에 실패했어요. 다시 시도해 주세요.';
    }

    try {
      await AuthService.logout();
    } catch (e) {
      debugPrint('Error logging out from backend: ');
      errorMessage ??= '로그아웃 중 오류가 발생했어요. 다시 시도해 주세요.';
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('kakao_logged_in');
        await prefs.remove('jwt_access_token');
        await prefs.remove('jwt_refresh_token');
      } catch (prefsError) {
        debugPrint('Error clearing local tokens: ');
      }
    }

    await loadUserData();

    if (!mounted) return;
    setState(() {
      _isKakaoLogoutInProgress = false;
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          errorMessage ?? '카카오 로그아웃이 완료됐어요.',
        ),
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
      final message = '네트워크 오류: ' + e.toString();
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
    if (inviteCode == null || inviteCode!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: inviteCode!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('추천 코드가 복사되었어요!')),
    );
  }

  Future<void> _shareInvite() async {
    if (!isKakaoLoggedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('카카오 로그인이 필요해요.')),
      );
      return;
    }
    if (_isShareInProgress) return;
    if (!mounted) return;
    setState(() {
      _isShareInProgress = true;
    });
    try {
      final code = await _loadInviteCode();
      if (!mounted) return;
      if (code == null || code.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('추천 코드를 불러오지 못했어요. 잠시 후 다시 시도해주세요.')),
        );
        return;
      }
      await KakaoShareService.shareInvite(context, referralCode: code);
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

  Widget _buildInviteCard(double screenWidth) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard_outlined, color: Color(0xFF312E81)),
              const SizedBox(width: 8),
              const Text(
                '내 추천 코드',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '다시 불러오기',
                onPressed: _isInviteLoading ? null : _loadInviteCode,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isInviteLoading)
            const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_inviteError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _inviteError!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loadInviteCode,
                  child: const Text('다시 시도'),
                ),
              ],
            )
          else if (inviteCode != null && inviteCode!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        inviteCode!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF312E81),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: '복사하기',
                      onPressed: _copyInviteCode,
                    ),
                  ],
                ),
              )
            else
              const Text('추천 코드를 불러오지 못했어요.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final bool isShareBusy = _isShareInProgress || _isInviteLoading;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Image.asset(
          'assets/images/logo1.png',
          height: screenHeight * 0.03,
        ),
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF312E81),
        ),
      )
          : ListView(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenHeight * 0.02,
        ),
        children: [
          _buildLoginBanner(screenWidth, screenHeight),
          SizedBox(height: screenHeight * 0.03),
          if (isKakaoLoggedIn) ...[
            SizedBox(height: screenHeight * 0.02),
            _buildInviteCard(screenWidth),
            SizedBox(height: screenHeight * 0.03),
          ],
          _buildMenuTile(
            context: context,
            icon: Icons.info_outline,
            title: '유형 코드 설명',
            subtitle: hasTypeInfo
                ? '$typeCode · $typeName'
                : '유형 정보를 불러올 수 없어요.',
            onTap: hasTypeInfo
                ? () => _openTypeDetail(context)
                : () => _showMissingTypeSnack(context),
          ),
          SizedBox(height: screenHeight * 0.02),
          _buildMenuTile(
            context: context,
            icon: Icons.assignment_outlined,
            title: '유형 조사 다시하기',
            subtitle: '취향 설문을 다시 진행해요.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StartSurveyScreen(),
                ),
              );
            },
          ),
          SizedBox(height: screenHeight * 0.02),
          _buildMenuTile(
            context: context,
            icon: Icons.favorite_border,
            title: '찜한 맛집 보기',
            subtitle: '내가 저장한 맛집 목록을 확인해요.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => WishlistScreen(),
                ),
              );
            },
          ),
          SizedBox(height: screenHeight * 0.02),
          _buildMenuTile(
            context: context,
            icon: Icons.share_outlined,
            title: '카카오톡으로 친구 초대',
            subtitle: '추천코드와 설치 링크를 공유해요.',
            onTap: () => _shareInvite(),
            trailing: isShareBusy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.share,
                    color: Color(0xFF312E81),
                  ),
            enabled: !isShareBusy,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginBanner(double screenWidth, double screenHeight) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF312E81),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF312E81).withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isKakaoLoggedIn ? '카카오 로그인 완료' : '카카오 로그인하기',
            style: TextStyle(
              fontSize: screenWidth * 0.048,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: screenHeight * 0.01),
          Text(
            isKakaoLoggedIn
                ? '카카오 계정이 연결되어 있습니다.'
                : '카카오 계정을 연결하면 더 많은 기능을 이용할 수 있어요.',
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              color: Colors.black54,
            ),
          ),
          if (uuid.isNotEmpty) ...[
            SizedBox(height: screenHeight * 0.012),
            Text(
              '내 UUID: $uuid',
              style: TextStyle(
                fontSize: screenWidth * 0.034,
                color: Colors.black45,
              ),
            ),
          ],
          if (isKakaoLoggedIn) ...[
            SizedBox(height: screenHeight * 0.02),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isKakaoLogoutInProgress ? null : _handleKakaoLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF312E81),
                  side: const BorderSide(
                    color: Color(0xFF312E81),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.015,
                  ),
                ),
                child: _isKakaoLogoutInProgress
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('카카오 로그아웃'),
              ),
            ),
          ],
          if (!isKakaoLoggedIn) ...[
            SizedBox(height: screenHeight * 0.02),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleKakaoLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEE500),
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: screenHeight * 0.015,
                  ),
                ),
                child: const Text('카카오로 로그인'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool enabled = true,
  }) {
    final VoidCallback? effectiveOnTap = enabled ? onTap : null;
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(
          color: Color(0xFF312E81),
          width: 1.2,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: const Color(0xFF312E81),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Colors.black54,
          ),
        ),
        trailing: trailing ??
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF312E81),
            ),
        onTap: effectiveOnTap,
        enabled: enabled,
      ),
    );
  }
  void _openTypeDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TypeDetailScreen(
          typeCode: typeCode,
          typeName: typeName,
          description: description,
          summary: summary,
          menuMbti: menuMbti,
          mealExample: mealExample,
          matchingType: matchingType,
          nonMatching: nonMatching,
        ),
      ),
    );
  }

  void _showMissingTypeSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('유형 정보를 먼저 받아와 주세요.')),
    );
  }
}

class TypeDetailScreen extends StatelessWidget {
  final String typeCode;
  final String typeName;
  final String description;
  final String summary;
  final String menuMbti;
  final String mealExample;
  final String matchingType;
  final String nonMatching;

  const TypeDetailScreen({
    super.key,
    required this.typeCode,
    required this.typeName,
    required this.description,
    required this.summary,
    required this.menuMbti,
    required this.mealExample,
    required this.matchingType,
    required this.nonMatching,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final imagePath = 'assets/images/$typeCode.png';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('유형 코드 설명'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenHeight * 0.02,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoContainer(
              screenWidth: screenWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      imagePath,
                      height: screenHeight * 0.25,
                      width: screenWidth * 0.6,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: screenHeight * 0.25,
                          alignment: Alignment.center,
                          color: Colors.grey[200],
                          child: Text(
                            typeCode,
                            style: TextStyle(
                              fontSize: screenWidth * 0.05,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF312E81),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Text(
                    typeCode,
                    style: TextStyle(
                      fontSize: screenWidth * 0.045,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF312E81),
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.01),
                  Text(
                    typeName,
                    style: TextStyle(
                      fontSize: screenWidth * 0.048,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    SizedBox(height: screenHeight * 0.012),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.03),
            _buildInfoContainer(
              screenWidth: screenWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    screenWidth: screenWidth,
                    icon: Icons.description_outlined,
                    title: '유형 설명',
                    text: summary,
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  _buildSection(
                    screenWidth: screenWidth,
                    icon: Icons.restaurant_menu_outlined,
                    title: '잘 어울리는 메뉴 & MBTI',
                    text: menuMbti,
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  _buildSection(
                    screenWidth: screenWidth,
                    icon: Icons.fastfood_outlined,
                    title: '추천 식사 예시',
                    text: mealExample,
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  _buildSection(
                    screenWidth: screenWidth,
                    icon: Icons.people_alt_outlined,
                    title: '잘 맞는 유형',
                    text: matchingType,
                  ),
                  SizedBox(height: screenHeight * 0.025),
                  _buildSection(
                    screenWidth: screenWidth,
                    icon: Icons.warning_amber_outlined,
                    title: '맞지 않는 유형',
                    text: nonMatching,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoContainer({
    required double screenWidth,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.045),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF312E81),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF312E81).withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSection({
    required double screenWidth,
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: screenWidth * 0.06,
              color: const Color(0xFF312E81),
            ),
            SizedBox(width: screenWidth * 0.03),
            Text(
              title,
              style: TextStyle(
                fontSize: screenWidth * 0.048,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SizedBox(height: screenWidth * 0.025),
        Text(
          text,
          style: TextStyle(
            fontSize: screenWidth * 0.038,
            color: Colors.black87,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
