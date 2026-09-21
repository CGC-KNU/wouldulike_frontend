import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/master_content.dart';

/// 카테고리 아이콘 줄. 식당 탭·지갑 쿠폰/스탬프가 같은 구성을 쓰도록 공용화했다.
class CategoryStrip extends StatelessWidget {
  const CategoryStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    this.categories,
  });

  final String selected;
  final ValueChanged<String> onSelect;
  final List<String>? categories;

  @override
  Widget build(BuildContext context) {
    final keys = categories ?? MasterContent.stripOrder;
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final key = keys[index];
          final isSelected = key == selected;

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
                      MasterContent.svgOf(key),
                      width: 50,
                      height: 50,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    MasterContent.labelOf(key),
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

List<String> get kCategoryOrder => MasterContent.stripOrder;

Map<String, CategoryIcon> get kCategoryIcons => {
      for (final code in MasterContent.stripOrder)
        code: CategoryIcon(
            MasterContent.labelOf(code), MasterContent.svgOf(code)),
    };

/// 서버가 주는 한글/영문 카테고리를 아이콘 키로 정규화한다.
String normalizeCategoryKey(String raw) => MasterContent.normalize(raw);
