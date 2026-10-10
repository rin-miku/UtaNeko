import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/theme/app_colors.dart';
import '../../core/furigana/furi_ruby.dart';
import '../../core/furigana/furigana_service.dart';
import '../../core/storage/lyric_scale.dart';
import '../player/player_controller.dart';
import 'mini_mode_controller.dart' show miniModeProvider, miniVerticalPadding;

/// Windows Mini：只显示当前一句歌词 + 注音 + 翻译；双击 / 托盘可回主窗。
class MiniLyricPage extends ConsumerStatefulWidget {
  const MiniLyricPage({super.key});

  @override
  ConsumerState<MiniLyricPage> createState() => _MiniLyricPageState();
}

class _MiniLyricPageState extends ConsumerState<MiniLyricPage>
    with WindowListener {
  /// 滚轮节流，避免触控板一次滑动连跳多句。
  DateTime? _lastWheelSeekAt;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 抢占滚轮，避免被横向 SingleChildScrollView 吃掉。
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final dy = scroll.scrollDelta.dy;
      if (dy == 0) return;

      final now = DateTime.now();
      final last = _lastWheelSeekAt;
      if (last != null && now.difference(last) < const Duration(milliseconds: 80)) {
        return;
      }
      _lastWheelSeekAt = now;

      final player = ref.read(playerControllerProvider.notifier);
      // 向上滚：上一句；向下滚：下一句（与常见阅读习惯一致）。
      if (dy < 0) {
        player.seekPrevLyric();
      } else {
        player.seekNextLyric();
      }
    });
  }

  @override
  void onWindowMoved() {
    ref.read(miniModeProvider.notifier).persistMiniBoundsIfNeeded();
  }

  @override
  void onWindowResized() {
    ref.read(miniModeProvider.notifier).persistMiniBoundsIfNeeded();
  }

  Future<void> _exit() async {
    await ref.read(miniModeProvider.notifier).exitMini();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    // 监听注音结果变化，切句/分词完成后刷新。
    ref.watch(furiganaServiceProvider);
    final scale = ref.watch(lyricScaleProvider);
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;

    final idx = player.lyricIndex;
    final hasLine = idx >= 0 && idx < player.lines.length;
    final line = hasLine ? player.lines[idx] : null;
    final tokens = hasLine
        ? ref.read(furiganaServiceProvider.notifier).tokensForLines(
              player.lines.length,
            )[idx]
        : null;

    final baseStyle = scaleTextStyle(
      Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.lyricActive,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
      scale,
      fallback: 16,
    );
    final transStyle = scaleTextStyle(
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.fgDim,
            height: 1.2,
          ),
      scale,
      fallback: 12,
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      // Stack 顶层 Listener 优先命中滚轮，避免被横向 ScrollView 抢走。
      body: Stack(
        fit: StackFit.expand,
        children: [
          DragToMoveArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _exit,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: miniVerticalPadding,
                ),
                child: Center(
                  child: line == null
                      ? Text(
                          player.track == null
                              ? '暂无歌词 · 双击或托盘回主界面'
                              : '…',
                          style: TextStyle(color: colors.fgDim, fontSize: 13),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: MediaQuery.sizeOf(context).height -
                                  miniVerticalPadding * 2,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (tokens != null && tokens.isNotEmpty)
                                  FuriRubyLine(
                                    tokens: tokens,
                                    baseStyle: baseStyle,
                                    rubyColor: colors.ruby,
                                    singleLine: true,
                                  )
                                else
                                  Text(line.text, style: baseStyle),
                                if (line.translation != null &&
                                    line.translation!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      line.translation!,
                                      style: transStyle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerSignal: _onPointerSignal,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}
