import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('utaneko/window_aspect');

/// 控制 Windows 原生 9:16 比例锁（Mini 时关闭）。
Future<void> setWindowAspectRatioLocked(bool locked) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  await _channel.invokeMethod<void>('setAspectRatioLocked', locked);
}
