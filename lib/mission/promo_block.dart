import 'package:flutter/material.dart';

import 'package:new1/services/mission_service.dart';

/// 홈 상단 프로모 블록. 기존 튜토리얼 블록 자리를 쓴다.
/// 운영이 켰을 때만(`PromoBlock.isVisibleAt`) 렌더링하고, 평소엔 아무것도 그리지 않는다.
/// 탭하면 검증을 통과한 https 링크만 연다.
const _deep = Color(0xFF312E81);
const _light = Color(0xFF6366F1);

class PromoBlockCard extends StatelessWidget {
  const PromoBlockCard({
    super.key,
    required this.block,
    required this.onTap,
  });

  final PromoBlock block;

  /// 링크가 없으면 null. 카드는 보이되 탭이 동작하지 않는다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 132,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _deep,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD4D7F5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1714123C),
                blurRadius: 20,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(child: _buildCopy()),
              SizedBox(width: 108, child: _buildVisual()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopy() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            block.note.isNotEmpty ? block.note : '우주라이크 혜택',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFFC9C8FF),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            block.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.45,
              height: 1.3,
              color: Colors.white,
            ),
          ),
          if (block.subtitle.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              block.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE5E4FF),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisual() {
    final fallback = Image.asset(
      'assets/images/coupon.png',
      fit: BoxFit.contain,
      width: 76,
      height: 76,
    );
    return ColoredBox(
      color: _light,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: block.imageUrl == null
                ? fallback
                : Image.network(
                    block.imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
          ),
          if (onTap != null)
            const Positioned(
              right: 9,
              bottom: 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x2EFFFFFF),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child:
                      Icon(Icons.chevron_right, size: 18, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
