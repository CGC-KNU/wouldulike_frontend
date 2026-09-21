import 'package:flutter/material.dart';

import '../services/master_content.dart';

/// 식사권 응모 유의사항 전문. 상점·당첨자 발표에서 함께 연결한다.
class RaffleTermsScreen extends StatelessWidget {
  const RaffleTermsScreen({super.key});

  static const _ink = Color(0xFF191F28);
  static const _sub = Color(0xFF4E5968);
  static const _faint = Color(0xFF8B95A1);
  static const _line = Color(0xFFE7E9EF);
  static const _primary = Color(0xFF4F46E5);

  @override
  Widget build(BuildContext context) {
    final sections = MasterContent.raffleSections;
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
          for (final section in sections) ...[
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

  Widget _buildSection(RaffleTermsSection section) {
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
