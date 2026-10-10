import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';
import 'theme_preference.dart';

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeModePreference>(ThemeController.new);

/// 读/写主题偏好；切换后立即持久化并触发 MaterialApp 重建。
class ThemeController extends Notifier<ThemeModePreference> {
  @override
  ThemeModePreference build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(
          ThemeModePreference.storageKey,
        );
    return ThemeModePreference.fromStorage(raw);
  }

  Future<void> setPreference(ThemeModePreference preference) async {
    state = preference;
    await ref.read(sharedPreferencesProvider).setString(
          ThemeModePreference.storageKey,
          preference.storageValue,
        );
  }

  /// 在 light ↔ dark 间翻转；若当前为 system，则落到与当前亮度相反的一极。
  Future<void> toggleLightDark(Brightness platformBrightness) async {
    final next = switch (state) {
      ThemeModePreference.light => ThemeModePreference.dark,
      ThemeModePreference.dark => ThemeModePreference.light,
      ThemeModePreference.system => platformBrightness == Brightness.dark
          ? ThemeModePreference.light
          : ThemeModePreference.dark,
    };
    await setPreference(next);
  }
}
