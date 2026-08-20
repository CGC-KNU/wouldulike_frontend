import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 카테고리 아이콘 줄. 식당 탭·지갑 쿠폰/스탬프가 같은 구성을 쓰도록 공용화했다.
class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    this.categories = kCategoryOrder,
  });

  final String selected;
  final ValueChanged<String> onSelect;
  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = categories[index];
          final isSelected = key == selected;
          final meta = kCategoryIcons[key] ?? kCategoryIcons['ALL']!;

          return InkWell(
            onTap: () => onSelect(key),
            borderRadius: BorderRadius.circular(30),
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF172133)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: SvgPicture.asset(
                      meta.iconPath,
                      width: 50,
                      height: 50,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    meta.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF172133)
                          : const Color(0xFF6B7280),
                      fontSize: 11.5,
                      fontFamily: 'Pretendard',
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CategoryIcon {
  const CategoryIcon(this.label, this.iconPath);

  final String label;
  final String iconPath;
}

const List<String> kCategoryOrder = [
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

const Map<String, CategoryIcon> kCategoryIcons = {
  'ALL': CategoryIcon('전체', 'assets/icons/category/all.svg'),
  'KOREAN': CategoryIcon('한식', 'assets/icons/category/korean.svg'),
  'CHINESE': CategoryIcon('중식', 'assets/icons/category/chinese.svg'),
  'JAPANESE': CategoryIcon('일식', 'assets/icons/category/japanese.svg'),
  'WESTERN': CategoryIcon('양식', 'assets/icons/category/western.svg'),
  'SNACK': CategoryIcon('분식', 'assets/icons/category/snack.svg'),
  'PUB': CategoryIcon('술집', 'assets/icons/category/pub.svg'),
  'CAFE': CategoryIcon('카페', 'assets/icons/category/cafe.svg'),
  'DONKATSU': CategoryIcon('돈가스', 'assets/icons/category/donkatsu.svg'),
  'HAMBURGER': CategoryIcon('햄버거', 'assets/icons/category/hamburger.svg'),
  'ETC': CategoryIcon('기타', 'assets/icons/category/etc.svg'),
};

const Map<String, String> _kAlias = {
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
};

/// 서버가 주는 한글/영문 카테고리를 아이콘 키로 정규화한다.
String normalizeCategoryKey(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'ETC';
  final upper = trimmed.toUpperCase();
  if (kCategoryIcons.containsKey(upper)) return upper;
  return _kAlias[trimmed] ?? _kAlias[upper] ?? 'ETC';
}
