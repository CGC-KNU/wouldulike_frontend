import 'package:flutter/material.dart';

/// 지갑 마일리지 탭 (M1: 오픈 전 안내만 표시, 실데이터는 M3에서 연동)
class MileageTab extends StatelessWidget {
  const MileageTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.savings_outlined,
                  size: 48,
                  color: Color(0xFF312E81),
                ),
                SizedBox(height: 12),
                Text(
                  '마일리지 기능을 준비 중이에요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF39393E),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '방문 적립과 마일리지 상점이 곧 열려요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Pretendard',
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF797979),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
