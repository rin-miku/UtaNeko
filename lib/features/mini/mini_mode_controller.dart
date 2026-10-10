import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import '../../core/storage/lyric_scale.dart';
import '../../core/storage/prefs.dart';
import '../../core/window/app_window_chrome.dart';
import '../../core/window/window_aspect.dart';
import 'mini_tray.dart';

const _miniXKey = 'utaneko:mini_x';
const _miniYKey = 'utaneko:mini_y';
const _miniWKey = 'utaneko:mini_w';
const _miniHKey = 'utaneko:mini_h';

const miniDefaultWidth = 420.0;
const miniDefaultHeight = 88.0;

/// Mini 内容区上下留白（与 [MiniLyricPage] 内 padding 一致）。
const miniVerticalPadding = 6.0;

/// 按歌词字号换算 Mini 高度：上下 padding 固定，只放大内容区。
double miniHeightForScale(double scale) {
  final s = scale.clamp(lyricScaleMin, lyricScaleMax);
  const pad = miniVerticalPadding * 2;
  // 100% 时总高仍约等于 [miniDefaultHeight]（旧版上下各 8px）。
  const contentAt1x = miniDefaultHeight - 16.0;
  return (pad + contentAt1x * s).clamp(56.0, 400.0);
}

bool get supportsMiniMode =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

final miniModeProvider =
    NotifierProvider<MiniModeNotifier, bool>(MiniModeNotifier.new);

class MiniModeNotifier extends Notifier<bool> {
  Rect? _normalBounds;
  var _openingMain = false;

  @override
  bool build() => false;

  Future<void> enterMini() async {
    if (!supportsMiniMode || state) return;

    try {
      _normalBounds = await windowManager.getBounds();
      await setWindowAspectRatioLocked(false);

      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setAsFrameless();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setMinimumSize(const Size(200, 56));

      // Mini：不占任务栏，改由托盘入口（依赖 main 里 waitUntilReadyToShow）。
      await windowManager.setSkipTaskbar(true);
      await MiniTray.show(
        onActivate: openMainFromTray,
        toolTip: 'UtaNeko · Mini',
        activateLabel: '打开主界面',
      );

      final prefs = ref.read(sharedPreferencesProvider);
      // 宽度沿用用户拖过的值；高度按当前歌词字号套一次。
      final w = prefs.getDouble(_miniWKey) ?? miniDefaultWidth;
      final h = miniHeightForScale(ref.read(lyricScaleProvider));
      final x = prefs.getDouble(_miniXKey);
      final y = prefs.getDouble(_miniYKey);

      final size = Size(w.clamp(200, 2000), h);
      if (x != null && y != null) {
        await windowManager.setBounds(
          Rect.fromLTWH(x, y, size.width, size.height),
        );
      } else {
        await windowManager.setSize(size);
        await windowManager.center();
      }

      state = true;
    } catch (e, st) {
      debugPrint('enterMini failed: $e\n$st');
      // 尽量回到可交互状态，避免卡在半截 Mini。
      try {
        await MiniTray.hide();
        await windowManager.setSkipTaskbar(false);
        await windowManager.setAlwaysOnTop(false);
        await applyMainWindowChrome();
        await setWindowAspectRatioLocked(true);
        if (_normalBounds != null) {
          await windowManager.setBounds(_normalBounds!);
        }
        await windowManager.show();
      } catch (_) {}
      rethrow;
    }
  }

  /// 托盘「打开主界面」/ 左键托盘。
  Future<void> openMainFromTray() async {
    if (_openingMain || !state) return;
    _openingMain = true;
    try {
      await exitMini();
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ctx.go('/');
      }
    } finally {
      _openingMain = false;
    }
  }

  /// 全局快捷键：在主窗 / Mini 之间切换（含路由）。
  Future<void> toggleMini() async {
    if (!supportsMiniMode) return;
    if (state) {
      await openMainFromTray();
      return;
    }
    try {
      await enterMini();
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ctx.go('/mini');
      }
    } catch (_) {}
  }

  Future<void> exitMini() async {
    if (!supportsMiniMode || !state) return;

    await _persistMiniBounds();
    await MiniTray.hide();

    await windowManager.setSkipTaskbar(false);
    await windowManager.setAlwaysOnTop(false);
    // 退出无边框：恢复主窗自绘标题栏（原生栏仍隐藏）。
    await applyMainWindowChrome();
    await setWindowAspectRatioLocked(true);

    await windowManager.setMinimumSize(const Size(360, 640));

    final restore = _normalBounds ??
        const Rect.fromLTWH(80, 80, 540, 960);
    await windowManager.setBounds(restore);
    _normalBounds = null;

    await windowManager.show();
    await windowManager.focus();

    state = false;
  }

  Future<void> persistMiniBoundsIfNeeded() async {
    if (!state) return;
    await _persistMiniBounds();
  }

  Future<void> _persistMiniBounds() async {
    try {
      final bounds = await windowManager.getBounds();
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setDouble(_miniXKey, bounds.left);
      await prefs.setDouble(_miniYKey, bounds.top);
      await prefs.setDouble(_miniWKey, bounds.width);
      await prefs.setDouble(_miniHKey, bounds.height);
    } catch (_) {}
  }
}
