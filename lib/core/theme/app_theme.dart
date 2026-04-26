import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // Pretendard 번들 — assets/fonts/ 에 otf 5단계 weight 포함.
  // 안드로이드 기기간 시스템 폰트 차이를 제거해 동일한 시각 인상 유지.
  static const String? _fontFamily = 'Pretendard';

  // ─── Light Theme ───
  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: AppColors.lightBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.gasBlueDark,
      brightness: Brightness.light,
      surface: AppColors.lightBg,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightBg,
      foregroundColor: AppColors.lightTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.lightTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.lightCardBorder, width: 0.5),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.lightBg,
      selectedItemColor: AppColors.gasBlueDark,
      unselectedItemColor: AppColors.lightTextMuted,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gasBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textTheme: _textTheme(Brightness.light),
    dividerTheme: const DividerThemeData(color: AppColors.lightCardBorder, thickness: 0.5),
  );

  // ─── Dark Theme ───
  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: AppColors.darkBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.gasBlue,
      brightness: Brightness.dark,
      surface: AppColors.darkBg,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBg,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF12141A),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.darkCardBorder, width: 0.5),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkBg,
      selectedItemColor: AppColors.gasBlue,
      unselectedItemColor: AppColors.darkTextMuted,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gasBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textTheme: _textTheme(Brightness.dark),
    dividerTheme: const DividerThemeData(color: AppColors.darkCardBorder, thickness: 0.5),
  );

  static TextTheme _textTheme(Brightness brightness) {
    final primary = brightness == Brightness.dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondary = brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return TextTheme(
      headlineLarge: TextStyle(fontFamily: _fontFamily, fontSize: 24, fontWeight: FontWeight.w800, color: primary),
      headlineMedium: TextStyle(fontFamily: _fontFamily, fontSize: 20, fontWeight: FontWeight.w700, color: primary),
      headlineSmall: TextStyle(fontFamily: _fontFamily, fontSize: 18, fontWeight: FontWeight.w700, color: primary),
      titleLarge: TextStyle(fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.w700, color: primary),
      titleMedium: TextStyle(fontFamily: _fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: primary),
      titleSmall: TextStyle(fontFamily: _fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: TextStyle(fontFamily: _fontFamily, fontSize: 15, fontWeight: FontWeight.w400, color: primary),
      bodyMedium: TextStyle(fontFamily: _fontFamily, fontSize: 13, fontWeight: FontWeight.w400, color: secondary),
      bodySmall: TextStyle(fontFamily: _fontFamily, fontSize: 11, fontWeight: FontWeight.w400, color: secondary),
      labelLarge: TextStyle(fontFamily: _fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      labelMedium: TextStyle(fontFamily: _fontFamily, fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
      labelSmall: TextStyle(fontFamily: _fontFamily, fontSize: 10, fontWeight: FontWeight.w500, color: secondary),
    );
  }
}
