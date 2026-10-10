import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/furigana/furi_ruby.dart';
import '../../core/storage/lyric_scale.dart';
import '../../core/furigana/furi_token.dart';
import '../../core/lyric/lrc_parser.dart';

class LyricPanel extends StatefulWidget {
  const LyricPanel({
    super.key,
    required this.lines,
    required this.activeIndex,
    required this.showTranslation,
    required this.onTapLine,
    this.onLongPressLine,
    this.showFurigana = false,
    this.tokenLines,
    this.scale = 1,
  });

  final List<LyricLine> lines;
  final int activeIndex;
  final bool showTranslation;
  final ValueChanged<int> onTapLine;
  final ValueChanged<int>? onLongPressLine;
  final bool showFurigana;
  final List<List<FuriToken>?>? tokenLines;
  final double scale;

  @override
  State<LyricPanel> createState() => _LyricPanelState();
}

class _LyricPanelState extends State<LyricPanel> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant LyricPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != oldWidget.activeIndex &&
        widget.activeIndex >= 0) {
      _scrollToActive();
    }
  }

  void _scrollToActive() {
    if (!_controller.hasClients) return;
    final itemExtent = 56.0 * widget.scale;
    final target = (widget.activeIndex * itemExtent) -
        _controller.position.viewportDimension / 3;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (widget.lines.isEmpty) {
      return Center(
        child: Text('歌词将显示在这里', style: TextStyle(color: colors.fgDim)),
      );
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      itemCount: widget.lines.length,
      itemBuilder: (context, i) {
        final line = widget.lines[i];
        final active = i == widget.activeIndex;
        final baseStyle = scaleTextStyle(
          Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: active
                    ? colors.lyricActive
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
          widget.scale,
          fallback: 16,
        );
        final toks = widget.tokenLines != null && i < widget.tokenLines!.length
            ? widget.tokenLines![i]
            : null;
        return InkWell(
          onTap: () => widget.onTapLine(i),
          onLongPress: widget.onLongPressLine == null
              ? null
              : () => widget.onLongPressLine!(i),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.showFurigana && toks != null)
                  FuriRubyLine(
                    tokens: toks,
                    baseStyle: baseStyle,
                    rubyColor: colors.lyricActive.withValues(alpha: 0.75),
                  )
                else
                  Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: baseStyle,
                  ),
                if (widget.showTranslation &&
                    line.translation != null &&
                    line.translation!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line.translation!,
                      textAlign: TextAlign.center,
                      style: scaleTextStyle(
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.fgDim,
                        ),
                        widget.scale,
                        fallback: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
