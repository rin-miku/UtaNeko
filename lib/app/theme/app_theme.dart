import 'package:flutter/material.dart';

import 'app_colors.dart';

/// MD3 双套 ThemeData；始终同时挂到 MaterialApp，只改 themeMode 切换。
abstract final class AppTheme {
  static const _seed = Color(0xFF7AA2FF);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        scheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
          surface: const Color(0xFFF4F5F8),
        ),
        colors: AppColors.light,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF0F1117),
        ),
        colors: AppColors.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppColors colors,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        color: colors.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
