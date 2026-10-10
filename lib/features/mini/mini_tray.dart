import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

const trayIconAsset = 'assets/icon/app_icon.ico';

/// 系统托盘：Mini / 老板键隐藏共用。
class MiniTray {
  MiniTray._();

  static Future<void> Function()? _onActivate;

  static Future<void> show({
    required Future<void> Function() onActivate,
    String toolTip = 'UtaNeko',
    String activateLabel = '显示窗口',
  }) async {
    _onActivate = onActivate;
    trayManager.removeListener(_listener);
    trayManager.addListener(_listener);
    try {
      await trayManager.setIcon(trayIconAsset);
      await trayManager.setToolTip(toolTip);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'activate', label: activateLabel),
            MenuItem.separator(),
            MenuItem(key: 'exit_app', label: '退出'),
          ],
        ),
      );
    } catch (e) {
      trayManager.removeListener(_listener);
      _onActivate = null;
      rethrow;
    }
  }

  static Future<void> hide() async {
    trayManager.removeListener(_listener);
    _onActivate = null;
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  static final _listener = _MiniTrayListener();
}

class _MiniTrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    final cb = MiniTray._onActivate;
    if (cb != null) {
      cb();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'activate':
      case 'show_main': // 兼容旧菜单 key
        final cb = MiniTray._onActivate;
        if (cb != null) {
          cb();
        }
      case 'exit_app':
        windowManager.destroy().whenComplete(() => exit(0));
    }
  }
}
