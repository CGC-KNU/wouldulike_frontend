import 'package:flutter/material.dart';

import '../../services/affiliate_service.dart';
import '../onboarding_style.dart';

/// 온보딩에서 재사용하는 식당 선택 리스트 (아이콘 없이 글씨만).
///
/// 로딩/에러/목록 상태를 함께 처리하며, 항목을 탭하면 [onSelect]로 인덱스를 알린다.
class RestaurantPickList extends StatelessWidget {
  const RestaurantPickList({
    super.key,
    required this.loading,
    required this.failed,
    required this.restaurants,
    required this.selectedIndex,
    required this.onSelect,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final List<AffiliateRestaurantSummary> restaurants;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: OnboardingStyle.primary),
      );
    }
    if (failed || restaurants.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('식당 목록을 불러오지 못했어요', style: OnboardingStyle.subtitle),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: restaurants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final restaurant = restaurants[index];
        final selected = selectedIndex == index;
        final meta = [restaurant.category, restaurant.zone]
            .where((s) => s.isNotEmpty)
            .join(' · ');
        return Material(
          color: selected ? OnboardingStyle.accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color:
                      selected ? OnboardingStyle.accent : OnboardingStyle.line,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? OnboardingStyle.primary
                                : OnboardingStyle.ink,
                          ),
                        ),
                        if (meta.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OnboardingStyle.caption,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: OnboardingStyle.primary,
                      size: 22,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
