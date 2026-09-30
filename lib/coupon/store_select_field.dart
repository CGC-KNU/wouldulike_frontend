import 'package:flutter/material.dart';

import '../data/campus_options.dart';
import '../services/affiliate_service.dart';
import '../services/user_service.dart';

/// 전 매장 쿠폰(마일리지 식사권 등)을 쓸 매장을 고르는 드롭다운.
///
/// 쿠폰에 매장이 정해져 있지 않으면(`restaurant_id == null`) 사용 시점에 매장을 골라야 한다.
/// 비밀번호는 여기서 고른 매장의 PIN이므로, PIN 입력창과 같은 다이얼로그에 둔다.
class StoreSelectField extends StatelessWidget {
  const StoreSelectField({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.label = '사용할 매장',
  });

  final AffiliateRestaurantSummary? selected;
  final ValueChanged<AffiliateRestaurantSummary> onSelected;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    final store = selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF797979),
            fontSize: 15,
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        // PIN 입력창과 같은 테두리·높이를 써서 한 다이얼로그 안에서 따로 놀지 않게 한다.
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: !enabled
              ? null
              : () async {
                  final picked = await pickAffiliateStore(context);
                  if (picked != null) onSelected(picked);
                },
          child: Container(
            width: double.infinity,
            height: 40,
            decoration: ShapeDecoration(
              color: enabled ? Colors.white : const Color(0xFFF6F6F6),
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 2, color: Color(0xFFD9D9D9)),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    store?.name ?? '매장을 선택하세요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: store == null
                          ? const Color(0xFF9A9AA0)
                          : const Color(0xFF39393E),
                      fontSize: 16,
                      fontFamily: 'Pretendard',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.expand_more,
                  size: 20,
                  color: Color(0xFF797979),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 제휴 매장 목록 시트(대학가·이름 검색 포함). 고르면 그 매장을 돌려준다.
///
/// 매장이 20개를 넘어가면 스크롤만으로는 찾기 힘들어 검색칸을 같이 둔다.
/// 대학가는 프로필 값으로 시작하고, 식사권은 어느 대학가에서나 쓸 수 있으니 바꿀 수 있게 둔다.
Future<AffiliateRestaurantSummary?> pickAffiliateStore(
  BuildContext context,
) async {
  final future = _storesFuture ??= AffiliateService.fetchRestaurants();
  final initialCampus = await _profileCampus();
  if (!context.mounted) return null;
  return showModalBottomSheet<AffiliateRestaurantSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      var keyword = '';
      var campus = initialCampus;
      return StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          // 검색 키보드가 올라와도 목록이 가려지지 않게 한다.
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7E9EF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '어디서 쓸까요?',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF191F28),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '이 쿠폰은 어느 대학가의 제휴 매장에서나 쓸 수 있어요.',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4E5968),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: CampusChips(
                    selected: campus,
                    onSelected: (value) =>
                        setSheetState(() => campus = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '매장 이름 검색',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (value) =>
                        setSheetState(() => keyword = value.trim()),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<AffiliateRestaurantSummary>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      final all = snapshot.data ?? const [];
                      // 목록을 못 불러온 것과 검색 결과가 없는 것은 다른 상황이라 문구를 나눈다.
                      if (all.isEmpty) {
                        return const Center(
                          child: Text(
                            '매장을 불러오지 못했어요.',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              color: Color(0xFF4E5968),
                            ),
                          ),
                        );
                      }
                      final items = filterStoresForPick(
                        all,
                        campus: campus,
                        keyword: keyword,
                      );
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            keyword.isEmpty && campus != kCampusFilterAll
                                ? '$campus에 등록된 매장이 아직 없어요.\n다른 대학가를 골라 보세요.'
                                : '검색 결과가 없어요.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              color: Color(0xFF4E5968),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final meta = [
                            item.category,
                            if (campus == kCampusFilterAll) item.campus ?? '',
                          ].where((s) => s.isNotEmpty).join(' · ');
                          return ListTile(
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF191F28),
                              ),
                            ),
                            subtitle: meta.isEmpty
                                ? null
                                : Text(
                                    meta,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 12,
                                      color: Color(0xFF8B95A1),
                                    ),
                                  ),
                            trailing:
                                const Icon(Icons.chevron_right, size: 18),
                            onTap: () => Navigator.of(sheetContext).pop(item),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 대학가를 고르면 그 대학가로 명시된 매장만, '전체'면 모두. 대학가 미지정 매장은 '전체'에서만 보인다.
List<AffiliateRestaurantSummary> filterStoresForPick(
  List<AffiliateRestaurantSummary> stores, {
  required String campus,
  String keyword = '',
}) {
  return stores.where((r) {
    if (campus != kCampusFilterAll && r.campus != campus) return false;
    return keyword.isEmpty || r.name.contains(keyword);
  }).toList();
}

Future<String> _profileCampus() async {
  try {
    final profile = await UserService.fetchCurrentUserProfile()
        .timeout(const Duration(seconds: 3));
    final campus = profile?['campus']?.toString();
    if (isKnownCampus(campus)) return campus!;
  } catch (_) {
    // 프로필을 못 읽어도 매장은 고를 수 있어야 한다.
  }
  return kCampusFilterAll;
}

/// 매장 선택 시트 상단의 대학가 칩 (전체 · 경북대 · 영남대 · 계명대).
class CampusChips extends StatelessWidget {
  const CampusChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const options = [kCampusFilterAll, ...kCampusOptions];
    return Wrap(
      spacing: 8,
      children: [
        for (final value in options)
          InkWell(
            onTap: () => onSelected(value),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: value == selected
                    ? const Color(0xFF192132)
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: value == selected
                      ? const Color(0xFF192132)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Text(
                value == kCampusFilterAll ? '전체' : value,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Pretendard',
                  fontWeight:
                      value == selected ? FontWeight.w700 : FontWeight.w500,
                  color: value == selected
                      ? Colors.white
                      : const Color(0xFF797979),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 드롭다운을 다시 열 때마다 매장 목록을 새로 받지 않도록 앱 실행 동안 캐시한다.
/// ponytail: 프로세스 수명 캐시. 매장 정보가 자주 바뀌면 TTL을 붙일 것.
Future<List<AffiliateRestaurantSummary>>? _storesFuture;
