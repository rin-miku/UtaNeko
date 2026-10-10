import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:kuromoji/src/dict/data/char.dart';
import 'package:kuromoji/src/dict/dynamic_dictionaries.dart';
import 'package:kuromoji/src/tokenizer.dart';
import 'package:path/path.dart' as p;

import '../storage/app_data_dir.dart';

/// 词典下载/加载进度回调。
class DictLoadProgress {
  const DictLoadProgress({
    required this.overall,
    this.fileIndex = 0,
    this.fileTotal = 0,
    this.fileName,
    this.phase = DictLoadPhase.idle,
  });

  /// 0.0–1.0 总进度
  final double overall;
  final int fileIndex;
  final int fileTotal;
  final String? fileName;
  final DictLoadPhase phase;
}

enum DictLoadPhase {
  idle,
  downloading,
  extracting,
  done,
}

/// 用户关掉下载弹窗。
class DictDownloadCancelled implements Exception {
  const DictDownloadCancelled();
}

/// 字节数格式化为 MB（二进制，保留两位）。
String formatDictMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(2)} MB';
}

/// 从 CDN 按需下载 IPADIC（与 kuromoji.js 0.1.2 同源），不调用内嵌大词典的 [TokenizerBuilder]。
class KuromojiLoader {
  KuromojiLoader({Dio? dio}) : _dio = dio ?? Dio();

  static const dictVersion = '0.1.2';
  static const cdnBase = 'https://cdn.jsdelivr.net/npm/kuromoji@$dictVersion/dict/';

  static const _datFiles = [
    'base.dat',
    'cc.dat',
    'check.dat',
    'tid_map.dat',
    'tid_pos.dat',
    'tid.dat',
    'unk_char.dat',
    'unk_compat.dat',
    'unk_invoke.dat',
    'unk_map.dat',
    'unk_pos.dat',
    'unk.dat',
  ];

  final Dio _dio;
  Tokenizer? _tokenizer;
  int? _probedBytes;
  var _cancelled = false;
  var _cancel = CancelToken();

  Tokenizer? get tokenizer => _tokenizer;
  bool get cancelled => _cancelled;

  void forgetTokenizer() {
    _tokenizer = null;
  }

  /// 新一轮下载开始时清掉上一轮的取消标记。
  void begin() {
    _cancelled = false;
    _cancel = CancelToken();
  }

  void requestCancel() {
    _cancelled = true;
    if (!_cancel.isCancelled) _cancel.cancel();
  }

  void _checkCancel() {
    if (_cancelled) throw const DictDownloadCancelled();
  }

  /// 并行 HEAD 各 `.gz`，汇总 Content-Length。结果缓存，避免重复探测。
  Future<int> probeTotalBytes() async {
    final cached = _probedBytes;
    if (cached != null && cached > 0) return cached;

    final sizes = await Future.wait(_datFiles.map(_headSize));
    final sum = sizes.fold<int>(0, (a, b) => a + b);
    if (sum <= 0) {
      throw StateError('无法获取词典大小');
    }
    _probedBytes = sum;
    return sum;
  }

  Future<int> _headSize(String name) async {
    final res = await _dio.head(
      '$cdnBase$name.gz',
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final raw = res.headers.value(Headers.contentLengthHeader);
    final n = int.tryParse(raw ?? '');
    if (n == null || n <= 0) {
      throw StateError('无法获取 $name.gz 大小');
    }
    return n;
  }

  Future<Directory> dictDirectory() async {
    final root = await appDataDirectory();
    return Directory(p.join(root.path, 'kuromoji-dict', dictVersion));
  }

  Future<bool> isReady() async {
    final dir = await dictDirectory();
    return File(p.join(dir.path, '.ready')).existsSync();
  }

  /// 删掉没下完的文件。已经加载进内存的词典不动。
  Future<void> discardPartial() async {
    if (_tokenizer != null) return;
    final dir = await dictDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 删除本机词典文件并释放内存 tokenizer；下次注音会重新下载。
  Future<void> clearDictionary() async {
    _tokenizer = null;
    final root = await appDataDirectory();
    final dir = Directory(p.join(root.path, 'kuromoji-dict'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// [onProgress] 细粒度进度（含当前文件名）。
  Future<Tokenizer> ensureTokenizer({
    void Function(DictLoadProgress progress)? onProgress,
  }) async {
    if (_tokenizer != null) {
      onProgress?.call(const DictLoadProgress(
        overall: 1,
        phase: DictLoadPhase.done,
      ));
      return _tokenizer!;
    }

    final dir = await dictDirectory();
    final needsDownload = !await File(p.join(dir.path, '.ready')).exists();

    if (needsDownload) {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final total = _datFiles.length;
      for (var i = 0; i < total; i++) {
        _checkCancel();
        final name = _datFiles[i];
        final dest = File(p.join(dir.path, '$name.gz'));
        await _downloadFile(
          '$cdnBase$name.gz',
          dest,
          onBytes: (got, totalBytes) {
            final fileFrac = totalBytes > 0 ? got / totalBytes : 0.0;
            final overall = (i + fileFrac) / total;
            onProgress?.call(DictLoadProgress(
              overall: overall.clamp(0, 1),
              fileIndex: i + 1,
              fileTotal: total,
              fileName: '$name.gz',
              phase: DictLoadPhase.downloading,
            ));
          },
        );
        onProgress?.call(DictLoadProgress(
          overall: (i + 1) / total,
          fileIndex: i + 1,
          fileTotal: total,
          fileName: '$name.gz',
          phase: DictLoadPhase.downloading,
        ));
      }
      _checkCancel();
      await File(p.join(dir.path, '.ready')).writeAsString('ok');
    }

    onProgress?.call(const DictLoadProgress(
      overall: 0.95,
      phase: DictLoadPhase.extracting,
      fileName: '解压词典…',
    ));
    _tokenizer = await _buildFromDir(dir);
    onProgress?.call(const DictLoadProgress(
      overall: 1,
      phase: DictLoadPhase.done,
    ));
    return _tokenizer!;
  }

  Future<void> _downloadFile(
    String url,
    File dest, {
    void Function(int got, int total)? onBytes,
  }) async {
    try {
      await _dio.download(
        url,
        dest.path,
        cancelToken: _cancel,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        ),
        onReceiveProgress: (got, total) {
          if (total > 0) onBytes?.call(got, total);
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || _cancelled) {
        throw const DictDownloadCancelled();
      }
      rethrow;
    }
  }

  Future<Tokenizer> _buildFromDir(Directory dir) async {
    final gzip = GZipDecoder();
    final data = <String, Uint8List>{};
    for (final name in _datFiles) {
      _checkCancel();
      final raw = await File(p.join(dir.path, '$name.gz')).readAsBytes();
      data[name] = Uint8List.fromList(gzip.decodeBytes(raw));
      // 解压很吃 CPU，每文件让出一帧，避免卡住音频通道回调
      await Future<void>.delayed(Duration.zero);
    }
    final dictionaries = DynamicDictionaries(data, charData);
    await Future<void>.delayed(Duration.zero);
    return Tokenizer(dictionaries);
  }
}
