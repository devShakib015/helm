import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// The single dark theme for Helm. The scaffold background is transparent so
/// the window's gradient + macOS vibrancy show through every screen.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.textOnAccent,
      secondary: AppColors.accentAlt,
      surface: AppColors.scaffold,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppType.fontFamily,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: AppColors.stroke,
      visualDensity: VisualDensity.compact,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamily: AppType.fontFamily,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: Color(0xF21A1F2B),
          borderRadius: BorderRadius.all(Radius.circular(7)),
        ),
        textStyle: TextStyle(
          fontFamily: AppType.fontFamily,
          fontSize: 11.5,
          color: AppColors.textPrimary,
        ),
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0x33FFFFFF)),
        thickness: WidgetStateProperty.all(7),
        radius: const Radius.circular(8),
        crossAxisMargin: 2,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 18),
    );
  }
}
