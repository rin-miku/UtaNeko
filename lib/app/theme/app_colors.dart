import 'package:flutter/material.dart';

/// 业务语义色：补 ColorScheme 未覆盖的歌词 / 注音 / Mini 等 token。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.panel,
    required this.fgDim,
    required this.ruby,
    required this.lyricActive,
    required this.danger,
    required this.miniScrim,
  });

  final Color panel;
  final Color fgDim;
  final Color ruby;
  final Color lyricActive;
  final Color danger;
  final Color miniScrim;

  /// 暗色：对齐现 Web CSS token。
  static const dark = AppColors(
    panel: Color(0xFF171A23),
    fgDim: Color(0xFF9AA3B5),
    ruby: Color(0xFF8FD3A8),
    lyricActive: Color(0xFF7AA2FF),
    danger: Color(0xFFFF7A7A),
    miniScrim: Color(0xCC0F1117),
  );

  /// 亮色：同语义、保证对比度。
  static const light = AppColors(
    panel: Color(0xFFFFFFFF),
    fgDim: Color(0xFF5C6578),
    ruby: Color(0xFF2E8B57),
    lyricActive: Color(0xFF3D6FE0),
    danger: Color(0xFFD64545),
    miniScrim: Color(0xCCF4F5F8),
  );

  @override
  AppColors copyWith({
    Color? panel,
    Color? fgDim,
    Color? ruby,
    Color? lyricActive,
    Color? danger,
    Color? miniScrim,
  }) {
    return AppColors(
      panel: panel ?? this.panel,
      fgDim: fgDim ?? this.fgDim,
      ruby: ruby ?? this.ruby,
      lyricActive: lyricActive ?? this.lyricActive,
      danger: danger ?? this.danger,
      miniScrim: miniScrim ?? this.miniScrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      panel: Color.lerp(panel, other.panel, t)!,
      fgDim: Color.lerp(fgDim, other.fgDim, t)!,
      ruby: Color.lerp(ruby, other.ruby, t)!,
      lyricActive: Color.lerp(lyricActive, other.lyricActive, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      miniScrim: Color.lerp(miniScrim, other.miniScrim, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
