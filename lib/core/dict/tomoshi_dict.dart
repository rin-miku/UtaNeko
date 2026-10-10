import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:zstd_dart/zstd_dart.dart';

import '../storage/app_data_dir.dart';

const tomoshiDictVersion = '2026-09-02';
const tomoshiDictUrl =
    'https://github.com/tomoshi-app/tomoshi-dict-data/releases/download/v$tomoshiDictVersion/tomoshi-dict-open.db.zst';

/// 发布页上的压缩包大小。HEAD 拿不到时用它显示进度。
const tomoshiDictZipBytes = 85966850;

/// 解压后的库大小，用来显示解压进度。
const tomoshiDictRawBytes = 649523200;

/// 一条词：写法、读音、按义项分开的简体释义。
class DictEntry {
  const DictEntry({
    required this.headword,
    required this.reading,
    required this.glosses,
  });

  final String headword;
  final String reading;
  final List<String> glosses;
}

class DictHit {
  const DictHit(this.entries);

  final List<DictEntry> entries;

  bool get found => entries.isNotEmpty;
}

/// 从词条 JSON 和 zh_defs JSON 抽出划词要显示的内容。没有简体义项则返回 null。
DictEntry? parseTomoshiEntry(String entryJson, String? zhJson) {
  final entry = jsonDecode(entryJson);
  if (entry is! Map) return null;

  final reading = _texts(entry['kana']).join('・');
  var headword = _kanji(entry['kanji']).join('・');
  if (headword.isEmpty) headword = reading;
  if (headword.isEmpty) return null;

  final glosses = _zhGlosses(zhJson);
  final lines = glosses.isNotEmpty ? glosses : _entryGlosses(entry);
  if (lines.isEmpty) return null;
  return DictEntry(headword: headword, reading: reading, glosses: lines);
}

List<String> _kanji(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final info = item['info'];
    if (info is List && info.any((e) => '$e'.contains('search-only'))) continue;
    final text = item['text'];
    if (text is String && text.isNotEmpty && !out.contains(text)) out.add(text);
  }
  return out;
}

List<String> _texts(Object? raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final text = item['text'];
    if (text is String && text.isNotEmpty && !out.contains(text)) out.add(text);
  }
  return out;
}

List<String> _zhGlosses(String? zhJson) {
  if (zhJson == null || zhJson.isEmpty) return const [];
  final zh = jsonDecode(zhJson);
  if (zh is! Map || zh['senses'] is! Map) return const [];
  final senses = zh['senses'] as Map;
  final keys = senses.keys.map((k) => '$k').toList()
    ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
  final lines = <String>[];
  for (final key in keys) {
    final sense = senses[key];
    if (sense is! Map) continue;
    final line = _glossLine(sense['glosses']);
    if (line != null) lines.add(line);
  }
  return lines;
}

List<String> _entryGlosses(Map entry) {
  final senses = entry['senses'];
  if (senses is! List) return const [];
  final lines = <String>[];
  for (final sense in senses) {
    if (sense is! Map) continue;
    final glosses = sense['glosses'];
    if (glosses is! List) continue;
    final parts = <String>[];
    for (final g in glosses) {
      if (g is Map && g['lang'] == 'zho' && g['text'] is String) {
        final t = (g['text'] as String).trim();
        if (t.isNotEmpty) parts.add(t);
      }
    }
    if (parts.isNotEmpty) lines.add(parts.join('；'));
  }
  return lines;
}

String? _glossLine(Object? glosses) {
  if (glosses is! List) return null;
  final parts = <String>[];
  for (final g in glosses) {
    if (g is! Map || g['text'] is! String) continue;
    final t = (g['text'] as String).trim();
    if (t.isNotEmpty) parts.add(t);
  }
  if (parts.isEmpty) return null;
  return parts.join('；');
}

/// 下载、解压、打开 Tomoshi 开放库，并按写法查义项。
class TomoshiDict {
  TomoshiDict({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  Database? _db;
  Future<void>? _opening;
  var _cancelled = false;
  var _cancel = CancelToken();

  bool get isOpen => _db != null;
  bool get cancelled => _cancelled;

  void begin() {
    _cancelled = false;
    _cancel = CancelToken();
  }

  void requestCancel() {
    _cancelled = true;
    if (!_cancel.isCancelled) _cancel.cancel();
  }

  void _checkCancel() {
    if (_cancelled) throw const TomoshiDownloadCancelled();
  }

  Future<Directory> directory() async {
    final root = await appDataDirectory();
    return Directory(p.join(root.path, 'tomoshi-dict', tomoshiDictVersion));
  }

  Future<bool> hasReadyMarker() async {
    final dir = await directory();
    return File(p.join(dir.path, '.ready')).existsSync() &&
        File(p.join(dir.path, 'tomoshi-dict-open.db')).existsSync();
  }

  Future<int> probeSize() async {
    try {
      final res = await _dio.head(
        tomoshiDictUrl,
        options: Options(
          followRedirects: true,
          headers: {HttpHeaders.userAgentHeader: 'UtaNeko'},
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final n = int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '');
      if (n != null && n > 0) return n;
    } catch (_) {}
    return tomoshiDictZipBytes;
  }

  Future<void> install({
    required int totalBytes,
    required void Function(double progress, String label) onProgress,
  }) async {
    final dir = await directory();
    await dir.create(recursive: true);
    final zst = File(p.join(dir.path, 'tomoshi-dict-open.db.zst'));
    final dbFile = File(p.join(dir.path, 'tomoshi-dict-open.db'));
    final ready = File(p.join(dir.path, '.ready'));

    if (!zst.existsSync()) {
      _checkCancel();
      await _download(zst, totalBytes, onProgress);
    }
    _checkCancel();

    // 解压中断会留下半截库。压缩包还在就删掉重解。
    if (!ready.existsSync() && zst.existsSync() && dbFile.existsSync()) {
      dbFile.deleteSync();
    }
    if (!dbFile.existsSync()) {
      await _decompress(zst, dbFile, onProgress);
    }
    _checkCancel();

    onProgress(0.98, '建立索引…');
    final db = sqlite3.open(dbFile.path);
    try {
      db.execute('CREATE INDEX IF NOT EXISTS forms_text ON forms(text)');
    } finally {
      db.close();
    }
    _checkCancel();
    await ready.writeAsString('ok');
    if (zst.existsSync()) zst.deleteSync();
  }

  /// 删掉没完成的下载。已经能打开的库不动。
  Future<void> discardPartial() async {
    if (isOpen) return;
    final dir = await directory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 本机 tomoshi-dict 目录占用的字节数。未下载时为 0。
  Future<int> bytesOnDisk() async {
    final root = await appDataDirectory();
    final dir = Directory(p.join(root.path, 'tomoshi-dict'));
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// 关掉已打开的库并删除整个词典目录。
  Future<void> deleteAll() async {
    close();
    _opening = null;
    final root = await appDataDirectory();
    final dir = Directory(p.join(root.path, 'tomoshi-dict'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> openAt() {
    final pending = _opening;
    if (pending != null) return pending;
    final run = _openNow();
    _opening = run;
    return run.catchError((Object e) {
      if (identical(_opening, run)) _opening = null;
      throw e;
    });
  }

  Future<void> _openNow() async {
    if (_db != null) return;
    final dir = await directory();
    _db ??= sqlite3.open(
      p.join(dir.path, 'tomoshi-dict-open.db'),
      mode: OpenMode.readOnly,
    );
  }

  void close() {
    _db?.close();
    _db = null;
  }

  DictHit find(String q) {
    final db = _db;
    if (db == null) throw StateError('词典尚未就绪');
    final rows = db.select(
      '''
      SELECT e.id AS id, e.data AS entry, z.data AS zh
      FROM forms f
      JOIN entries e ON e.id = f.entry_id
      LEFT JOIN zh_defs z ON z.entry_id = e.id
      WHERE f.text = ?
      ORDER BY f.is_common DESC, e.id
      ''',
      [q],
    );
    final seen = <String>{};
    final entries = <DictEntry>[];
    for (final row in rows) {
      final id = '${row['id']}';
      if (!seen.add(id)) continue;
      final parsed = parseTomoshiEntry(row['entry'] as String, row['zh'] as String?);
      if (parsed != null) entries.add(parsed);
    }
    return DictHit(entries);
  }

  Future<void> _download(
    File dest,
    int totalBytes,
    void Function(double progress, String label) onProgress,
  ) async {
    final part = File('${dest.path}.part');
    if (part.existsSync()) part.deleteSync();
    try {
      await _dio.download(
        tomoshiDictUrl,
        part.path,
        cancelToken: _cancel,
        options: Options(
          headers: {HttpHeaders.userAgentHeader: 'UtaNeko'},
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (got, total) {
          final n = total > 0 ? total : totalBytes;
          onProgress((got / n).clamp(0, 1) * 0.8, '下载词典…');
        },
      );
    } on DioException catch (e) {
      if (part.existsSync()) part.deleteSync();
      if (e.type == DioExceptionType.cancel || _cancelled) {
        throw const TomoshiDownloadCancelled();
      }
      rethrow;
    }
    if (dest.existsSync()) dest.deleteSync();
    await part.rename(dest.path);
  }

  Future<void> _decompress(
    File zst,
    File dbFile,
    void Function(double progress, String label) onProgress,
  ) async {
    final decoder = ZstdStreamDecoder();
    final input = await zst.open();
    final output = await dbFile.open(mode: FileMode.write);
    final buf = Uint8List(1024 * 1024);
    var produced = 0;
    try {
      while (true) {
        _checkCancel();
        final n = await input.readInto(buf);
        if (n <= 0) break;
        final out = decoder.feed(Uint8List.sublistView(buf, 0, n));
        if (out.isNotEmpty) {
          await output.writeFrom(out);
          produced += out.length;
          final frac = (produced / tomoshiDictRawBytes).clamp(0.0, 1.0);
          onProgress(0.8 + frac * 0.18, '解压词典…');
        }
        await Future<void>.delayed(Duration.zero);
      }
      decoder.finish();
    } catch (e) {
      await output.close();
      await input.close();
      decoder.dispose();
      if (dbFile.existsSync()) dbFile.deleteSync();
      rethrow;
    }
    await output.close();
    await input.close();
    decoder.dispose();
  }
}

enum TomoshiStatus { unknown, downloading, ready, failed }

class TomoshiDownloadCancelled implements Exception {
  const TomoshiDownloadCancelled();
}

class TomoshiDictState {
  const TomoshiDictState({
    this.status = TomoshiStatus.unknown,
    this.progress = 0,
    this.totalBytes,
    this.label,
    this.error,
  });

  final TomoshiStatus status;
  final double progress;
  final int? totalBytes;
  final String? label;
  final String? error;

  TomoshiDictState copyWith({
    TomoshiStatus? status,
    double? progress,
    int? totalBytes,
    String? label,
    bool clearLabel = false,
    String? error,
    bool clearError = false,
  }) {
    return TomoshiDictState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalBytes: totalBytes ?? this.totalBytes,
      label: clearLabel ? null : (label ?? this.label),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final tomoshiDictProvider =
    NotifierProvider<TomoshiDictService, TomoshiDictState>(TomoshiDictService.new);

class TomoshiDictService extends Notifier<TomoshiDictState> {
  late final TomoshiDict _dict;
  Future<void>? _task;
  DateTime? _lastUi;
  var _stop = false;

  @override
  TomoshiDictState build() {
    _dict = TomoshiDict();
    ref.onDispose(_dict.close);
    unawaited(_openIfReady());
    return const TomoshiDictState();
  }

  DictHit find(String q) => _dict.find(q);

  /// 本机已有解压好的库就打开并返回 true。
  Future<bool> ensureOpen() async {
    if (_dict.isOpen) return true;
    if (!await _dict.hasReadyMarker()) return false;
    await _dict.openAt();
    state = state.copyWith(
      status: TomoshiStatus.ready,
      progress: 1,
      clearLabel: true,
      clearError: true,
    );
    return true;
  }

  Future<void> download() {
    if (_task != null) return _task!;
    _stop = false;
    return _task = _download().whenComplete(() => _task = null);
  }

  Future<int> diskBytes() => _dict.bytesOnDisk();

  /// 停掉进行中的下载，关闭数据库，并删除本机词典文件。
  Future<void> deleteDictionary() async {
    if (state.status == TomoshiStatus.downloading || _task != null) {
      await cancel();
    }
    await _dict.deleteAll();
    state = const TomoshiDictState();
  }

  /// 关掉下载弹窗：停掉传输，并删掉这次没下完的文件。
  Future<void> cancel() async {
    if (state.status == TomoshiStatus.ready) return;
    _stop = true;
    _dict.requestCancel();
    state = state.copyWith(
      status: TomoshiStatus.unknown,
      progress: 0,
      clearLabel: true,
      clearError: true,
    );
    final task = _task;
    if (task != null) {
      try {
        await task;
      } catch (_) {}
    }
    await _dict.discardPartial();
  }

  Future<void> _openIfReady() async {
    if (await _dict.hasReadyMarker()) {
      await _dict.openAt();
      state = state.copyWith(
        status: TomoshiStatus.ready,
        progress: 1,
        clearLabel: true,
        clearError: true,
      );
    }
  }

  Future<void> _download() async {
    if (_stop) return;
    if (await ensureOpen()) return;
    if (_stop) return;
    _dict.begin();
    if (_stop) {
      _dict.requestCancel();
      return;
    }
    try {
      final total = await _dict.probeSize();
      if (_stop || _dict.cancelled) throw const TomoshiDownloadCancelled();
      state = state.copyWith(
        status: TomoshiStatus.downloading,
        progress: 0,
        totalBytes: total,
        label: '准备下载…',
        clearError: true,
      );
      await _dict.install(
        totalBytes: total,
        onProgress: _emit,
      );
      await _dict.openAt();
      if (_dict.cancelled) throw const TomoshiDownloadCancelled();
      state = state.copyWith(
        status: TomoshiStatus.ready,
        progress: 1,
        clearLabel: true,
        clearError: true,
      );
    } on TomoshiDownloadCancelled {
      state = state.copyWith(
        status: TomoshiStatus.unknown,
        progress: 0,
        clearLabel: true,
        clearError: true,
      );
    } catch (e) {
      if (_stop || _dict.cancelled) {
        state = state.copyWith(
          status: TomoshiStatus.unknown,
          progress: 0,
          clearLabel: true,
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        status: TomoshiStatus.failed,
        error: e is DioException ? '词典下载失败' : '$e',
        clearLabel: true,
      );
    }
  }

  void _emit(double progress, String label) {
    if (_dict.cancelled) return;
    final now = DateTime.now();
    final last = _lastUi;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 120) &&
        progress < 0.98) {
      return;
    }
    _lastUi = now;
    state = state.copyWith(
      status: TomoshiStatus.downloading,
      progress: progress,
      label: label,
    );
  }
}
