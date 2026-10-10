import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/storage/prefs.dart';
import 'core/window/app_window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 安卓只锁竖屏，不改窗口尺寸；Windows 的 9:16 在原生窗口里处理。
  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  // just_audio 在 Windows 需通过 media_kit 后端注册；Android 仍用官方实现。
  if (defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
    // hot reload 时清掉旧全局热键，避免重复注册。
    await hotKeyManager.unregisterAll();
    await windowManager.ensureInitialized();
    // 必须调用：内部会创建 ITaskbarList3，否则 setSkipTaskbar 空指针闪退。
    await windowManager.waitUntilReadyToShow();
    // 隐藏原生标题栏，改由 Flutter 自绘（最小化 / 关闭）；禁用最大化。
    await applyMainWindowChrome();
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const UtaNekoApp(),
    ),
  );
}
