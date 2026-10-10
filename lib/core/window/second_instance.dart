import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/mini/boss_hide_controller.dart';

const _channel = MethodChannel('utaneko/second_instance');

/// 二次启动：原生 PostMessage → 此处走完整 reveal（清老板键隐藏态）。
void bindSecondInstanceActivation(WidgetRef ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'activate') {
      await ref.read(bossHideProvider.notifier).reveal();
    }
  });
}
