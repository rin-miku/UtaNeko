import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/dict/tomoshi_dict.dart';
import '../../core/furigana/furi_ruby.dart';
import '../../core/furigana/furi_token.dart';
import '../../core/furigana/furigana_service.dart';
import '../../core/lyric/lrc_parser.dart';
import '../../core/storage/lyric_scale.dart';
import 'tomoshi_download_dialog.dart';

final _noise = RegExp(r'[\s\u3000\p{P}\p{S}]', unicode: true);

/// 长按歌词：上方展示这一句，划词后查本机日中词典。
class LyricLookupPage extends ConsumerStatefulWidget {
  const LyricLookupPage({
    super.key,
    required this.line,
    required this.showTranslation,
    this.tokens,
  });

  final LyricLine line;
  final bool showTranslation;

  /// 主界面已分词结果；为空时若注音已开会再 analyze 一次。
  final List<FuriToken>? tokens;

  @override
  ConsumerState<LyricLookupPage> createState() => _LyricLookupPageState();
}

class _LyricLookupPageState extends ConsumerState<LyricLookupPage> {
  Timer? _debounce;
  var _seq = 0;
  var _loading = false;
  var _dialog = false;
  String? _message;
  DictHit? _hit;
  List<FuriToken>? _tokens;

  @override
  void initState() {
    super.initState();
    _tokens = widget.tokens;
    if (_tokens == null) {
      unawaited(_ensureTokens());
    }
  }

  @override
  void didUpdateWidget(covariant LyricLookupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.tokens, oldWidget.tokens)) {
      _tokens = widget.tokens;
      if (_tokens == null) {
        unawaited(_ensureTokens());
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// 词典已就绪时补一次分词，用于上方注音；不触发下载。
  Future<void> _ensureTokens() async {
    final furi = ref.read(furiganaServiceProvider);
    if (!furi.enabled || furi.dictStatus != DictStatus.ready) return;
    try {
      final tokens =
          await ref.read(furiganaServiceProvider.notifier).analyzeLine(
                widget.line.text,
              );
      if (!mounted || widget.tokens != null) return;
      setState(() => _tokens = tokens);
    } catch (_) {}
  }

  void _onSelectedPlain(String raw) {
    final q = raw.replaceAll(_noise, '');
    _debounce?.cancel();
    if (q.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _lookup(q));
  }

  void _onSelection(TextSelection selection) {
    _onSelectedPlain(_slice(widget.line.text, selection));
  }

  Future<void> _lookup(String q) async {
    if (_dialog) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _message = null;
      _hit = null;
    });
    try {
      final dict = ref.read(tomoshiDictProvider.notifier);
      if (!await dict.ensureOpen()) {
        if (!mounted || seq != _seq || _dialog) return;
        _dialog = true;
        setState(() => _loading = false);
        await showTomoshiDownloadDialog(context);
        _dialog = false;
        if (!mounted || seq != _seq) return;
        final st = ref.read(tomoshiDictProvider);
        setState(() {
          _message = switch (st.status) {
            TomoshiStatus.ready => '词典已就绪，请重新划词',
            TomoshiStatus.failed => st.error ?? '词典下载失败',
            _ => null,
          };
        });
        return;
      }
      var hit = dict.find(q);
      if (!hit.found) {
        final base = await _lemma(q);
        if (base != null) hit = dict.find(base);
      }
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _hit = hit.found ? hit : null;
        _message = hit.found ? null : '没有查到这个词';
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _hit = null;
        _message = e is StateError ? e.message : '词典查询失败';
      });
    }
  }

  /// 选区只有一个实词时，用它的基本形再查一次（見て → 見る）。
  /// 注音词典还没下过就不在这里触发下载。
  Future<String?> _lemma(String q) async {
    if (ref.read(furiganaServiceProvider).dictStatus != DictStatus.ready) {
      return null;
    }
    try {
      final tokens =
          await ref.read(furiganaServiceProvider.notifier).analyzeLine(q);
      final content = tokens.where((t) {
        return t.surface.isNotEmpty &&
            t.pos != '助詞' &&
            t.pos != '助動詞' &&
            t.pos != '記号';
      }).toList();
      if (content.length != 1) return null;
      final base = content.single.basicForm.trim();
      if (base.isEmpty || base == '*' || base == q) return null;
      return base;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scale = ref.watch(lyricScaleProvider);
    final furi = ref.watch(furiganaServiceProvider);
    final lineStyle = scaleTextStyle(
      Theme.of(context).textTheme.headlineSmall,
      scale,
      fallback: 24,
    );
    final translationStyle = scaleTextStyle(
      Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.fgDim),
      scale,
      fallback: 14,
    );
    final translation = widget.line.translation;
    final showTr = widget.showTranslation &&
        translation != null &&
        translation.isNotEmpty;
    final toks = _tokens;
    final showFuri =
        furi.enabled && toks != null && toks.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('查词')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
            child: Column(
              children: [
                if (showFuri)
                  SelectionArea(
                    onSelectionChanged: (content) {
                      _onSelectedPlain(content?.plainText ?? '');
                    },
                    child: FuriRubyLine(
                      tokens: toks,
                      baseStyle: lineStyle,
                      rubyColor: colors.ruby,
                    ),
                  )
                else
                  SelectableText(
                    widget.line.text,
                    textAlign: TextAlign.center,
                    style: lineStyle,
                    onSelectionChanged: (selection, _) =>
                        _onSelection(selection),
                  ),
                if (showTr)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      translation,
                      textAlign: TextAlign.center,
                      style: translationStyle,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '划选要查的词',
                    style: TextStyle(color: colors.fgDim, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(context, colors)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppColors colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final hit = _hit;
    if (hit != null && hit.found) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          for (final entry in hit.entries) ...[
            Text(entry.headword, style: Theme.of(context).textTheme.titleLarge),
            if (entry.reading.isNotEmpty && entry.reading != entry.headword)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(entry.reading, style: TextStyle(color: colors.fgDim)),
              ),
            const SizedBox(height: 12),
            for (final line in entry.glosses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line, style: Theme.of(context).textTheme.bodyLarge),
              ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }
    return Center(
      child: Text(
        _message ?? '划选歌词中的词',
        style: TextStyle(color: colors.fgDim),
      ),
    );
  }

  static String _slice(String text, TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed) return '';
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    if (end <= start) return '';
    return text.substring(start, end);
  }
}
