import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:new1/services/api_client.dart';
import 'package:new1/services/coupon_service.dart';
import 'package:new1/widgets/coupon_issued_dialog.dart';

/// 친구 초대·학생회·기획 이벤트 코드를 한 칸에서 받는 바텀시트.
/// 종류 판단은 앱이 하지 않고 서버 code_kind / event_kind를 따른다.
enum ReferralSheetStatus { dismissed, success, loginRequired, alreadyClaimed }

class ReferralSheetResult {
  const ReferralSheetResult({
    required this.status,
    this.coupon,
    this.issuedCodes = const [],
    this.tag = '쿠폰 발급',
    this.title = '쿠폰이 발급되었어요',
    this.message,
  });

  final ReferralSheetStatus status;
  final UserCoupon? coupon;
  final List<String> issuedCodes;
  final String tag;
  final String title;
  final String? message;
}

Future<ReferralSheetResult?> presentReferralCodeSheet(
  BuildContext context,
) async {
  final result = await showModalBottomSheet<ReferralSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const ReferralCodeSheet(),
  );
  if (!context.mounted || result == null) return result;

  if (result.status == ReferralSheetStatus.loginRequired) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('로그인이 필요해요.')));
    await Navigator.of(context).pushNamed('/login');
    return result;
  }

  if (result.status == ReferralSheetStatus.alreadyClaimed) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(result.message ?? '이미 받은 쿠폰이에요')),
      );
    return result;
  }

  if (result.status == ReferralSheetStatus.success) {
    await showCouponIssuedDialog(
      context,
      tag: result.tag,
      title: result.title,
      coupon: result.coupon,
      issuedCodes: result.issuedCodes,
    );
  }
  return result;
}

class ReferralCodeSheet extends StatefulWidget {
  const ReferralCodeSheet({super.key});

  @override
  State<ReferralCodeSheet> createState() => ReferralCodeSheetState();
}

class ReferralCodeSheetState extends State<ReferralCodeSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _inputError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() {
        _inputError = '코드를 입력해 주세요.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _inputError = null;
    });

    var closed = false;
    try {
      final accepted = await CouponService.acceptReferralCode(refCode: code);
      final copy = referralIssuedCopy(accepted);
      UserCoupon? coupon;
      try {
        coupon = await CouponService.fetchIssuedCouponCard(
          issuedCodes: accepted.issuedCouponCodes,
        );
      } catch (_) {
        // 목록 동기화 실패는 성공 팝업을 막지 않는다.
      }
      if (!mounted) return;
      closed = true;
      Navigator.of(context).pop(
        ReferralSheetResult(
          status: ReferralSheetStatus.success,
          coupon: coupon,
          issuedCodes: accepted.issuedCouponCodes,
          tag: copy.tag,
          title: copy.title,
        ),
      );
    } on ApiAuthException {
      if (!mounted) return;
      closed = true;
      Navigator.of(context).pop(
        const ReferralSheetResult(status: ReferralSheetStatus.loginRequired),
      );
    } on ApiHttpException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        closed = true;
        Navigator.of(context).pop(
          const ReferralSheetResult(status: ReferralSheetStatus.loginRequired),
        );
        return;
      }
      if (e.statusCode == 409) {
        closed = true;
        Navigator.of(context).pop(
          ReferralSheetResult(
            status: ReferralSheetStatus.alreadyClaimed,
            message: _conflictMessage(e.body),
          ),
        );
        return;
      }
      setState(() {
        _inputError = _inputErrorMessage(e.statusCode, e.body);
      });
    } on ApiNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _inputError = '네트워크 오류: $e';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _inputError = '코드를 입력하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (mounted && !closed) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _conflictMessage(String body) {
    final parsed = _parseApiError(body);
    if (parsed != null &&
        parsed.trim().isNotEmpty &&
        !_looksLikeMachineError(parsed)) {
      return parsed;
    }
    return '이미 받은 쿠폰이에요';
  }

  String _inputErrorMessage(int statusCode, String body) {
    if (statusCode == 429) {
      return '잠시 후 다시 시도해 주세요.';
    }
    final parsed = _parseApiError(body);
    if (parsed != null && _looksLikeInvalidCode(parsed)) {
      return '없는 코드예요';
    }
    if (parsed != null && parsed.trim().isNotEmpty) {
      return parsed;
    }
    if (statusCode == 400) {
      return '없는 코드예요';
    }
    return '코드를 확인해 주세요.';
  }

  bool _looksLikeInvalidCode(String message) {
    final lower = message.toLowerCase();
    return lower.contains('invalid referral') ||
        lower.contains('invalid code') ||
        lower.contains('not found');
  }

  bool _looksLikeMachineError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('_') ||
        lower.contains('already') ||
        lower.contains('invalid') ||
        RegExp(r'^[a-z0-9\-]+$').hasMatch(lower);
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
          if (entry.key == 'code' || entry.key == 'ok') continue;
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit = !_isSubmitting && _controller.text.trim().isNotEmpty;
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHandle(),
                  const SizedBox(height: 20),
                  const Text(
                    '코드 입력하기',
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
                    '친구 초대 코드나 학생회·이벤트 코드를 같은 칸에 입력하면 쿠폰을 받을 수 있어요.',
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
                    '친구 초대 또는 이벤트 코드',
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      controller: _controller,
                      enabled: !_isSubmitting,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(
                        color: Color(0xFF39393E),
                        fontSize: 16,
                        fontFamily: 'Pretendard',
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: '친구 초대 또는 이벤트 코드',
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
                    '※ 대소문자는 구분하지 않아요.',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
