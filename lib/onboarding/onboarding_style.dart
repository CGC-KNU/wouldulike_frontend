import 'package:flutter/material.dart';

/// 온보딩 화면 공용 스타일 — 앱 기존 인디고 팔레트를 그대로 사용한다.
class OnboardingStyle {
  OnboardingStyle._();

  static const Color primary = Color(0xFF312E81);
  static const Color accent = Color(0xFF6366F1);
  static const Color accentSoft = Color(0xFFEEF4FF);
  static const Color ink = Color(0xFF111827);
  static const Color body = Color(0xFF4B5563);
  static const Color muted = Color(0xFF9CA3AF);
  static const Color line = Color(0xFFE5E7EB);
  static const Color danger = Color(0xFFE11D48);

  static ButtonStyle primaryButton({bool enabled = true}) {
    return ElevatedButton.styleFrom(
      backgroundColor: enabled ? primary : const Color(0xFFC7D2FE),
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFC7D2FE),
      disabledForegroundColor: Colors.white,
      minimumSize: const Size.fromHeight(54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      textStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  static const TextStyle title = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.35,
    letterSpacing: -0.5,
    color: ink,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.55,
    color: body,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'Pretendard',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: muted,
  );
}
