import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static const String defaultFontFamily = 'MiSans';

  static const List<String> _fontFamilyFallback = [
    'MiSans',
    'HarmonyOS Sans SC',
    'HarmonyOS Sans',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static const List<FontFeature> _defaultFontFeatures = [
    FontFeature.tabularFigures(),
  ];

  /// 构建适配中文阅读节奏与等宽数字对齐的全局 TextTheme
  static TextTheme _buildHarmoniousTextTheme(Brightness brightness, Color primaryColor, Color secondaryColor) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true).textTheme
        : ThemeData.light(useMaterial3: true).textTheme;

    TextStyle harmonize(TextStyle? style, {double height = 1.42, double letterSpacing = 0.2, Color? color}) {
      return (style ?? const TextStyle()).copyWith(
        fontFamily: defaultFontFamily,
        fontFamilyFallback: _fontFamilyFallback,
        fontFeatures: _defaultFontFeatures,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
    }

    return base.copyWith(
      displayLarge: harmonize(base.displayLarge, height: 1.25, letterSpacing: 0.0, color: primaryColor),
      displayMedium: harmonize(base.displayMedium, height: 1.25, letterSpacing: 0.0, color: primaryColor),
      displaySmall: harmonize(base.displaySmall, height: 1.28, letterSpacing: 0.1, color: primaryColor),
      headlineLarge: harmonize(base.headlineLarge, height: 1.3, letterSpacing: 0.1, color: primaryColor),
      headlineMedium: harmonize(base.headlineMedium, height: 1.3, letterSpacing: 0.15, color: primaryColor),
      headlineSmall: harmonize(base.headlineSmall, height: 1.32, letterSpacing: 0.15, color: primaryColor),
      titleLarge: harmonize(base.titleLarge, height: 1.35, letterSpacing: 0.2, color: primaryColor),
      titleMedium: harmonize(base.titleMedium, height: 1.38, letterSpacing: 0.2, color: primaryColor),
      titleSmall: harmonize(base.titleSmall, height: 1.38, letterSpacing: 0.2, color: primaryColor),
      bodyLarge: harmonize(base.bodyLarge, height: 1.45, letterSpacing: 0.2, color: primaryColor),
      bodyMedium: harmonize(base.bodyMedium, height: 1.42, letterSpacing: 0.2, color: primaryColor),
      bodySmall: harmonize(base.bodySmall, height: 1.4, letterSpacing: 0.15, color: secondaryColor),
      labelLarge: harmonize(base.labelLarge, height: 1.35, letterSpacing: 0.25, color: primaryColor),
      labelMedium: harmonize(base.labelMedium, height: 1.35, letterSpacing: 0.2, color: secondaryColor),
      labelSmall: harmonize(base.labelSmall, height: 1.32, letterSpacing: 0.2, color: secondaryColor),
    );
  }

  static ThemeData get darkTheme {
    final textTheme = _buildHarmoniousTextTheme(Brightness.dark, Colors.white, Colors.white70);

    return ThemeData(
      useMaterial3: true,
      fontFamily: defaultFontFamily,
      fontFamilyFallback: _fontFamilyFallback,
      brightness: Brightness.dark,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        brightness: Brightness.dark,
        primary: AppColors.primaryBlue,
        secondary: AppColors.accentCyan,
        surface: AppColors.darkSurface,
        surfaceContainerHighest: const Color(0xFF252A36),
        onSurface: Colors.white,
        outline: AppColors.darkBorder,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      dividerColor: AppColors.darkBorder,
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontFeatures: _defaultFontFeatures,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.primaryBlue,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        dividerColor: AppColors.darkBorder,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primaryBlue,
        selectedIconTheme: IconThemeData(color: Colors.white),
        unselectedIconTheme: IconThemeData(color: Colors.white54),
        selectedLabelTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          color: Colors.white54,
          letterSpacing: 0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primaryBlue,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: Colors.white54);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: defaultFontFamily,
              fontFamilyFallback: _fontFamilyFallback,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.2,
            );
          }
          return const TextStyle(
            fontFamily: defaultFontFamily,
            fontFamilyFallback: _fontFamilyFallback,
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 0.2,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontFeatures: _defaultFontFeatures,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontFeatures: _defaultFontFeatures,
          fontSize: 14,
          height: 1.45,
          letterSpacing: 0.2,
          color: Colors.white70,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          color: Colors.white,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final textTheme = _buildHarmoniousTextTheme(
      Brightness.light,
      AppColors.lightTitle,
      AppColors.lightSubtext,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: defaultFontFamily,
      fontFamilyFallback: _fontFamilyFallback,
      brightness: Brightness.light,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        brightness: Brightness.light,
        primary: AppColors.primaryBlue,
        secondary: AppColors.primaryBlueDark,
        surface: AppColors.lightSurface,
        surfaceContainerHighest: AppColors.lightElevated,
        onSurface: AppColors.lightTitle,
        outline: AppColors.lightBorder,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,
      dividerColor: AppColors.lightBorder,
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.lightTitle,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.lightTitle),
        titleTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontFeatures: _defaultFontFeatures,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppColors.lightTitle,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.primaryBlue,
        labelColor: AppColors.primaryBlueDark,
        unselectedLabelColor: AppColors.lightSubtext,
        dividerColor: AppColors.lightBorder,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: Color(0x1F0288D1),
        selectedIconTheme: IconThemeData(color: AppColors.primaryBlue),
        unselectedIconTheme: IconThemeData(color: AppColors.lightSubtext),
        selectedLabelTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          color: AppColors.primaryBlue,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          color: AppColors.lightSubtext,
          letterSpacing: 0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: const Color(0x1F0288D1),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primaryBlue);
          }
          return const IconThemeData(color: AppColors.lightSubtext);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: defaultFontFamily,
              fontFamilyFallback: _fontFamilyFallback,
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.2,
            );
          }
          return const TextStyle(
            fontFamily: defaultFontFamily,
            fontFamilyFallback: _fontFamilyFallback,
            color: AppColors.lightSubtext,
            fontSize: 12,
            letterSpacing: 0.2,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontFeatures: _defaultFontFeatures,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: AppColors.lightTitle,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontFeatures: _defaultFontFeatures,
          fontSize: 14,
          height: 1.45,
          letterSpacing: 0.2,
          color: AppColors.lightSubtext,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          color: AppColors.lightTitle,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          fontFamilyFallback: _fontFamilyFallback,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

extension ThemeContextExt on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get subtextColor => isDark ? Colors.white54 : AppColors.lightSubtext;
  Color get tertiaryTextColor => isDark ? Colors.white38 : const Color(0xFF64748B);
  Color get customCardColor => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get customBorderColor => isDark ? Colors.white.withOpacity(0.06) : AppColors.lightBorder;
}
