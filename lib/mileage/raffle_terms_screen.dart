import 'package:flutter/material.dart';

/// 식사권 응모 유의사항 전문. 상점·당첨자 발표에서 함께 연결한다.
/// 표시 전용 화면이라 네트워크 호출이 없다.
class RaffleTermsScreen extends StatelessWidget {
  const RaffleTermsScreen({super.key});

  static const _ink = Color(0xFF191F28);
  static const _sub = Color(0xFF4E5968);
  static const _faint = Color(0xFF8B95A1);
  static const _line = Color(0xFFE7E9EF);
  static const _primary = Color(0xFF4F46E5);

  static const _sections = <_TermsSection>[
    _TermsSection('응모 방법', [
      '마일리지는 매장 구분 없이 전 매장 공통으로 사용해요.',
      '응모하면 표시된 마일리지가 즉시 차감돼요.',
      '한 응모 건에 1인 1회만 응모할 수 있어요.',
      '보유 마일리지가 부족하면 응모할 수 없어요.',
    ]),
    _TermsSection('추첨과 발표', [
      '마감 시각이 지나면 응모자 중 무작위로 추첨해요.',
      '결과는 당첨자 발표와 내 응모에서 확인할 수 있어요.',
      '당첨되면 식사권 쿠폰이 쿠폰함으로 자동 발급돼요.',
      '당첨자 닉네임은 개인정보 보호를 위해 일부만 표시해요.',
    ]),
    _TermsSection('쿠폰 사용', [
      '식사권 쿠폰은 제휴 전 매장에서 사용할 수 있어요.',
      '쿠폰은 유효기간 안에 써야 하고, 기간이 지나면 자동으로 사라져요.',
      '현금 교환·양도·재발급은 되지 않아요.',
      '다른 할인·쿠폰과 중복 사용은 매장 정책에 따라 제한될 수 있어요.',
    ]),
    _TermsSection('꼭 확인해주세요', [
      '응모 후 취소와 마일리지 환급은 되지 않아요.',
      '미당첨이어도 차감된 마일리지는 돌려드리지 않아요.',
      '부정한 방법으로 적립한 마일리지로 응모하면 당첨이 취소될 수 있어요.',
      '운영상의 사유로 응모가 중단되면 차감된 마일리지를 돌려드려요.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _ink),
        title: const Text(
          '응모 유의사항',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: _ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          const Text(
            '식사권 응모 전에\n아래 내용을 확인해주세요',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.35,
              color: _ink,
            ),
          ),
          const SizedBox(height: 20),
          for (final section in _sections) ...[
            _buildSection(section),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          const Text(
            '본 안내는 서비스 운영 정책에 따라 변경될 수 있으며, 변경 시 앱 공지로 알려드려요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: _faint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(_TermsSection section) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < section.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF1FE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: _primary,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.items[i],
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                      height: 1.5,
                      color: _sub,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TermsSection {
  const _TermsSection(this.title, this.items);

  final String title;
  final List<String> items;
}
