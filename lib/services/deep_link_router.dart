import 'package:flutter/material.dart';

import 'package:new1/favorite_restaurants_screen.dart';
import 'package:new1/featured/featured_campaign_screen.dart';
import 'package:new1/login_screen.dart';
import 'package:new1/mileage/mileage_shop_screen.dart';
import 'package:new1/mileage/my_raffle_entries_screen.dart';
import 'package:new1/mileage/raffle_terms_screen.dart';
import 'package:new1/mileage/raffle_winners_screen.dart';
import 'package:new1/mission/invite_friend.dart';
import 'package:new1/mission/mission_track_screen.dart';
import 'package:new1/profile_setup_screen.dart';
import 'package:new1/services/deep_link_service.dart';
import 'package:new1/services/promotion_service.dart';
import 'package:new1/services/user_service.dart';

/// MainAppScreen 위에서 딥링크 목적 화면을 연다.
class DeepLinkRouter {
  DeepLinkRouter._();

  static Future<void> open(BuildContext context, DeepLinkTarget target) async {
    if (!target.pushesRoute) return;
    if (!context.mounted) return;

    switch (target.screen) {
      case DeepLinkScreen.featured:
        await _openFeatured(context, target.campaignCode);
        return;
      case DeepLinkScreen.mission:
        _push(context, const MissionTrackScreen(entry: 'deeplink'));
        return;
      case DeepLinkScreen.invite:
        _push(context, const InviteFriendScreen());
        return;
      case DeepLinkScreen.shop:
        _push(context, const MileageShopScreen());
        return;
      case DeepLinkScreen.raffleEntries:
        _push(context, const MyRaffleEntriesScreen());
        return;
      case DeepLinkScreen.raffleWinners:
        _push(context, const RaffleWinnersScreen());
        return;
      case DeepLinkScreen.raffleTerms:
        _push(context, const RaffleTermsScreen());
        return;
      case DeepLinkScreen.favorites:
        _push(context, const FavoriteRestaurantsScreen());
        return;
      case DeepLinkScreen.profile:
        await _openProfile(context);
        return;
      case DeepLinkScreen.login:
        if (!context.mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        );
        return;
      case DeepLinkScreen.home:
      case DeepLinkScreen.restaurants:
      case DeepLinkScreen.restaurantDetail:
      case DeepLinkScreen.wallet:
      case DeepLinkScreen.my:
        return;
    }
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  static Future<void> _openFeatured(BuildContext context, String? code) async {
    final campaigns = await PromotionService.fetchCurrentFeatured();
    if (!context.mounted) return;
    FeaturedCampaign? campaign;
    if (code != null && code.isNotEmpty) {
      for (final item in campaigns) {
        if (item.code.toLowerCase() == code.toLowerCase()) {
          campaign = item;
          break;
        }
      }
    }
    campaign ??= campaigns.isEmpty ? null : campaigns.first;
    if (campaign == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('진행 중인 기획전이 없어요.')),
      );
      return;
    }
    _push(context, FeaturedCampaignScreen(campaign: campaign));
  }

  static Future<void> _openProfile(BuildContext context) async {
    try {
      final profile = await UserService.fetchCurrentUserProfile();
      if (!context.mounted) return;
      _push(
        context,
        ProfileSetupScreen(
          initialProfile: profile,
          isRequiredFlow: false,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필을 불러오지 못했어요.')),
      );
    }
  }
}
