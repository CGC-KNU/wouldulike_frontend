import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:new1/widgets/stamp_asset_grid.dart';

void main() {
  Future<List<String>> renderBoard(
    WidgetTester tester, {
    required int current,
    required int target,
    required Set<int> rewardSteps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StampAssetGrid(
              current: current,
              target: target,
              rewardSteps: rewardSteps,
            ),
          ),
        ),
      ),
    );

    return tester
        .widgetList<Image>(find.descendant(
          of: find.byType(StampAssetGrid),
          matching: find.byType(Image),
        ))
        .map((image) => (image.image as AssetImage).assetName)
        .toList();
  }

  testWidgets('라라더 15개 도장판은 기존 리소스로 15칸을 그린다', (tester) async {
    final assets = await renderBoard(
      tester,
      current: 6,
      target: 15,
      rewardSteps: const {15},
    );

    expect(assets, hasLength(15));
    expect(
      assets.where((asset) => asset.endsWith('stamp_filled.png')),
      hasLength(6),
    );
    expect(
      assets.where((asset) => asset.endsWith('stamp_empty.png')),
      hasLength(8),
    );
    expect(assets.last, endsWith('stamp_reward.png'));
  });

  testWidgets('라라더 20개 도장판은 기존 리소스로 20칸을 그린다', (tester) async {
    final assets = await renderBoard(
      tester,
      current: 11,
      target: 20,
      rewardSteps: const {15, 20},
    );

    expect(assets, hasLength(20));
    expect(
      assets.where((asset) => asset.endsWith('stamp_filled.png')),
      hasLength(11),
    );
    expect(
      assets.where((asset) => asset.endsWith('stamp_empty.png')),
      hasLength(7),
    );
    expect(
      assets.where((asset) => asset.endsWith('stamp_reward.png')),
      hasLength(2),
    );
  });
}
