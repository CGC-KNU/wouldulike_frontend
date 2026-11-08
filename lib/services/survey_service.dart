import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'coupon_service.dart';

/// 앱 내 설문 (서버 surveys 앱, 서버설계 Rev.6).
///
/// 상태: open(참여 전, 비로그인 포함) · claimed(답 + 쿠폰 = 끝) · closed(기간 밖)
/// · ineligible(대상에서 뺀 대학가, 11/8 계명대·영남대).
/// 답과 쿠폰은 쿠폰을 받는 순간 같이 저장된다 — 그 전에 나가면 아무것도 남지 않는다.
enum SurveyStatus { open, claimed, closed, ineligible, unknown }

SurveyStatus _parseStatus(Object? raw) {
  switch (raw?.toString()) {
    case 'open':
      return SurveyStatus.open;
    case 'ineligible':
      return SurveyStatus.ineligible;
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
    this.loggedIn = false,
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
      loggedIn: json['logged_in'] == true,
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

  /// 서버가 이 요청을 로그인으로 봤는지. 비로그인도 문항은 받는다.
  final bool loggedIn;
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

  /// 비로그인도 기간 안이면 open.
  final SurveyStatus status;
  final String? rewardTitle;
  final int? rewardValidDays;

  /// 홈 배너·쿠폰함 카드를 보일지 — 쿠폰까지 받기 전(참여 전)일 때만.
  bool get showEntry => status == SurveyStatus.open;
}

/// 쿠폰 고르기 오퍼 조회 결과 (GET /api/surveys/<code>/reward/).
class SurveyRewardResult {
  const SurveyRewardResult({this.status, this.offer, this.code, this.message});

  final SurveyStatus? status;
  final LimitedCouponOffer? offer;

  /// 실패 코드: ineligible · closed · network_error …
  final String? code;
  final String? message;
}

class SurveyService {
  SurveyService._();

  /// 설문 화면 결과가 바뀌면(응답 제출) 홈·쿠폰함이 배너를 다시 그리도록 알린다.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<ActiveSurvey?> fetchActive() async {
    try {
      // 토큰이 아예 없으면 인증 헤더를 붙이지 않는다(비로그인도 설문을 본다).
      final response = await ApiClient.getWithoutThrow(
        '/api/surveys/active/',
        authenticated: await ApiClient.hasAccessToken(),
      ).timeout(const Duration(seconds: 8));
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

  /// 비로그인도 문항을 받는다. 로그인했으면 토큰을 붙여 상태(claimed 등)를 받는다.
  static Future<SurveyDetail?> fetchDetail(String code) async {
    final response = await ApiClient.getWithoutThrow(
      '/api/surveys/$code/',
      authenticated: await ApiClient.hasAccessToken(),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) {
      throw ApiHttpException(404, response.body);
    }
    if (response.statusCode != 200) {
      throw ApiHttpException(response.statusCode, response.body);
    }
    final map = _decode(response);
    return map is Map<String, dynamic> ? SurveyDetail.fromJson(map) : null;
  }

  /// 쿠폰 고르기에 넘길 보상 오퍼. 답은 아직 저장하지 않는다.
  static Future<SurveyRewardResult> fetchReward(String code) async {
    try {
      final response = await ApiClient.getWithoutThrow('/api/surveys/$code/reward/')
          .timeout(const Duration(seconds: 10));
      final map = _decode(response);
      final body = map is Map<String, dynamic> ? map : const <String, dynamic>{};
      if (response.statusCode >= 400) {
        return SurveyRewardResult(
          code: body['code']?.toString() ?? 'http_${response.statusCode}',
          message: body['detail']?.toString(),
        );
      }
      final rawOffer = body['offer'];
      return SurveyRewardResult(
        status: _parseStatus(body['status']),
        offer: rawOffer is Map
            ? LimitedCouponOffer.fromJson(Map<String, dynamic>.from(rawOffer))
            : null,
      );
    } catch (e) {
      debugPrint('[Survey] reward failed: $e');
      return const SurveyRewardResult(
        code: 'network_error',
        message: '네트워크 오류로 불러오지 못했어요. 다시 시도해 주세요.',
      );
    }
  }

  /// 답 + 고른 식당을 한 번에 보낸다. 서버가 응답 저장과 쿠폰 발급을 같이 한다.
  static Future<LimitedCouponClaimResult> complete(
    String code, {
    required Map<String, String> answers,
    required int restaurantId,
    String? entry,
    int? elapsedSeconds,
  }) async {
    final result = await CouponService.postLimitedClaim(
      '/api/surveys/$code/complete/',
      {
        'answers': answers,
        'restaurant_id': restaurantId,
        if (entry != null) 'entry': entry,
        if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
      },
    );
    if (result.isSuccess) changes.value++;
    return result;
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
