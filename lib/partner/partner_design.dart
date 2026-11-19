import 'package:flutter/material.dart';

/// Shared with dashboard globals.css, PartnerHome and BottomNav.
/// Scoped to partner routes so the consumer app keeps its own theme.
abstract final class PartnerDesign {
  static const navy = Color(0xFF050072);
  static const periwinkle = Color(0xFF6366E0);
  static const background = Color(0xFFF4F4F9);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const tint = Color(0xFFF0F0F8);
  static const green = Color(0xFF047857);
  static const amber = Color(0xFF92400E);
  static const red = Color(0xFFDC2626);
  static const gradient = LinearGradient(colors: [navy, periwinkle]);

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(seedColor: navy).copyWith(
        primary: navy,
        secondary: periwinkle,
        surface: Colors.white,
        onSurface: ink,
      ),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: border),
    );
    return base.copyWith(
      textTheme:
          base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
                bodyMedium: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    height: 1.55,
                    color: ink),
                bodySmall: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    height: 1.5,
                    color: muted),
                titleMedium: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ink),
              ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(fontSize: 13, color: muted),
        counterStyle: const TextStyle(fontSize: 11, color: muted),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
            borderSide: const BorderSide(color: periwinkle, width: 1.5)),
        disabledBorder: fieldBorder,
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        side: const BorderSide(color: border),
        minimumSize: const Size(48, 44),
        shape: const StadiumBorder(),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        foregroundColor: navy,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 12,
            fontWeight: FontWeight.w600),
      )),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        iconColor: navy,
        titleTextStyle: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink),
        subtitleTextStyle: TextStyle(
            fontFamily: 'Pretendard', fontSize: 12, height: 1.5, color: muted),
      ),
      dividerTheme:
          const DividerThemeData(color: border, thickness: 1, space: 24),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: periwinkle, linearTrackColor: tint),
    );
  }
}

class PartnerPanel extends StatelessWidget {
  const PartnerPanel(
      {super.key,
      required this.child,
      this.color = Colors.white,
      this.gradient,
      this.borderColor = PartnerDesign.border,
      this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final Color color, borderColor;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A101828), offset: Offset(0, 1), blurRadius: 2)
          ],
        ),
        child: child,
      );
}

class PartnerBadge extends StatelessWidget {
  const PartnerBadge(this.label,
      {super.key,
      this.color = PartnerDesign.navy,
      this.background = PartnerDesign.tint});
  final String label;
  final Color color, background;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(30)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: color)),
      );
}

class PartnerEmpty extends StatelessWidget {
  const PartnerEmpty(this.message,
      {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: PartnerDesign.tint, shape: BoxShape.circle),
              child: Icon(icon, color: PartnerDesign.periwinkle, size: 22)),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class PartnerNavigation extends StatelessWidget {
  const PartnerNavigation(
      {super.key, required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int>? onSelected;
  static const labels = ['홈', '매장', '혜택', '콘텐츠', '리포트', '플랜'];
  static const icons = [
    Icons.home_outlined,
    Icons.storefront_outlined,
    Icons.card_giftcard_outlined,
    Icons.photo_library_outlined,
    Icons.description_outlined,
    Icons.receipt_long_outlined
  ];
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: PartnerDesign.border))),
        child: SafeArea(
            top: false,
            child: LayoutBuilder(builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
              final width =
                  (box.maxWidth / 6).clamp(62.0 * scale, 100.0 * scale);
              return Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width * 6),
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width * 6,
                            child: Row(
                                children: List.generate(
                                    6,
                                    (i) => Expanded(
                                            child: Semantics(
                                          selected: i == selected,
                                          button: true,
                                          child: InkWell(
                                            onTap: onSelected == null
                                                ? null
                                                : () => onSelected!(i),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 9),
                                                child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      AnimatedContainer(
                                                          duration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      180),
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 9,
                                                                  vertical: 4),
                                                          decoration: BoxDecoration(
                                                              color: i ==
                                                                      selected
                                                                  ? PartnerDesign
                                                                      .navy
                                                                  : Colors
                                                                      .transparent,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          9)),
                                                          child: Icon(icons[i],
                                                              size: 20,
                                                              color: i ==
                                                                      selected
                                                                  ? Colors.white
                                                                  : PartnerDesign
                                                                      .muted)),
                                                      const SizedBox(height: 4),
                                                      Text(labels[i],
                                                          style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: i ==
                                                                      selected
                                                                  ? PartnerDesign
                                                                      .navy
                                                                  : PartnerDesign
                                                                      .muted)),
                                                    ])),
                                          ),
                                        )))),
                          ))));
            })),
      );
}
