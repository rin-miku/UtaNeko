import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 主窗口使用自绘标题栏（隐藏原生栏）。
bool get supportsCustomWindowChrome =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// 主窗口 chrome：隐藏原生标题栏、禁用最大化（保持 9:16 比例锁）。
Future<void> applyMainWindowChrome() async {
  if (!supportsCustomWindowChrome) return;
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.setMaximizable(false);
  // 若已被双击等路径最大化，立刻还原，避免 hidden 标题栏下顶栏变灰、按钮被盖住。
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  }
}

/// 自绘标题栏：可拖拽；仅最小化 / 关闭。
///
/// 不用 [DragToMoveArea]：它会在双击时 maximize，与「禁止最大化」冲突，
/// 且 maximize + TitleBarStyle.hidden 在 Windows 上常导致顶栏灰条、按钮不可见。
class AppWindowTitleBar extends StatelessWidget {
  const AppWindowTitleBar({super.key});

  static const double height = 40;

  Future<void> _closeApp() async {
    await windowManager.destroy();
    exit(0);
  }

  Future<void> _minimize() async {
    final minimized = await windowManager.isMinimized();
    if (minimized) {
      await windowManager.restore();
    } else {
      await windowManager.minimize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: _WindowDragArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/icon/icon-utaneko-1024.png',
                        width: 28,
                        height: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'UtaNeko',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            WindowCaptionButton.minimize(
              brightness: brightness,
              onPressed: _minimize,
            ),
            WindowCaptionButton.close(
              brightness: brightness,
              onPressed: _closeApp,
            ),
          ],
        ),
      ),
    );
  }
}

/// 仅拖拽移动窗口；显式不处理双击，避免最大化。
class _WindowDragArea extends StatelessWidget {
  const _WindowDragArea({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      child: child ?? const SizedBox.expand(),
    );
  }
}
