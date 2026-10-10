import 'package:flutter/material.dart';

/// 用户主题偏好（持久化字符串，不存整份 ThemeData）。
enum ThemeModePreference {
  light,
  dark,
  system;

  static const storageKey = 'utaneko:theme_mode';

  ThemeMode get themeMode => switch (this) {
        ThemeModePreference.light => ThemeMode.light,
        ThemeModePreference.dark => ThemeMode.dark,
        ThemeModePreference.system => ThemeMode.system,
      };

  static ThemeModePreference fromStorage(String? raw) {
    return switch (raw) {
      'light' => ThemeModePreference.light,
      'dark' => ThemeModePreference.dark,
      _ => ThemeModePreference.system,
    };
  }

  String get storageValue => name;
}
