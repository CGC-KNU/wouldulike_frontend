import 'package:flutter/material.dart';
import 'package:new1/models/coupon_benefits_summary.dart';
import 'package:new1/services/coupon_service.dart';

/// 식당 상세 — `coupon_benefits_summary` 펼침 본문
class RestaurantCouponBenefitsContent extends StatelessWidget {
  const RestaurantCouponBenefitsContent({
    super.key,
    required this.summary,
  });

  final CouponBenefitsSummary summary;

  static const _sectionTitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Color(0xFF1F2937),
  );

  static const _itemTitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF374151),
    height: 1.35,
  );

  static const _itemSubtitleStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF6B7280),
    height: 1.35,
  );

  static const _bodyStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF4B5563),
    height: 1.45,
  );

  static const _footnoteStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Color(0xFF9CA3AF),
    height: 1.4,
  );

  static const _stepLabelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111439),
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (summary.signup.shouldDisplay) {
      children.add(
        _buildCouponTypeSection(
          title: '신규가입 혜택',
          section: summary.signup,
          footnote: '가입 시 이 식당 쿠폰이 당첨될 수 있는 혜택이에요',
        ),
      );
    }

    for (final referralSection in _buildReferralSections()) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 14));
      }
      children.add(referralSection);
    }

    if (summary.stamp.hasRewardList || summary.stamp.hasNotesOnly) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 14));
      }
      children.add(_buildStampSection(summary.stamp));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  List<Widget> _buildReferralSections() {
    final referrer = summary.referral.referrer;
    final referee = summary.referral.referee;
    final referrerVisible = referrer.shouldDisplay;
    final refereeVisible = referee.shouldDisplay;

    if (!referrerVisible && !refereeVisible) {
      return const [];
    }

    if (referrerVisible &&
        refereeVisible &&
        CouponBenefitsSummary.itemsEqual(referrer.items, referee.items)) {
      return [
        _buildCouponTypeSection(
          title: '친구초대 혜택',
          section: referrer,
          footnote: '친구 초대 시 이 식당 쿠폰이 당첨될 수 있는 혜택이에요',
        ),
      ];
    }

    final widgets = <Widget>[];
    if (referrerVisible) {
      widgets.add(
        _buildCouponTypeSection(
          title: '친구초대 · 추천인',
          section: referrer,
          footnote: '친구 초대 시 추천인에게 당첨될 수 있는 혜택이에요',
        ),
      );
    }
    if (refereeVisible) {
      widgets.add(
        _buildCouponTypeSection(
          title: '친구초대 · 피추천인',
          section: referee,
          footnote: '친구 초대 시 피추천인에게 당첨될 수 있는 혜택이에요',
        ),
      );
    }
    return widgets;
  }

  Widget _buildCouponTypeSection({
    required String title,
    required CouponTypeSection section,
    String? footnote,
  }) {
    return _buildSection(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...section.items.map(_buildBenefitItem),
          if (footnote != null && footnote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(footnote, style: _footnoteStyle),
          ],
        ],
      ),
    );
  }

  Widget _buildStampSection(CouponBenefitsStampSection stamp) {
    final sortedRewards = List<StampReward>.from(stamp.rewards);
    sortedRewards.sort((a, b) {
      final aKey = a.stamps ?? a.minVisit ?? 0;
      final bKey = b.stamps ?? b.minVisit ?? 0;
      return aKey.compareTo(bKey);
    });

    return _buildSection(
      title: '스탬프 혜택',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stamp.notes.trim().isNotEmpty) ...[
            Text(stamp.notes.trim(), style: _bodyStyle),
            if (stamp.hasRewardList) const SizedBox(height: 8),
          ],
          if (stamp.hasRewardList) ...[
            ...sortedRewards.map(
              (reward) => _buildStampRewardItem(reward, stamp.ruleType),
            ),
            const SizedBox(height: 6),
            const Text(
              '해당 식당에서 PIN 적립 시 단계별로 발급돼요',
              style: _footnoteStyle,
            ),
          ] else if (!stamp.enabled) ...[
            const Text(
              '이 식당은 스탬프 적립을 운영하지 않아요',
              style: _footnoteStyle,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: _sectionTitleStyle),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildBenefitItem(CouponBenefitItem item) {
    final benefitText =
        CouponBenefitsSummaryFormat.formatBenefitValue(item.benefit);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.title.trim().isNotEmpty)
            Text(item.title.trim(), style: _itemTitleStyle),
          if (item.subtitle.trim().isNotEmpty) ...[
            if (item.title.trim().isNotEmpty) const SizedBox(height: 2),
            Text(item.subtitle.trim(), style: _itemSubtitleStyle),
          ],
          if (benefitText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(benefitText, style: _bodyStyle),
          ],
          if (item.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.notes.trim(), style: _bodyStyle),
          ],
        ],
      ),
    );
  }

  Widget _buildStampRewardItem(StampReward reward, String? ruleType) {
    final stepLabel =
        CouponBenefitsSummaryFormat.stampRewardStepLabel(reward, ruleType);
    final title = CouponBenefitsSummaryFormat.rewardDisplayTitle(reward);
    final benefitMap = reward.benefit is Map<String, dynamic>
        ? reward.benefit as Map<String, dynamic>
        : reward.benefit is Map
            ? Map<String, dynamic>.from(reward.benefit as Map)
            : <String, dynamic>{};
    final benefitText = CouponBenefitsSummaryFormat.formatBenefitValue(
      benefitMap,
    );
    final notes = reward.notes?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stepLabel.isNotEmpty)
            Text(stepLabel, style: _stepLabelStyle),
          if (stepLabel.isNotEmpty && title.isNotEmpty) const SizedBox(height: 2),
          if (title.isNotEmpty) Text(title, style: _itemTitleStyle),
          if (benefitText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(benefitText, style: _bodyStyle),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes, style: _bodyStyle),
          ],
        ],
      ),
    );
  }
}
