import 'package:flutter/material.dart';

import '../services/affiliate_service.dart';

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

/// 제휴 매장 목록 시트(이름 검색 포함). 고르면 그 매장을 돌려준다.
///
/// 매장이 20개를 넘어가면 스크롤만으로는 찾기 힘들어 검색칸을 같이 둔다.
Future<AffiliateRestaurantSummary?> pickAffiliateStore(
  BuildContext context,
) async {
  final future = _storesFuture ??= AffiliateService.fetchRestaurants();
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
                      '이 쿠폰은 제휴 매장 어디서나 쓸 수 있어요.',
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
                      final items = keyword.isEmpty
                          ? all
                          : all.where((r) => r.name.contains(keyword)).toList();
                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                            '검색 결과가 없어요.',
                            style: TextStyle(
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
                            subtitle: item.category.isEmpty
                                ? null
                                : Text(
                                    item.category,
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

/// 드롭다운을 다시 열 때마다 매장 목록을 새로 받지 않도록 앱 실행 동안 캐시한다.
/// ponytail: 프로세스 수명 캐시. 매장 정보가 자주 바뀌면 TTL을 붙일 것.
Future<List<AffiliateRestaurantSummary>>? _storesFuture;
