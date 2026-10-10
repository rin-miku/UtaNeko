import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/hotkey_bindings.dart';
import '../core/window/app_window_chrome.dart';
import '../core/window/second_instance.dart';
import '../features/mini/mini_mode_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class UtaNekoApp extends ConsumerStatefulWidget {
  const UtaNekoApp({super.key});

  @override
  ConsumerState<UtaNekoApp> createState() => _UtaNekoAppState();
}

class _UtaNekoAppState extends ConsumerState<UtaNekoApp> {
  @override
  void initState() {
    super.initState();
    bindSecondInstanceActivation(ref);
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(themeControllerProvider);
    final router = ref.watch(routerProvider);
    final miniMode = supportsCustomWindowChrome
        ? ref.watch(miniModeProvider)
        : false;
    // Windows：保活全局快捷键注册（不依赖是否打开设置页）。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      ref.watch(hotkeyBindingsProvider);
    }

    return MaterialApp.router(
      title: 'UtaNeko',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: preference.themeMode,
      routerConfig: router,
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final overlay = brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;
        // 主窗口套自绘标题栏；Mini 无边框页不套。
        final body = supportsCustomWindowChrome && !miniMode
            ? Column(
                children: [
                  const AppWindowTitleBar(),
                  Expanded(child: child ?? const SizedBox.shrink()),
                ],
              )
            : (child ?? const SizedBox.shrink());
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay.copyWith(
            statusBarColor: Colors.transparent,
          ),
          child: body,
        );
      },
    );
  }
}
