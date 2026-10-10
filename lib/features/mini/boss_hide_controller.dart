import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'mini_mode_controller.dart';
import 'mini_tray.dart';

/// 老板键隐藏态：窗口藏起，托盘可唤回，播放不中断。
final bossHideProvider =
    NotifierProvider<BossHideNotifier, bool>(BossHideNotifier.new);

class BossHideNotifier extends Notifier<bool> {
  /// 隐藏前所在是否为 Mini（用于显示时原样恢复）。
  var _wasInMini = false;
  var _busy = false;

  @override
  bool build() => false;

  bool get wasInMiniWhenHidden => _wasInMini;

  Future<void> hideToTray() async {
    if (!supportsMiniMode || _busy) return;
    if (state) return; // 已隐藏

    _busy = true;
    try {
      final inMini = ref.read(miniModeProvider);
      _wasInMini = inMini;

      if (inMini) {
        // Mini 已有托盘：只藏窗，并把托盘动作改成「显示」。
        await MiniTray.show(
          onActivate: showFromTray,
          toolTip: 'UtaNeko · 已隐藏',
          activateLabel: '显示窗口',
        );
      } else {
        await windowManager.setSkipTaskbar(true);
        await MiniTray.show(
          onActivate: showFromTray,
          toolTip: 'UtaNeko · 已隐藏',
          activateLabel: '显示窗口',
        );
      }

      await windowManager.hide();
      state = true;
    } catch (e, st) {
      debugPrint('boss hide failed: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  Future<void> showFromTray() => reveal();

  Future<void> reveal() async {
    if (!supportsMiniMode || _busy) return;
    if (!state) {
      // 未处于老板键隐藏时，仅确保窗口可见。
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
      return;
    }

    _busy = true;
    try {
      await windowManager.show();
      await windowManager.focus();

      if (_wasInMini) {
        // 回到 Mini：托盘改回「打开主界面」。
        await MiniTray.show(
          onActivate: () =>
              ref.read(miniModeProvider.notifier).openMainFromTray(),
          toolTip: 'UtaNeko · Mini',
          activateLabel: '打开主界面',
        );
      } else {
        await MiniTray.hide();
        await windowManager.setSkipTaskbar(false);
      }

      state = false;
      _wasInMini = false;
    } catch (e, st) {
      debugPrint('boss reveal failed: $e\n$st');
    } finally {
      _busy = false;
    }
  }
}
