import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

const lyricScaleKey = 'utaneko:lyric_scale';
const lyricScaleMin = 0.8;
const lyricScaleMax = 2.0;
const lyricScaleDivisions = 12;

final lyricScaleProvider =
    NotifierProvider<LyricScaleNotifier, double>(LyricScaleNotifier.new);

/// 歌词、注音、翻译共用一个倍数。注音在绘制时仍是歌词字号的 55%。
class LyricScaleNotifier extends Notifier<double> {
  @override
  double build() {
    final raw = ref.watch(sharedPreferencesProvider).getDouble(lyricScaleKey);
    return _snap(raw ?? 1);
  }

  Future<void> setScale(double value) async {
    final next = _snap(value);
    state = next;
    await ref.read(sharedPreferencesProvider).setDouble(lyricScaleKey, next);
  }

  double _snap(double value) {
    final clamped = value.clamp(lyricScaleMin, lyricScaleMax);
    return (clamped * 10).round() / 10;
  }
}

/// 把主题字号乘上倍数。主题没写死 fontSize 时用 [fallback]。
TextStyle scaleTextStyle(TextStyle? style, double scale, {required double fallback}) {
  final base = style ?? const TextStyle();
  return base.copyWith(fontSize: (base.fontSize ?? fallback) * scale);
}
