import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:new1/services/api_client.dart';
import 'package:new1/services/coupon_service.dart';

/// 추천인(초대) 코드 입력 바텀시트.
/// 마이페이지와 친구 초대 화면이 함께 쓴다.
enum ReferralSheetStatus { dismissed, success }

class ReferralSheetResult {
  const ReferralSheetResult({
    required this.status,
    this.openCoupons = false,
  });

  final ReferralSheetStatus status;
  final bool openCoupons;
}

enum ReferralSheetMode { input, success }

class ReferralCodeSheet extends StatefulWidget {
  const ReferralCodeSheet({super.key});

  @override
  State<ReferralCodeSheet> createState() => ReferralCodeSheetState();
}

class ReferralCodeSheetState extends State<ReferralCodeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _inputError;
  ReferralSheetMode _mode = ReferralSheetMode.input;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_mode != ReferralSheetMode.input) return;
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _inputError = '초대 코드를 입력해 주세요.';
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
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _mode = ReferralSheetMode.success;
      });
    } on ApiHttpException catch (e) {
      final message = _parseApiError(e.body) ?? '초대 코드를 확인해 주세요.';
      if (!mounted) return;
      if (e.statusCode == 409) {
        setState(() {
          _inputError = message;
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
        _inputError = '초대 코드를 입력하지 못했어요. 잠시 후 다시 시도해 주세요.';
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
        openCoupons: openCoupons,
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
        const SizedBox(height: 20),
        const Text(
          '초대 코드 입력하기',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF39393E),
            fontFamily: 'Pretendard',
            height: 1.21,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '초대 코드를 입력하면 쿠폰 보상을 바로 받을 수 있어요!',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF797979),
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
            height: 1.29,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '초대 코드',
          style: TextStyle(
            color: Color(0xFF797979),
            fontSize: 15,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                width: 2,
                color: _inputError != null
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFD9D9D9),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: _controller,
            enabled: !_isSubmitting,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            keyboardType: TextInputType.text,
            style: const TextStyle(
              color: Color(0xFF39393E),
              fontSize: 16,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: '예: FRIEND1234',
              hintStyle: TextStyle(
                color: Color(0xFFBABAC0),
                fontSize: 16,
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w500,
              ),
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
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
        ),
        if (_inputError != null) ...[
          const SizedBox(height: 6),
          Text(
            _inputError!,
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 12,
              fontFamily: 'Pretendard',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '※ 초대 코드는 대소문자를 구분하지 않아요.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canSubmit ? _submit : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1C203C),
              disabledBackgroundColor: const Color(0xFFD9D9D9),
              foregroundColor: Colors.white,
              disabledForegroundColor: const Color(0xFF9CA3AF),
              padding: const EdgeInsets.symmetric(vertical: 14),
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
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    Navigator.of(context).pop(
                      const ReferralSheetResult(
                        status: ReferralSheetStatus.dismissed,
                      ),
                    );
                  },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF797979),
              textStyle: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
            child: const Text('나중에 할게요'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessBody() {
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
                '쿠폰이 발급되었어요',
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
                    const TextSpan(
                      text: '쿠폰함에서 ',
                    ),
                    const TextSpan(
                      text: '새로 발급된 쿠폰',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(
                      text: '을 확인해 보세요.',
                    ),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    Widget body;
    switch (_mode) {
      case ReferralSheetMode.input:
        body = _buildInputBody();
        break;
      case ReferralSheetMode.success:
        body = _buildSuccessBody();
        break;
    }

    body = KeyedSubtree(
      key: ValueKey<ReferralSheetMode>(_mode),
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
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
            SingleChildScrollView(
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}
