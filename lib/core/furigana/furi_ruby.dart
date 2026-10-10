import 'package:flutter/material.dart';

import 'furi_token.dart';

final _katakana = RegExp(r'[\u30a1-\u30f6]');
final _kanji = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');

String toHiragana(String s) {
  return s.replaceAllMapped(_katakana, (m) {
    return String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0x60);
  });
}

bool needsRuby(FuriToken t) {
  final s = t.surface;
  if (s.isEmpty) return false;
  final r = t.reading;
  if (r.isEmpty || _kanji.hasMatch(r)) return false;
  if (t.pos == '記号') return false;
  return _kanji.hasMatch(s) && toHiragana(r) != s;
}

/// 单行注音：用 Row / Wrap + 小字读音，避免依赖 WebView。
class FuriRubyLine extends StatelessWidget {
  const FuriRubyLine({
    super.key,
    required this.tokens,
    required this.baseStyle,
    this.rubyColor,
    this.singleLine = false,
  });

  final List<FuriToken> tokens;
  final TextStyle? baseStyle;
  final Color? rubyColor;

  /// true 时不换行（Mini 横向滚动用）。
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final rubyStyle = baseStyle?.copyWith(
      fontSize: (baseStyle?.fontSize ?? 16) * 0.55,
      color: rubyColor ?? const Color(0xFF8FD3A8),
      height: 1.1,
    );
    final children = <Widget>[
      for (final t in tokens)
        if (t.surface.isNotEmpty)
          needsRuby(t)
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 划词时排除注音，只选表面形（查词页 SelectionArea）。
                      SelectionContainer.disabled(
                        child: Text(toHiragana(t.reading), style: rubyStyle),
                      ),
                      Text(t.surface, style: baseStyle),
                    ],
                  ),
                )
              : Text(t.surface, style: baseStyle),
    ];
    if (singleLine) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: children,
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: children,
    );
  }
}
