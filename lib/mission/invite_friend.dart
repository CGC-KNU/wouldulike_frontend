import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:new1/coupon_list_screen.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/services/kakao_share_service.dart';
import 'package:new1/widgets/referral_code_sheet.dart';

/// 환영 미션이 끝나면 홈 배너 자리를 친구 초대가 이어받는다.
/// 미션은 환영 미션 하나뿐이므로, 그 뒤로는 이 배너만 남는다.
const _navy = Color(0xFF202038);
const _ink = Color(0xFF17171B);
const _muted = Color(0xFF6B6B73);
const _sub = Color(0xFF9A9AA2);
const _surface = Color(0xFFF6F6F8);
const _yellow = Color(0xFFFFD84D);
const _yellowSoft = Color(0xFFFFF6CD);

/// ===== 홈 배너 =====
class InviteFriendBanner extends StatelessWidget {
  const InviteFriendBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: _yellowSoft,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: _yellow,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.waving_hand_rounded,
                      size: 21, color: _navy),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '친구와 함께 시작해요',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.46,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '내 코드를 보내면 친구도 혜택을 받아요',
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.12,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: _navy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 친구 초대 화면 =====
/// 내 초대 코드 · 친구 초대(카카오 공유) · 추천인 코드 입력 세 가지를 담는다.
class InviteFriendScreen extends StatefulWidget {
  const InviteFriendScreen({super.key, this.initialCode});

  /// 테스트·캐시 복원처럼 이미 알고 있는 코드가 있으면 첫 로딩을 생략한다.
  final String? initialCode;

  @override
  State<InviteFriendScreen> createState() => _InviteFriendScreenState();
}

class _InviteFriendScreenState extends State<InviteFriendScreen> {
  String? _code;
  String? _error;
  bool _isLoading = true;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    final initialCode = widget.initialCode;
    if (initialCode != null && initialCode.isNotEmpty) {
      _code = initialCode;
      _isLoading = false;
    } else {
      _loadCode();
    }
  }

  Future<void> _loadCode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await CouponService.fetchInviteCode();
      // 서버가 code / invite_code / coupon_code 중 하나로 내려준다.
      final code = result['code']?.toString() ??
          result['invite_code']?.toString() ??
          result['coupon_code']?.toString();
      if (!mounted) return;
      setState(() {
        _code = code;
        _isLoading = false;
        if (code == null || code.isEmpty) _error = '초대 코드를 불러오지 못했어요.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '코드를 불러오지 못했어요.';
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('초대 코드를 복사했어요.')));
  }

  Future<void> _share() async {
    final code = _code;
    if (code == null || code.isEmpty || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      await KakaoShareService.shareInvite(context, referralCode: code);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _openReferralSheet() async {
    final result = await showModalBottomSheet<ReferralSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ReferralCodeSheet(),
    );
    if (!mounted || result == null) return;
    // 코드가 통과하면 쿠폰이 발급된다. 발급 흐름은 항상 쿠폰함으로 이어진다.
    if (result.status == ReferralSheetStatus.success && result.openCoupons) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CouponListScreen(source: 'invite'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const Text(
          '친구 초대',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        iconTheme: const IconThemeData(color: _ink),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          const Text(
            '같이 쓰면,\n혜택도 같이 받아요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.28,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '내 코드를 공유하거나 친구에게 받은 코드를 입력하세요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              height: 1.45,
              color: _muted,
            ),
          ),
          const SizedBox(height: 24),
          _buildCodeCard(),
          const SizedBox(height: 14),
          _buildShareButton(),
          const SizedBox(height: 28),
          _buildReferralCard(),
        ],
      ),
    );
  }

  /// 내 초대 코드. 탭하면 클립보드로 복사된다.
  Widget _buildCodeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 19, 16, 19),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MY INVITE CODE',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFFB9B9C7),
            ),
          ),
          const SizedBox(height: 9),
          if (_isLoading)
            const SizedBox(
              height: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else if (_error != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFE0E5),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loadCode,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text(
                    '다시 시도',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    _code ?? '',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  color: const Color(0xFFCACAD5),
                  tooltip: '복사',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildShareButton() {
    final ready = !_isLoading && _error == null && (_code?.isNotEmpty ?? false);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (ready && !_isSharing) ? _share : null,
        icon: _isSharing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded, size: 18),
        label: const Text('친구에게 코드 보내기'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _yellow,
          foregroundColor: _navy,
          disabledBackgroundColor: const Color(0xFFE9EBF1),
          disabledForegroundColor: const Color(0xFFA9B0BD),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// 남의 추천인 코드를 입력하는 자리. 입력 UI는 마이페이지와 같은 시트를 쓴다.
  Widget _buildReferralCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openReferralSheet,
        borderRadius: BorderRadius.circular(16),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(17, 16, 15, 16),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.keyboard_rounded, size: 19, color: _navy),
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '추천인 코드 입력',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '친구에게 받은 코드가 있다면 입력하세요',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11.5,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 19, color: _sub),
            ],
          ),
        ),
      ),
    );
  }
}
