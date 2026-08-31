import 'package:flutter/material.dart';

import 'affiliate_benefits_screen.dart';

/// 마이페이지의 '찜한 식당 모아보기'.
/// 식당 탭(AffiliateBenefitsScreen)과 동일한 UI·기능을 그대로 쓰되,
/// 뒤로가기 있는 화면으로 감싸고 '찜한 식당만' 필터를 고정해 둔다.
class FavoriteRestaurantsScreen extends StatelessWidget {
  const FavoriteRestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AffiliateBenefitsScreen(
      appBarTitle: '찜한 식당',
      lockFavoritesOnly: true,
    );
  }
}
