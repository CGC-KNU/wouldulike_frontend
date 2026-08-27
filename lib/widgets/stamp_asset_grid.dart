import 'package:flutter/material.dart';

/// 앱 공통 스탬프 리소스를 5열 도장판으로 배치한다.
///
/// 판의 길이는 서버에서 받은 값을 그대로 사용하므로 10개뿐 아니라
/// 라라더의 15개(3줄), 20개(4줄) 도장판도 같은 디자인으로 확장된다.
class StampAssetGrid extends StatelessWidget {
  const StampAssetGrid({
    super.key,
    required this.current,
    required this.target,
    this.rewardSteps = const <int>{},
  });

  static const int columns = 5;
  static const double gap = 8;

  final int current;
  final int target;
  final Set<int> rewardSteps;

  @override
  Widget build(BuildContext context) {
    final filled = current.clamp(0, target);

    return Semantics(
      label: '스탬프 $filled개 / $target개',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < target; i++)
                SizedBox(
                  width: size,
                  height: size,
                  child: Image.asset(
                    rewardSteps.contains(i + 1) && i >= filled
                        ? 'assets/images/stamp/stamp_reward.png'
                        : (i < filled
                            ? 'assets/images/stamp/stamp_filled.png'
                            : 'assets/images/stamp/stamp_empty.png'),
                    fit: BoxFit.contain,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
