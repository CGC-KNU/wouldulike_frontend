import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/knu_profile_options.dart';
import '../question_list.dart';
import 'api_client.dart';

class CategoryItem {
  const CategoryItem({
    required this.code,
    required this.label,
    required this.iconKey,
    required this.sortOrder,
    this.aliases = const [],
  });

  final String code;
  final String label;
  final String iconKey;
  final int sortOrder;
  final List<String> aliases;
}

class RaffleTermsSection {
  const RaffleTermsSection({required this.title, required this.items});

  final String title;
  final List<String> items;
}

/// GET /api/config/categories/, /api/config/content/{quiz_questions|raffle_terms}/
/// 비어 있거나 404면 기존 로컬 원본을 그대로 쓴다.
/// 학교/단과대/학과는 서버 콘텐츠 API 없이 로컬 원본(경북대 고정 목록)만 쓴다.
class MasterContent {
  MasterContent._();

  static const _fallbackOrder = [
    'ALL',
    'KOREAN',
    'CHINESE',
    'JAPANESE',
    'WESTERN',
    'SNACK',
    'PUB',
    'CAFE',
    'DONKATSU',
    'HAMBURGER',
    'ETC',
  ];

  static const _fallbackLabels = {
    'ALL': '전체',
    'KOREAN': '한식',
    'CHINESE': '중식',
    'JAPANESE': '일식',
    'WESTERN': '양식',
    'SNACK': '분식',
    'PUB': '술집',
    'CAFE': '카페',
    'DONKATSU': '돈가스',
    'HAMBURGER': '햄버거',
    'ETC': '기타',
    'UNCLASSIFIED': '미분류',
  };

  static const _fallbackAlias = {
    '전체': 'ALL',
    '한식': 'KOREAN',
    '고기/구이': 'KOREAN',
    '중식': 'CHINESE',
    '일식': 'JAPANESE',
    '양식': 'WESTERN',
    '분식': 'SNACK',
    '술집': 'PUB',
    'BAR': 'PUB',
    '주점': 'PUB',
    '카페': 'CAFE',
    '돈가스': 'DONKATSU',
    '햄버거': 'HAMBURGER',
    '기타': 'ETC',
    '아시안': 'ETC',
    '미분류': 'UNCLASSIFIED',
  };

  static const _knownSvgKeys = {
    'all',
    'korean',
    'chinese',
    'japanese',
    'western',
    'snack',
    'pub',
    'cafe',
    'donkatsu',
    'hamburger',
    'etc',
  };

  static const _pngByCode = {
    'ALL': 'assets/images/total.png',
    'KOREAN': 'assets/images/korean.png',
    'CHINESE': 'assets/images/chinese.png',
    'JAPANESE': 'assets/images/japanese.png',
    'WESTERN': 'assets/images/western.png',
    'SNACK': 'assets/images/snack.png',
    'PUB': 'assets/images/pub.png',
    'CAFE': 'assets/images/cafe.png',
    'DONKATSU': 'assets/images/donkatsu.png',
    'HAMBURGER': 'assets/images/hamburger.png',
    'ETC': 'assets/images/total.png',
    'UNCLASSIFIED': 'assets/images/total.png',
  };

  static List<CategoryItem> _categories = const [];
  static List<Map<String, dynamic>> _questions = const [];
  static List<RaffleTermsSection> _raffleSections = const [];

  static Future<void> prefetch() async {
    await Future.wait([
      _loadCategories(),
      _loadQuizQuestions(),
      _loadRaffleTerms(),
    ]);
  }

  static Future<void> _loadCategories() async {
    try {
      final decoded = await _getJson('/api/config/categories/');
      final raw = decoded['categories'];
      if (raw is! List || raw.isEmpty) return;
      final parsed = <CategoryItem>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final code = (map['code'] ?? '').toString().trim().toUpperCase();
        if (code.isEmpty) continue;
        final aliases = <String>[];
        final aliasRaw = map['aliases'];
        if (aliasRaw is List) {
          for (final alias in aliasRaw) {
            final text = alias.toString().trim();
            if (text.isNotEmpty) aliases.add(text);
          }
        }
        parsed.add(
          CategoryItem(
            code: code,
            label: (map['label'] ?? code).toString(),
            iconKey: (map['icon_key'] ?? code.toLowerCase()).toString(),
            sortOrder: _asInt(map['sort_order'], i),
            aliases: aliases,
          ),
        );
      }
      parsed.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (parsed.isNotEmpty) _categories = parsed;
    } catch (e) {
      debugPrint('[MasterContent] categories fetch failed: $e');
    }
  }

  static Future<void> _loadQuizQuestions() async {
    try {
      final decoded = await _getJson('/api/config/content/quiz_questions/');
      final payload = _unwrap(decoded);
      final raw = payload['questions'];
      if (raw is! List || raw.isEmpty) return;
      final parsed = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final text = (map['text'] ?? map['questionText'] ?? '').toString();
        final answersRaw = map['answers'];
        if (text.isEmpty || answersRaw is! List) continue;
        final answers = <Map<String, dynamic>>[];
        for (final answer in answersRaw) {
          if (answer is! Map) continue;
          final amap = Map<String, dynamic>.from(answer);
          answers.add({
            'text': (amap['text'] ?? '').toString(),
            'score': _answerScore(amap),
          });
        }
        if (answers.isEmpty) continue;
        parsed.add({'questionText': text, 'answers': answers});
      }
      if (parsed.isNotEmpty) _questions = parsed;
    } catch (e) {
      debugPrint('[MasterContent] quiz fetch failed: $e');
    }
  }

  static Future<void> _loadRaffleTerms() async {
    try {
      final decoded = await _getJson('/api/config/content/raffle_terms/');
      final payload = _unwrap(decoded);
      final sectionsRaw = payload['sections'];
      if (sectionsRaw is List && sectionsRaw.isNotEmpty) {
        final parsed = <RaffleTermsSection>[];
        for (final item in sectionsRaw) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final title = (map['title'] ?? '').toString();
          final items = _stringList(map['clauses'] ?? map['items']);
          if (title.isEmpty && items.isEmpty) continue;
          parsed.add(RaffleTermsSection(
            title: title.isEmpty ? '안내' : title,
            items: items,
          ));
        }
        if (parsed.isNotEmpty) {
          _raffleSections = parsed;
          return;
        }
      }
      final clauses = _clauseTexts(payload['clauses']);
      if (clauses.isNotEmpty) {
        _raffleSections = _groupClauses(clauses);
      }
    } catch (e) {
      debugPrint('[MasterContent] raffle terms fetch failed: $e');
    }
  }

  static Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await ApiClient.getWithoutThrow(
      path,
      authenticated: false,
    );
    if (response.statusCode >= 400) {
      return const {};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return const {};
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> decoded) {
    final value = decoded['value'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return decoded;
  }

  static int _asInt(dynamic raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  static int _answerScore(Map<String, dynamic> answer) {
    final score = answer['score'];
    if (score is int) return score;
    if (score is num) return score.round();
    if (score is String) return int.tryParse(score) ?? 0;
    final scores = answer['scores'];
    if (scores is Map) {
      final values = scores.values.whereType<num>();
      if (values.isNotEmpty) return values.first.round();
    }
    final id = (answer['id'] ?? '').toString().toUpperCase();
    return id == 'B' || id == '1' ? 1 : 0;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        out.add(item.trim());
      } else if (item is Map) {
        final text = (item['text'] ?? '').toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }
    return out;
  }

  static List<String> _clauseTexts(dynamic raw) {
    if (raw is! List) return const [];
    final pairs = <({int order, String text})>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is String && item.trim().isNotEmpty) {
        pairs.add((order: i + 1, text: item.trim()));
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final text = (map['text'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        pairs.add((order: _asInt(map['order'], i + 1), text: text));
      }
    }
    pairs.sort((a, b) => a.order.compareTo(b.order));
    return pairs.map((e) => e.text).toList();
  }

  static List<RaffleTermsSection> _groupClauses(List<String> clauses) {
    const titles = ['응모 방법', '추첨과 발표', '쿠폰 사용', '꼭 확인해주세요'];
    final sections = <RaffleTermsSection>[];
    for (var i = 0; i < clauses.length; i += 4) {
      final end = (i + 4) > clauses.length ? clauses.length : i + 4;
      final titleIndex = i ~/ 4;
      sections.add(
        RaffleTermsSection(
          title: titleIndex < titles.length ? titles[titleIndex] : '안내',
          items: clauses.sublist(i, end),
        ),
      );
    }
    return sections;
  }

  static List<Map<String, dynamic>> get quizQuestions =>
      _questions.isNotEmpty ? _questions : kFallbackQuestionList;

  // 학과 콘텐츠 API(/api/config/content/majors/)는 백엔드에 아직 구성되지 않아
  // 제거했다. 학교/단과대/학과는 로컬 원본(경북대 고정 목록)만 쓴다.
  static List<SchoolOption> get schools => knuSchools;

  static List<CollegeOption> get colleges => knuColleges;

  static List<DepartmentOption> get departments => knuDepartments;

  static List<RaffleTermsSection> get raffleSections =>
      _raffleSections.isNotEmpty ? _raffleSections : kFallbackRaffleSections;

  static List<CategoryItem> get categories {
    if (_categories.isNotEmpty) return _categories;
    return [
      for (var i = 0; i < _fallbackOrder.length; i++)
        CategoryItem(
          code: _fallbackOrder[i],
          label: _fallbackLabels[_fallbackOrder[i]] ?? _fallbackOrder[i],
          iconKey: _fallbackOrder[i].toLowerCase(),
          sortOrder: i,
          aliases: const [],
        ),
    ];
  }

  static List<String> get stripOrder {
    final codes = [
      for (final item in categories)
        if (item.code != 'UNCLASSIFIED') item.code,
    ];
    if (!codes.contains('ALL')) codes.insert(0, 'ALL');
    return codes;
  }

  static Set<String> get knownCodes =>
      {for (final item in categories) item.code, 'UNCLASSIFIED'};

  static String normalize(String raw, {bool unknownAsEtc = true}) {
    final mapped = _mappedCode(raw);
    if (mapped.isNotEmpty) return mapped;
    return unknownAsEtc ? 'ETC' : raw.trim();
  }

  static String _mappedCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final upper = trimmed.toUpperCase();
    for (final item in categories) {
      if (item.code == upper) return item.code;
      if (item.label == trimmed || item.label.toUpperCase() == upper) {
        return item.code;
      }
      for (final alias in item.aliases) {
        if (alias == trimmed || alias.toUpperCase() == upper) return item.code;
      }
    }
    return _fallbackAlias[trimmed] ??
        _fallbackAlias[upper] ??
        (_fallbackLabels.containsKey(upper) ? upper : '');
  }

  static String labelOf(String code) {
    for (final item in categories) {
      if (item.code == code) return item.label;
    }
    return _fallbackLabels[code] ?? code;
  }

  static String svgOf(String code) {
    final key = normalize(code);
    for (final item in categories) {
      if (item.code == key) {
        return svgPath(item.iconKey, item.code);
      }
    }
    return svgPath(key.toLowerCase(), key);
  }

  static String pngPath(String code) =>
      _pngByCode[normalize(code)] ?? 'assets/images/total.png';

  static String svgPath(String iconKey, String code) {
    final key = iconKey.trim().toLowerCase();
    if (_knownSvgKeys.contains(key)) {
      return 'assets/icons/category/$key.svg';
    }
    final fromCode = code.trim().toLowerCase();
    if (_knownSvgKeys.contains(fromCode)) {
      return 'assets/icons/category/$fromCode.svg';
    }
    return 'assets/icons/category/all.svg';
  }
}

const kFallbackRaffleSections = <RaffleTermsSection>[
  RaffleTermsSection(title: '응모 방법', items: [
    '마일리지는 매장 구분 없이 전 매장 공통으로 사용해요.',
    '응모하면 표시된 마일리지가 즉시 차감돼요.',
    '한 응모 건에 1인 1회만 응모할 수 있어요.',
    '보유 마일리지가 부족하면 응모할 수 없어요.',
  ]),
  RaffleTermsSection(title: '추첨과 발표', items: [
    '마감 시각이 지나면 응모자 중 무작위로 추첨해요.',
    '결과는 당첨자 발표와 내 응모에서 확인할 수 있어요.',
    '당첨되면 식사권 쿠폰이 쿠폰함으로 자동 발급돼요.',
    '당첨자 닉네임은 개인정보 보호를 위해 일부만 표시해요.',
  ]),
  RaffleTermsSection(title: '쿠폰 사용', items: [
    '식사권 쿠폰은 제휴 전 매장에서 사용할 수 있어요.',
    '쿠폰은 유효기간 안에 써야 하고, 기간이 지나면 자동으로 사라져요.',
    '현금 교환·양도·재발급은 되지 않아요.',
    '다른 할인·쿠폰과 중복 사용은 매장 정책에 따라 제한될 수 있어요.',
  ]),
  RaffleTermsSection(title: '꼭 확인해주세요', items: [
    '응모 후 취소와 마일리지 환급은 되지 않아요.',
    '미당첨이어도 차감된 마일리지는 돌려드리지 않아요.',
    '부정한 방법으로 적립한 마일리지로 응모하면 당첨이 취소될 수 있어요.',
    '운영상의 사유로 응모가 중단되면 차감된 마일리지를 돌려드려요.',
  ]),
];
