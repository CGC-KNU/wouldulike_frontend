import 'dart:convert';

import 'package:flutter/material.dart';

import 'services/api_client.dart';
import 'services/user_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.initialProfile,
    this.onCompleted,
  });

  final Map<String, dynamic>? initialProfile;
  final VoidCallback? onCompleted;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _schoolController;
  late final TextEditingController _studentIdController;
  late final TextEditingController _departmentController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _nicknameController = TextEditingController(
      text: profile?['nickname']?.toString() ?? '',
    );
    _schoolController = TextEditingController(
      text: profile?['school']?.toString() ?? '',
    );
    _studentIdController = TextEditingController(
      text: profile?['student_id']?.toString() ?? '',
    );
    _departmentController = TextEditingController(
      text: profile?['department']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _schoolController.dispose();
    _studentIdController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    final nickname = _nicknameController.text.trim();
    final school = _schoolController.text.trim();
    final studentId = _studentIdController.text.trim();
    final department = _departmentController.text.trim();

    final validationError = _validate(
      nickname: nickname,
      school: school,
      studentId: studentId,
      department: department,
    );
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      await UserService.updateCurrentUserProfile(
        nickname: nickname,
        school: school,
        studentId: studentId,
        department: department,
      );
      if (!mounted) return;
      widget.onCompleted?.call();
      _showMessage('프로필이 저장되었어요.');
    } on ApiAuthException {
      _showMessage('로그인이 필요해요. 다시 로그인해 주세요.');
    } on ApiHttpException catch (e) {
      _showMessage(_parseApiError(e.body) ?? '프로필 저장 중 오류가 발생했어요.');
    } on ApiNetworkException {
      _showMessage('네트워크 상태를 확인한 뒤 다시 시도해 주세요.');
    } catch (_) {
      _showMessage('프로필 저장에 실패했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      } else {
        _isSaving = false;
      }
    }
  }

  String? _validate({
    required String nickname,
    required String school,
    required String studentId,
    required String department,
  }) {
    if (nickname.isEmpty ||
        school.isEmpty ||
        studentId.isEmpty ||
        department.isEmpty) {
      return '닉네임, 학교, 학번, 학과를 모두 입력해 주세요.';
    }
    if (nickname.length > 50) return '닉네임은 50자 이하로 입력해 주세요.';
    if (school.length > 100) return '학교는 100자 이하로 입력해 주세요.';
    if (studentId.length > 20) return '학번은 20자 이하로 입력해 주세요.';
    if (department.length > 100) return '학과는 100자 이하로 입력해 주세요.';
    return null;
  }

  String? _parseApiError(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is String && decoded.isNotEmpty) {
        return decoded;
      }
      if (decoded is Map<String, dynamic>) {
        if (decoded['detail'] is String &&
            decoded['detail'].toString().isNotEmpty) {
          return decoded['detail'].toString();
        }
        for (final value in decoded.values) {
          if (value is String && value.isNotEmpty) return value;
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.isNotEmpty) return first;
          }
        }
      }
    } catch (_) {}
    return body;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '프로필 편집',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _AvatarPlaceholder(),
                        SizedBox(width: 14),
                        Text(
                          '사진 또는 아바타 수정',
                          style: TextStyle(
                            color: Color(0xFF4F46E5),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _ProfileFieldRow(
                      label: '닉네임',
                      hintText: '닉네임',
                      controller: _nicknameController,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 6),
                    _ProfileFieldRow(
                      label: '학교',
                      hintText: '학교',
                      controller: _schoolController,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 6),
                    _ProfileFieldRow(
                      label: '학번',
                      hintText: '학번',
                      controller: _studentIdController,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 6),
                    _ProfileFieldRow(
                      label: '학과',
                      hintText: '학과',
                      controller: _departmentController,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '필수 항목: 닉네임, 학교, 학번, 학과',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2937),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '저장',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
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

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 34,
          backgroundColor: Color(0xFFE5E7EB),
          child: Icon(Icons.person, size: 34, color: Color(0xFF6B7280)),
        ),
        const SizedBox(width: 8),
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Icon(
            Icons.sentiment_satisfied_alt_outlined,
            color: Color(0xFF6B7280),
            size: 28,
          ),
        ),
      ],
    );
  }
}

class _ProfileFieldRow extends StatelessWidget {
  const _ProfileFieldRow({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.enabled,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF3F4F6)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF111827),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 18,
                ),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
