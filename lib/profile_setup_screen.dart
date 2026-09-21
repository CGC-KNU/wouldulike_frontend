import 'dart:convert';

import 'package:flutter/material.dart';

import 'config/analytics_events.dart';
import 'data/knu_profile_options.dart';
import 'onboarding/onboarding_prefs.dart';
import 'services/api_client.dart';
import 'services/app_config_service.dart';
import 'utils/analytics_logger.dart';
import 'services/user_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.initialProfile,
    this.onCompleted,
    this.isRequiredFlow = false,
  });

  final Map<String, dynamic>? initialProfile;
  final VoidCallback? onCompleted;
  final bool isRequiredFlow;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nicknameController;
  late final FocusNode _nicknameFocusNode;

  late final List<SchoolOption> _schools;
  late final List<CollegeOption> _colleges;
  late final List<DepartmentOption> _departments;

  String? _selectedSchoolCode;
  String? _selectedCollegeCode;
  String? _selectedDepartmentCode;

  int _nicknameRequestId = 0;
  String _lastCheckedNickname = '';
  bool _isCheckingNickname = false;
  bool _isNicknameAvailable = false;
  bool _isNicknameCheckSoftFailed = false;
  String? _nicknameMessage;
  bool _nicknameMessageIsError = false;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    final options = UserService.resolveProfileSetupOptions(profile);
    _schools = options.schools;
    _colleges = options.colleges;
    _departments = options.departments;

    _nicknameController = TextEditingController(
      text: profile?['nickname']?.toString() ?? '',
    );
    _nicknameFocusNode = FocusNode();

    _initializeSelections(profile);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _nicknameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;
    if (!_isFormSubmittable) {
      _showMessage('닉네임, 학교, 단과대, 학과를 모두 올바르게 입력해 주세요.');
      return;
    }

    final nickname = _nicknameController.text.trim();
    final school = _selectedSchool;
    final college = _selectedCollege;
    final department = _selectedDepartment;
    if (school == null || college == null || department == null) {
      _showMessage('학교, 단과대, 학과를 모두 선택해 주세요.');
      return;
    }

    if (!_isNicknameValidatedForCurrentInput) {
      _setNicknameState(
        message: '닉네임 중복 확인 버튼을 눌러 확인해 주세요',
        isError: true,
        available: false,
        checking: false,
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      await UserService.updateCurrentUserProfile(
        nickname: nickname,
        schoolCode: school.code,
        collegeCode: college.code,
        departmentCode: department.code,
        schoolName: school.name,
        departmentName: department.name,
      );
      if (!mounted) return;
      // 쿠폰 발급은 항상 보상 온보딩(튜토리얼)의 식당 선택 단계에서만 일어난다
      // (OnboardingRewardFlow._fetchIssuedCoupon) — 여기서 미리 발급해 버리면
      // 사용자가 튜토리얼에서 다른 식당을 골랐을 때 이미 발급된 이전 식당의
      // 쿠폰이 그대로 공개돼 버린다.
      if (widget.isRequiredFlow) {
        // 가입 완료 → 보상 온보딩(식당 선택→룰렛→사용법) 1회 노출 예약
        await OnboardingPrefs.markRewardPending();
      }
      if (!mounted) return;
      AnalyticsLogger.logEvent(
        AnalyticsEvents.userSignupCompleted,
        parameters: {
          AnalyticsEvents.paramSchoolCode: school.code,
          AnalyticsEvents.paramCollegeCode: college.code,
          AnalyticsEvents.paramDepartmentCode: department.code,
        },
      );
      AnalyticsLogger.setUserPropertiesFromProfile({
        'college_code': college.code,
        'department_code': department.code,
      });
      widget.onCompleted?.call();
      if (!widget.isRequiredFlow && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        _showMessage('프로필이 저장되었어요.');
      }
    } on ApiAuthException {
      _showMessage('로그인이 필요해요. 다시 로그인해 주세요.');
    } on ApiHttpException catch (e) {
      final code = UserService.parseErrorCode(e.body);
      if (e.statusCode == 409 && code == 'nickname_duplicated') {
        _setNicknameState(
          message: '이미 사용 중인 닉네임입니다',
          isError: true,
          available: false,
          checking: false,
        );
        return;
      }
      if (e.statusCode == 400 &&
          (code == 'nickname_invalid_format' || code == 'nickname_too_long')) {
        _setNicknameState(
          message: _messageForNicknameCode(code),
          isError: true,
          available: false,
          checking: false,
        );
        return;
      }
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

  Future<void> _checkNicknameByButton() async {
    final nickname = _nicknameController.text.trim();
    final localError = _localNicknameErrorMessage(nickname);
    if (localError != null) {
      _setNicknameState(
        message: localError,
        isError: true,
        available: false,
        checking: false,
      );
      return;
    }
    await _checkNicknameAvailability(nickname);
  }

  Future<bool> _checkNicknameAvailability(String nickname) async {
    final requestId = ++_nicknameRequestId;
    _setNicknameState(
      message: null,
      isError: false,
      available: false,
      checking: true,
    );

    final result = await UserService.checkNicknameAvailability(nickname);
    if (!mounted || requestId != _nicknameRequestId) return false;

    if (result.available) {
      _lastCheckedNickname = nickname;
      _setNicknameState(
        message: '사용 가능한 닉네임입니다',
        isError: false,
        available: true,
        checking: false,
        softFailed: false,
      );
      return true;
    }

    final code = result.code;
    if (code == null || code == 'availability_check_failed') {
      _lastCheckedNickname = nickname;
      _setNicknameState(
        message: '닉네임 확인이 지연되고 있어요. 저장 시 최종 확인됩니다.',
        isError: false,
        available: false,
        checking: false,
        softFailed: true,
      );
      return true;
    }

    _setNicknameState(
      message: _messageForNicknameCode(code),
      isError: true,
      available: false,
      checking: false,
      softFailed: false,
    );
    return false;
  }

  String? _localNicknameErrorMessage(String nickname) {
    final maxLength = AppConfigService.nicknameMaxLength;
    if (nickname.isEmpty) return '닉네임을 입력해 주세요';
    if (nickname.length > maxLength) {
      return '닉네임은 $maxLength자 이하로 입력해 주세요';
    }
    final regex = RegExp(AppConfigService.nicknamePattern);
    if (!regex.hasMatch(nickname)) {
      return '한글/영문/숫자만 입력 가능해요 (공백/특수문자 불가)';
    }
    return null;
  }

  String _messageForNicknameCode(String? code) {
    switch (code) {
      case 'nickname_duplicated':
        return '이미 사용 중인 닉네임입니다';
      case 'nickname_invalid_format':
        return '한글/영문/숫자만 입력 가능해요 (공백/특수문자 불가)';
      case 'nickname_too_long':
        return '닉네임은 ${AppConfigService.nicknameMaxLength}자 이하로 입력해 주세요';
      default:
        return '사용할 수 없는 닉네임입니다';
    }
  }

  void _setNicknameState({
    required String? message,
    required bool isError,
    required bool available,
    required bool checking,
    bool softFailed = false,
  }) {
    if (!mounted) return;
    setState(() {
      _nicknameMessage = message;
      _nicknameMessageIsError = isError;
      _isNicknameAvailable = available;
      _isCheckingNickname = checking;
      _isNicknameCheckSoftFailed = softFailed;
    });
  }

  void _handleNicknameChanged(String value) {
    final nickname = value.trim();
    final localError = _localNicknameErrorMessage(nickname);
    // 한글 조합 중 setState 호출 시 글자 중복 발생 → 프레임 종료 후 상태 갱신
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isNicknameAvailable = false;
        _isNicknameCheckSoftFailed = false;
        _lastCheckedNickname = '';
        if (nickname.isEmpty) {
          _nicknameMessage = null;
          _nicknameMessageIsError = false;
        } else if (localError != null) {
          _nicknameMessage = localError;
          _nicknameMessageIsError = true;
        } else {
          _nicknameMessage = '중복 확인 버튼을 눌러 닉네임을 확인해 주세요';
          _nicknameMessageIsError = false;
        }
      });
    });
  }

  void _initializeSelections(Map<String, dynamic>? profile) {
    final schoolCodeFromServer = profile?['school_code']?.toString();
    final schoolNameFromServer = profile?['school']?.toString();
    _selectedSchoolCode = _resolveSchoolCode(
      schoolCode: schoolCodeFromServer,
      schoolName: schoolNameFromServer,
    );

    final collegeCodeFromServer = profile?['college_code']?.toString();
    final departmentCodeFromServer = profile?['department_code']?.toString();
    final departmentNameFromServer = profile?['department']?.toString();

    _selectedCollegeCode = _resolveCollegeCode(
      collegeCode: collegeCodeFromServer,
      departmentCode: departmentCodeFromServer,
      departmentName: departmentNameFromServer,
    );

    _selectedDepartmentCode = _resolveDepartmentCode(
      departmentCode: departmentCodeFromServer,
      departmentName: departmentNameFromServer,
      collegeCode: _selectedCollegeCode,
    );
  }

  String? _resolveSchoolCode({
    required String? schoolCode,
    required String? schoolName,
  }) {
    if (schoolCode != null &&
        _schools.any((SchoolOption e) => e.code == schoolCode)) {
      return schoolCode;
    }
    if (schoolName != null) {
      final match = _schools.where((e) => e.name == schoolName).toList();
      if (match.isNotEmpty) return match.first.code;
    }
    if (_schools.length == 1) return _schools.first.code;
    return null;
  }

  String? _resolveCollegeCode({
    required String? collegeCode,
    required String? departmentCode,
    required String? departmentName,
  }) {
    if (collegeCode != null &&
        _colleges.any((CollegeOption e) => e.code == collegeCode)) {
      return collegeCode;
    }
    if (departmentCode != null) {
      final byDepartmentCode = _departments
          .where((DepartmentOption e) => e.code == departmentCode)
          .toList();
      if (byDepartmentCode.isNotEmpty) return byDepartmentCode.first.collegeCode;
    }
    if (departmentName != null) {
      final byDepartmentName = _departments
          .where((DepartmentOption e) => e.name == departmentName)
          .toList();
      if (byDepartmentName.isNotEmpty) return byDepartmentName.first.collegeCode;
    }
    return null;
  }

  String? _resolveDepartmentCode({
    required String? departmentCode,
    required String? departmentName,
    required String? collegeCode,
  }) {
    if (departmentCode != null &&
        _departments.any((DepartmentOption e) => e.code == departmentCode)) {
      if (collegeCode == null) return departmentCode;
      final sameCollege = _departments.any((DepartmentOption e) =>
          e.code == departmentCode && e.collegeCode == collegeCode);
      if (sameCollege) return departmentCode;
    }

    if (departmentName != null) {
      final fromName = _departments.where((DepartmentOption e) {
        final collegeMatched = collegeCode == null || e.collegeCode == collegeCode;
        return collegeMatched && e.name == departmentName;
      }).toList();
      if (fromName.isNotEmpty) return fromName.first.code;
    }
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

  void _skipProfile() {
    if (_isSaving) return;
    widget.onCompleted?.call();
    if (!widget.isRequiredFlow && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneColor = _isFormSubmittable
        ? const Color(0xFF1C203C)
        : const Color(0xFF9CA3AF);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 100,
        leading: widget.isRequiredFlow
            ? TextButton(
                onPressed: _isSaving ? null : _skipProfile,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '건너뛰기',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              )
            : TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  '취소',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
        title: Text(
          widget.isRequiredFlow ? '프로필 설정' : '프로필 편집',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving || !_isFormSubmittable ? null : _saveProfile,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1C203C),
                    ),
                  )
                : Text(
                    '완료',
                    style: TextStyle(
                      color: doneColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                child: Column(
                  children: [
                    const SizedBox(height: 34),
                    _ProfileTextFieldRow(
                      label: '닉네임',
                      hintText: '닉네임 입력',
                      controller: _nicknameController,
                      focusNode: _nicknameFocusNode,
                      enabled: !_isSaving,
                      onChanged: _handleNicknameChanged,
                      trailing: SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: _isSaving || _isCheckingNickname
                              ? null
                              : _checkNicknameByButton,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            foregroundColor: const Color(0xFF1F2937),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('중복 확인'),
                        ),
                      ),
                    ),
                    if (_isCheckingNickname)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(104, 6, 20, 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '중복 확인 중...',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_nicknameMessage != null && !_isCheckingNickname)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(104, 6, 20, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _nicknameMessage!,
                            style: TextStyle(
                              color: _nicknameMessageIsError
                                  ? const Color(0xFFDC2626).withOpacity(0.68)
                                  : const Color(0xFF16A34A).withOpacity(0.82),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(104, 0, 20, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '조건: 한글/영문/숫자만, 공백/특수문자 불가, 15자 이하',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ProfileSelectRow(
                      label: '학교',
                      selectedCode: _selectedSchoolCode,
                      options: _schools
                          .map((SchoolOption e) =>
                              _SelectOption(code: e.code, name: e.name))
                          .toList(),
                      hintText: '학교 선택',
                      enabled: !_isSaving,
                      onChanged: (String? code) {
                        if (code == null) return;
                        setState(() {
                          _selectedSchoolCode = code;
                        });
                      },
                    ),
                    _ProfileSelectRow(
                      label: '단과대',
                      selectedCode: _selectedCollegeCode,
                      options: _colleges
                          .map((CollegeOption e) =>
                              _SelectOption(code: e.code, name: e.name))
                          .toList(),
                      hintText: '단과대 선택',
                      enabled: !_isSaving,
                      onChanged: (String? code) {
                        setState(() {
                          _selectedCollegeCode = code;
                          _selectedDepartmentCode = null;
                        });
                      },
                    ),
                    _ProfileSelectRow(
                      label: '학과',
                      selectedCode: _selectedDepartmentCode,
                      options: _availableDepartmentOptions,
                      hintText: _selectedCollegeCode == null
                          ? '단과대를 먼저 선택해 주세요'
                          : '학과 선택',
                      enabled: !_isSaving && _selectedCollegeCode != null,
                      onChanged: (String? code) {
                        setState(() {
                          _selectedDepartmentCode = code;
                        });
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '닉네임, 학교, 단과대, 학과를 모두 설정해야 서비스를 이용할 수 있어요.',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 10.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SchoolOption? get _selectedSchool {
    final matched = _schools.where((SchoolOption e) => e.code == _selectedSchoolCode);
    return matched.isEmpty ? null : matched.first;
  }

  CollegeOption? get _selectedCollege {
    final matched =
        _colleges.where((CollegeOption e) => e.code == _selectedCollegeCode);
    return matched.isEmpty ? null : matched.first;
  }

  DepartmentOption? get _selectedDepartment {
    final matched = _departments
        .where((DepartmentOption e) => e.code == _selectedDepartmentCode);
    return matched.isEmpty ? null : matched.first;
  }

  List<_SelectOption> get _availableDepartmentOptions {
    if (_selectedCollegeCode == null) return const <_SelectOption>[];
    return _departments
        .where((DepartmentOption e) => e.collegeCode == _selectedCollegeCode)
        .map((DepartmentOption e) => _SelectOption(code: e.code, name: e.name))
        .toList();
  }

  bool get _isFormSubmittable {
    final nickname = _nicknameController.text.trim();
    final isNicknameChecked =
        nickname.isNotEmpty &&
        _lastCheckedNickname == nickname &&
        !_isCheckingNickname &&
        (_isNicknameAvailable || _isNicknameCheckSoftFailed);
    final hasSchool = _selectedSchool != null;
    final hasCollege = _selectedCollege != null;
    final hasDepartment = _selectedDepartment != null;
    return !_isSaving && isNicknameChecked && hasSchool && hasCollege && hasDepartment;
  }

  bool get _isNicknameValidatedForCurrentInput {
    final nickname = _nicknameController.text.trim();
    return nickname.isNotEmpty &&
        _lastCheckedNickname == nickname &&
        (_isNicknameAvailable || _isNicknameCheckSoftFailed);
  }
}

class _ProfileTextFieldRow extends StatelessWidget {
  const _ProfileTextFieldRow({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    this.onChanged,
    this.trailing,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFF3F4F6)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
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
              focusNode: focusNode,
              enabled: enabled,
              onChanged: onChanged,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 18,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _SelectOption {
  const _SelectOption({
    required this.code,
    required this.name,
  });

  final String code;
  final String name;
}

class _ProfileSelectRow extends StatelessWidget {
  const _ProfileSelectRow({
    required this.label,
    required this.selectedCode,
    required this.options,
    required this.hintText,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String? selectedCode;
  final List<_SelectOption> options;
  final String hintText;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFF3F4F6)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                color: enabled ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedCode != null &&
                        options.any((element) => element.code == selectedCode)
                    ? selectedCode
                    : null,
                hint: Text(
                  hintText,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 16,
                  ),
                ),
                items: options
                    .map(
                      (_SelectOption option) => DropdownMenuItem<String>(
                        value: option.code,
                        child: Text(
                          option.name,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: enabled ? onChanged : null,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                dropdownColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
