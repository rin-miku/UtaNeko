import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kuromoji/src/tokenizer.dart';

import '../../core/lyric/lrc_parser.dart';
import '../../core/storage/prefs.dart';
import 'furi_token.dart';
import 'furi_txt.dart';
import 'furigana_cache.dart';
import 'kuromoji_loader.dart';

const _furiKey = 'utaneko:furi';

final furiganaServiceProvider =
    NotifierProvider<FuriganaService, FuriganaState>(FuriganaService.new);

enum DictStatus { unknown, downloading, ready, failed }

class FuriganaState {
  const FuriganaState({
    this.enabled = false,
    this.dictStatus = DictStatus.unknown,
    this.dictProgress = 0,
    this.dictTotalBytes,
    this.dictFileLabel,
    this.dictError,
    this.trackId,
    this.tokens,
    this.tokenizing = false,
  });

  final bool enabled;
  final DictStatus dictStatus;
  final double dictProgress;

  /// 词典压缩包总字节（HEAD 探测后写入）。
  final int? dictTotalBytes;

  /// 如「下载 base.dat.gz (3/12)」或「解压词典…」
  final String? dictFileLabel;
  final String? dictError;
  final String? trackId;
  final List<List<FuriToken>>? tokens;
  final bool tokenizing;

  FuriganaState copyWith({
    bool? enabled,
    DictStatus? dictStatus,
    double? dictProgress,
    int? dictTotalBytes,
    String? dictFileLabel,
    bool clearDictFileLabel = false,
    String? dictError,
    bool clearDictError = false,
    String? trackId,
    List<List<FuriToken>>? tokens,
    bool clearTokens = false,
    bool? tokenizing,
  }) {
    return FuriganaState(
      enabled: enabled ?? this.enabled,
      dictStatus: dictStatus ?? this.dictStatus,
      dictProgress: dictProgress ?? this.dictProgress,
      dictTotalBytes: dictTotalBytes ?? this.dictTotalBytes,
      dictFileLabel:
          clearDictFileLabel ? null : (dictFileLabel ?? this.dictFileLabel),
      dictError: clearDictError ? null : (dictError ?? this.dictError),
      trackId: trackId ?? this.trackId,
      tokens: clearTokens ? null : (tokens ?? this.tokens),
      tokenizing: tokenizing ?? this.tokenizing,
    );
  }
}

class FuriganaService extends Notifier<FuriganaState> {
  late final KuromojiLoader _loader;
  late final FuriganaCache _cache;
  Future<Tokenizer>? _loadFut;
  DateTime? _lastProgressUi;
  String? _busyTrackId;

  @override
  FuriganaState build() {
    _loader = KuromojiLoader();
    _cache = FuriganaCache();
    final prefs = ref.read(sharedPreferencesProvider);
    // 默认关闭：避免首次使用时尚无词典却显示「已开注音」。
    final enabled = prefs.getBool(_furiKey) ?? false;
    unawaited(_refreshDictStatus());
    return FuriganaState(enabled: enabled);
  }

  Future<void> _refreshDictStatus() async {
    final ready = await _loader.isReady();
    if (ready || _loader.tokenizer != null) {
      state = state.copyWith(
        dictStatus: DictStatus.ready,
        dictProgress: 1,
        clearDictFileLabel: true,
      );
    } else {
      state = state.copyWith(
        dictStatus: DictStatus.unknown,
        dictProgress: 0,
        clearDictFileLabel: true,
      );
    }
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await ref.read(sharedPreferencesProvider).setBool(_furiKey, value);
  }

  /// 用户打开注音：无词典则先下载，成功后再启用并分词；取消/失败则保持关闭。
  Future<void> requestEnable({
    String? trackId,
    List<LyricLine> lines = const [],
  }) async {
    if (state.enabled) {
      if (trackId != null && lines.isNotEmpty) {
        await ensureForTrack(trackId, lines);
      }
      return;
    }
    try {
      await _loadTokenizer();
    } on DictDownloadCancelled {
      return;
    } catch (_) {
      // dictError 已由 _doLoadTokenizer 写入
      return;
    }
    await setEnabled(true);
    if (trackId != null && lines.isNotEmpty) {
      await ensureForTrack(trackId, lines);
    }
  }

  /// 切歌时只清 tokens，不立刻跑重活，避免拖住播放。
  void prepareForTrack(String trackId) {
    if (state.trackId == trackId) return;
    state = state.copyWith(
      trackId: trackId,
      clearTokens: true,
      clearDictError: true,
    );
  }

  /// 播放已启动后再调用：注音与播歌完全解耦。
  Future<void> onTrackChanged(String trackId, List<LyricLine> lines) async {
    state = state.copyWith(trackId: trackId, clearDictError: true);
    if (!state.enabled || lines.isEmpty) return;
    if (_busyTrackId == trackId && state.tokenizing) return;

    final cached = await _cache.read(trackId, lines.length);
    if (cached != null) {
      state = state.copyWith(tokens: cached);
      return;
    }
    await ensureForTrack(trackId, lines);
  }

  /// 打开注音或导出前：保证分词（失败则保持原文，不抛到播放链路）。
  /// [force] 为 true 时即使注音开关关闭也分词（用于导出）。
  Future<void> ensureForTrack(
    String trackId,
    List<LyricLine> lines, {
    bool force = false,
  }) async {
    if ((!state.enabled && !force) || lines.isEmpty) return;
    if (state.trackId == trackId &&
        state.tokens != null &&
        state.tokens!.length == lines.length) {
      return;
    }
    if (_busyTrackId == trackId && state.tokenizing) return;

    final cached = await _cache.read(trackId, lines.length);
    if (cached != null) {
      state = state.copyWith(trackId: trackId, tokens: cached);
      return;
    }

    _busyTrackId = trackId;
    state = state.copyWith(trackId: trackId, tokenizing: true, clearDictError: true);
    try {
      final tokenizer = await _loadTokenizer();
      // 若期间又切了歌，丢弃结果
      if (state.trackId != trackId) {
        state = state.copyWith(tokenizing: false);
        return;
      }

      final tokens = <List<FuriToken>>[];
      for (var i = 0; i < lines.length; i++) {
        tokens.add(_tokenizeLine(tokenizer, lines[i].text));
        // 让出事件循环，避免卡住 setAudioSource / play
        if (i % 8 == 7) {
          await Future<void>.delayed(Duration.zero);
          if (state.trackId != trackId) {
            state = state.copyWith(tokenizing: false);
            return;
          }
        }
      }
      await _cache.write(trackId, tokens);
      if (state.trackId == trackId) {
        state = state.copyWith(tokens: tokens, tokenizing: false);
      } else {
        state = state.copyWith(tokenizing: false);
      }
    } catch (e) {
      if (e is DictDownloadCancelled) {
        state = state.copyWith(
          tokenizing: false,
          dictStatus: DictStatus.unknown,
          dictProgress: 0,
          clearDictFileLabel: true,
          clearDictError: true,
        );
      } else {
        state = state.copyWith(
          tokenizing: false,
          dictError: e.toString(),
          dictStatus: DictStatus.failed,
        );
      }
    } finally {
      if (_busyTrackId == trackId) _busyTrackId = null;
    }
  }

  Future<void> preloadDictionary() async {
    try {
      await _loadTokenizer();
    } on DictDownloadCancelled {
      state = state.copyWith(
        dictStatus: DictStatus.unknown,
        dictProgress: 0,
        clearDictFileLabel: true,
        clearDictError: true,
      );
    } catch (e) {
      state = state.copyWith(dictStatus: DictStatus.failed, dictError: e.toString());
    }
  }

  /// 关掉下载弹窗：停掉传输，并删掉这次没下完的文件。
  Future<void> cancelDownload() async {
    if (state.dictStatus != DictStatus.downloading) return;
    _loader.requestCancel();
    state = state.copyWith(
      dictStatus: DictStatus.unknown,
      dictProgress: 0,
      tokenizing: false,
      clearDictFileLabel: true,
      clearDictError: true,
    );
    final pending = _loadFut;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    await _loader.discardPartial();
  }

  /// 清除本机词典；下次开启注音会重新下载。
  Future<void> clearDictionary() async {
    _loadFut = null;
    await _loader.clearDictionary();
    state = state.copyWith(
      dictStatus: DictStatus.unknown,
      dictProgress: 0,
      clearDictFileLabel: true,
      clearDictError: true,
      clearTokens: true,
      tokenizing: false,
    );
  }

  /// 清除按曲注音缓存（内存 + 磁盘）。
  Future<void> clearTokenCache() async {
    await _cache.clearAll();
    state = state.copyWith(clearTokens: true);
  }

  Future<Tokenizer> _loadTokenizer() async {
    if (_loader.tokenizer != null) return _loader.tokenizer!;
    return _loadFut ??= _doLoadTokenizer().whenComplete(() => _loadFut = null);
  }

  void _emitProgress({
    required double overall,
    required DictStatus status,
    String? label,
  }) {
    if (_loader.cancelled) return;
    final now = DateTime.now();
    final last = _lastProgressUi;
    // 节流：避免 dio 字节回调把 UI/播放事件循环打满
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 120) &&
        overall < 0.99) {
      return;
    }
    _lastProgressUi = now;
    state = state.copyWith(
      dictProgress: overall,
      dictStatus: status,
      dictFileLabel: label,
    );
  }

  Future<Tokenizer> _doLoadTokenizer() async {
    _loader.begin();
    final alreadyOnDisk = await _loader.isReady();
    if (!alreadyOnDisk) {
      // 先探测总大小，再进入 downloading，弹窗一出现就有具体 MB。
      final bytes = await _loader.probeTotalBytes();
      state = state.copyWith(
        dictStatus: DictStatus.downloading,
        dictProgress: 0,
        dictTotalBytes: bytes,
        dictFileLabel: '准备下载…',
        clearDictError: true,
      );
    } else {
      state = state.copyWith(
        dictFileLabel: '加载本机词典…',
        clearDictError: true,
      );
    }

    try {
      final t = await _loader.ensureTokenizer(onProgress: (p) {
        final label = switch (p.phase) {
          DictLoadPhase.downloading when p.fileName != null =>
            '下载 ${p.fileName} (${p.fileIndex}/${p.fileTotal})',
          DictLoadPhase.extracting => '解压并加载词典…',
          DictLoadPhase.done => '完成',
          _ => p.fileName,
        };
        if (!alreadyOnDisk && p.phase == DictLoadPhase.downloading) {
          _emitProgress(
            overall: p.overall,
            status: DictStatus.downloading,
            label: label,
          );
        } else if (p.phase == DictLoadPhase.extracting) {
          _emitProgress(
            overall: alreadyOnDisk ? 0.5 : p.overall,
            status: alreadyOnDisk ? state.dictStatus : DictStatus.downloading,
            label: label,
          );
        }
      });
      if (_loader.cancelled) {
        _loader.forgetTokenizer();
        throw const DictDownloadCancelled();
      }
      state = state.copyWith(
        dictStatus: DictStatus.ready,
        dictProgress: 1,
        clearDictFileLabel: true,
        clearDictError: true,
      );
      return t;
    } on DictDownloadCancelled {
      state = state.copyWith(
        dictStatus: DictStatus.unknown,
        dictProgress: 0,
        clearDictFileLabel: true,
        clearDictError: true,
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        dictStatus: DictStatus.failed,
        dictError: e.toString(),
        clearDictFileLabel: true,
      );
      rethrow;
    }
  }

  List<FuriToken> _tokenizeLine(Tokenizer tokenizer, String text) {
    try {
      final raw = tokenizer.tokenize(text);
      return raw
          .map(
            (t) => FuriToken(
              surface: t['surface_form'] as String? ?? '',
              reading: t['reading'] as String? ?? '',
              pos: t['pos'] as String? ?? '',
              basicForm: t['basic_form'] as String? ?? '',
            ),
          )
          .toList();
    } catch (_) {
      return [FuriToken(surface: text, reading: '', pos: '')];
    }
  }

  /// 拆一行歌词。不依赖注音开关，词典未就绪时会触发下载。
  Future<List<FuriToken>> analyzeLine(String text) async {
    final tokenizer = await _loadTokenizer();
    return _tokenizeLine(tokenizer, text);
  }

  List<List<FuriToken>?> tokensForLines(int lineCount) {
    final toks = state.tokens;
    if (toks == null || toks.length != lineCount) {
      return List.filled(lineCount, null);
    }
    return toks;
  }

  /// 导入外部注音：校验行数 → 写缓存 → 更新界面（并开启注音显示）。
  Future<void> importTokens({
    required String trackId,
    required int lineCount,
    required List<List<FuriToken>> tokens,
  }) async {
    validateFuriLineCount(tokens, lineCount);
    await _cache.write(trackId, tokens);
    await ref.read(sharedPreferencesProvider).setBool(_furiKey, true);
    state = state.copyWith(
      enabled: true,
      trackId: trackId,
      tokens: tokens,
      tokenizing: false,
      clearDictError: true,
    );
  }

  /// 从 TXT 文本导入；失败抛 [FuriImportException]。
  Future<void> importFuriTxtText({
    required String trackId,
    required int lineCount,
    required String raw,
  }) async {
    final tokens = parseFuriTxt(raw);
    await importTokens(
      trackId: trackId,
      lineCount: lineCount,
      tokens: tokens,
    );
  }
}
