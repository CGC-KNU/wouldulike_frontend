import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// 앱 내 설문 (서버 surveys 앱, 서버설계 Rev.6).
///
/// 상태: open(참여 전) · answered(응답, 쿠폰 미수령) · claimed(쿠폰까지 받음) · closed(기간 밖).
enum SurveyStatus { open, answered, claimed, closed, unknown }

SurveyStatus _parseStatus(Object? raw) {
  switch (raw?.toString()) {
    case 'open':
      return SurveyStatus.open;
    case 'answered':
      return SurveyStatus.answered;
    case 'claimed':
      return SurveyStatus.claimed;
    case 'closed':
      return SurveyStatus.closed;
  }
  return SurveyStatus.unknown;
}

class SurveyOption {
  const SurveyOption({required this.label, required this.value});

  factory SurveyOption.fromJson(Map<String, dynamic> json) => SurveyOption(
        label: json['label']?.toString() ?? '',
        value: json['value']?.toString() ?? '',
      );

  final String label;
  final String value;
}

class SurveyQuestion {
  const SurveyQuestion({
    required this.code,
    required this.badge,
    required this.text,
    required this.options,
    this.required = true,
  });

  factory SurveyQuestion.fromJson(Map<String, dynamic> json) => SurveyQuestion(
        code: json['code']?.toString() ?? '',
        badge: json['badge']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        required: json['required'] != false,
        options: (json['options'] is List)
            ? (json['options'] as List)
                .whereType<Map>()
                .map((o) => SurveyOption.fromJson(Map<String, dynamic>.from(o)))
                .toList()
            : const [],
      );

  final String code;
  final String badge;
  final String text;
  final bool required;
  final List<SurveyOption> options;
}

class SurveyDetail {
  const SurveyDetail({
    required this.code,
    required this.title,
    required this.headline,
    required this.description,
    required this.status,
    required this.questions,
    this.rewardTitle,
    this.rewardValidDays,
  });

  factory SurveyDetail.fromJson(Map<String, dynamic> json) {
    final reward = json['reward'] is Map
        ? Map<String, dynamic>.from(json['reward'] as Map)
        : const <String, dynamic>{};
    final days = int.tryParse(reward['valid_days']?.toString() ?? '');
    return SurveyDetail(
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      headline: json['headline']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: _parseStatus(json['status']),
      rewardTitle: reward['title']?.toString(),
      rewardValidDays: days,
      questions: (json['questions'] is List)
          ? (json['questions'] as List)
              .whereType<Map>()
              .map((q) => SurveyQuestion.fromJson(Map<String, dynamic>.from(q)))
              .toList()
          : const [],
    );
  }

  final String code;
  final String title;
  final String headline;
  final String description;
  final SurveyStatus status;
  final List<SurveyQuestion> questions;
  final String? rewardTitle;
  final int? rewardValidDays;
}

/// 지금 열린 설문 (GET /api/surveys/active/). 홈 배너·쿠폰함 카드가 쓴다.
class ActiveSurvey {
  const ActiveSurvey({
    required this.code,
    required this.title,
    required this.status,
    this.rewardTitle,
    this.rewardValidDays,
  });

  final String code;
  final String title;

  /// 로그인 안 했으면 unknown.
  final SurveyStatus status;
  final String? rewardTitle;
  final int? rewardValidDays;

  /// 홈 배너·쿠폰함 카드를 보일지 — 참여 전일 때만.
  bool get showEntry => status == SurveyStatus.open;
}

class SurveySubmitResult {
  const SurveySubmitResult({required this.ok, this.status, this.code, this.message});

  final bool ok;
  final SurveyStatus? status;
  final String? code;
  final String? message;
}

class SurveyService {
  SurveyService._();

  /// 설문 화면 결과가 바뀌면(응답 제출) 홈·쿠폰함이 배너를 다시 그리도록 알린다.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<ActiveSurvey?> fetchActive() async {
    try {
      final response = await ApiClient.getWithoutThrow('/api/surveys/active/')
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final map = _decode(response);
      if (map is! Map<String, dynamic>) return null;
      final survey = map['survey'];
      if (survey is! Map) return null;
      final s = Map<String, dynamic>.from(survey);
      final reward =
          s['reward'] is Map ? Map<String, dynamic>.from(s['reward'] as Map) : const {};
      return ActiveSurvey(
        code: s['code']?.toString() ?? '',
        title: s['title']?.toString() ?? '',
        status: _parseStatus(map['status']),
        rewardTitle: reward['title']?.toString(),
        rewardValidDays: int.tryParse(reward['valid_days']?.toString() ?? ''),
      );
    } catch (e) {
      debugPrint('[Survey] active failed: $e');
      return null;
    }
  }

  /// 401 이면 null 이 아니라 예외(ApiAuthException)가 나간다 — 화면이 비로그인 안내로 바꾼다.
  static Future<SurveyDetail?> fetchDetail(String code) async {
    final response = await ApiClient.get('/api/surveys/$code/')
        .timeout(const Duration(seconds: 8));
    final map = _decode(response);
    return map is Map<String, dynamic> ? SurveyDetail.fromJson(map) : null;
  }

  static Future<SurveySubmitResult> submit(
    String code,
    Map<String, String> answers, {
    String? entry,
  }) async {
    try {
      final response = await ApiClient.postWithoutThrow(
        '/api/surveys/$code/submit/',
        body: {'answers': answers, if (entry != null) 'entry': entry},
      ).timeout(const Duration(seconds: 10));
      final map = _decode(response);
      final body = map is Map<String, dynamic> ? map : const <String, dynamic>{};
      if (response.statusCode >= 400) {
        return SurveySubmitResult(
          ok: false,
          code: body['code']?.toString() ?? 'http_${response.statusCode}',
          message: body['detail']?.toString(),
        );
      }
      changes.value++;
      return SurveySubmitResult(ok: true, status: _parseStatus(body['status']));
    } catch (e) {
      debugPrint('[Survey] submit failed: $e');
      return const SurveySubmitResult(
        ok: false,
        code: 'network_error',
        message: '네트워크 오류로 보내지 못했어요. 다시 시도해 주세요.',
      );
    }
  }
}

/// 설문 링크에서 설문 코드를 꺼낸다. 아니면 null.
/// - https://wouldulike.com/survey/<code> (홈 프로모 블록·세로배너)
/// - wouldulike://survey/<code>
String? surveyCodeFromLink(Uri? uri) {
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'wouldulike') {
    final all = [if (host.isNotEmpty) host, ...segs];
    if (all.length >= 2 && all.first.toLowerCase() == 'survey') return all[1];
    return null;
  }
  if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      (host == 'wouldulike.com' || host == 'www.wouldulike.com') &&
      segs.length >= 2 &&
      segs.first.toLowerCase() == 'survey') {
    return segs[1];
  }
  return null;
}

dynamic _decode(http.Response response) {
  if (response.bodyBytes.isEmpty) return null;
  try {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    return null;
  }
}
