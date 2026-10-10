import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/app_data_dir.dart';

import 'furi_token.dart';

/// 按曲缓存分词结果（与 Web localStorage key 语义一致）。
class FuriganaCache {
  Future<File> _fileFor(String trackId) async {
    final root = await appDataDirectory();
    final dir = Directory(p.join(root.path, 'furi-cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = trackId.replaceAll(RegExp(r'[^\w\-]'), '_');
    return File(p.join(dir.path, '$safe.json'));
  }

  Future<List<List<FuriToken>>?> read(String trackId, int lineCount) async {
    try {
      final f = await _fileFor(trackId);
      if (!await f.exists()) return null;
      final arr = jsonDecode(await f.readAsString()) as List<dynamic>;
      if (arr.length != lineCount) return null;
      // 旧缓存没有基本形字段，丢弃后重新分词。
      for (final line in arr) {
        if (line is! List) return null;
        for (final t in line) {
          if (t is! Map || !t.containsKey('b')) return null;
        }
      }
      return arr
          .map((line) => (line as List<dynamic>)
              .map((t) => FuriToken.fromJson(Map<String, dynamic>.from(t as Map)))
              .toList())
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String trackId, List<List<FuriToken>> tokens) async {
    final f = await _fileFor(trackId);
    final json = tokens.map((line) => line.map((t) => t.toJson()).toList()).toList();
    await f.writeAsString(jsonEncode(json), flush: true);
  }

  /// 清除全部按曲注音缓存。
  Future<void> clearAll() async {
    final root = await appDataDirectory();
    final dir = Directory(p.join(root.path, 'furi-cache'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
