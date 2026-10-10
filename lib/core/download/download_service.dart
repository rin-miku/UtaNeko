import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../sources/models.dart';
import '../furigana/furi_token.dart';
import '../furigana/furi_txt.dart';
import 'safe_filename.dart';

/// SharedPreferences：用户自选下载根目录。
const kDownloadDirPrefKey = 'utaneko:dl_dir';

/// 裸音频 + 旁路 LRC/封面/注音；不阻塞播放（调用方在 UI 层异步触发）。
class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 默认按网易云头；调用方应传入当前音源的 mediaHeaders。
  static const defaultMediaHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Referer': 'https://music.163.com/',
  };

  /// 兼容旧调用名。
  static const neteaseHeaders = defaultMediaHeaders;

  Future<Directory> defaultSaveDir() async {
    final dl = await getDownloadsDirectory();
    if (dl != null) {
      final dir = Directory(p.join(dl.path, 'UtaNeko'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(doc.path, 'UtaNeko'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 根目录下为当前曲创建 `歌手 - 歌名/` 子文件夹。
  Future<Directory> songFolder(TrackMeta meta, Directory root) async {
    final name = safeFolderName(title: meta.title, artists: meta.artists);
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// [dir] 为下载根目录时自动建歌曲夹；已是歌曲夹也可直接传入。
  Future<Directory> _resolveSongDir(TrackMeta meta, Directory? dir) async {
    final root = dir ?? await defaultSaveDir();
    final expected = safeFolderName(title: meta.title, artists: meta.artists);
    if (p.basename(root.path) == expected) return root;
    return songFolder(meta, root);
  }

  Future<String> downloadAudio({
    required TrackMeta meta,
    required String url,
    required AudioQuality quality,
    Directory? dir,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) async {
    final folder = await _resolveSongDir(meta, dir);
    final ext = _guessExt(url);
    final path = p.join(folder.path, 'audio.$ext');
    await _dio.download(
      url,
      path,
      options: Options(headers: headers ?? defaultMediaHeaders),
      onReceiveProgress: (got, total) {
        if (total > 0) onProgress?.call(got / total);
      },
    );
    return path;
  }

  Future<String> saveLrc({
    required TrackMeta meta,
    required String lrcRaw,
    Directory? dir,
  }) async {
    final folder = await _resolveSongDir(meta, dir);
    final path = p.join(folder.path, 'lyrics.lrc');
    await File(path).writeAsString(lrcRaw, flush: true);
    return path;
  }

  /// 有翻译时写入旁路 `lyrics.trans.lrc`；空串则跳过并返回 null。
  Future<String?> saveTranslatedLrc({
    required TrackMeta meta,
    required String translatedLrc,
    Directory? dir,
  }) async {
    if (translatedLrc.trim().isEmpty) return null;
    final folder = await _resolveSongDir(meta, dir);
    final path = p.join(folder.path, 'lyrics.trans.lrc');
    await File(path).writeAsString(translatedLrc, flush: true);
    return path;
  }

  Future<String> saveCover({
    required TrackMeta meta,
    Directory? dir,
  }) async {
    if (meta.coverUrl.isEmpty) {
      throw StateError('无封面 URL');
    }
    final folder = await _resolveSongDir(meta, dir);
    final ext = _extFromUrl(meta.coverUrl) ?? 'jpg';
    final path = p.join(folder.path, 'cover.$ext');
    await _dio.download(meta.coverUrl, path);
    return path;
  }

  Future<String> saveFuriTxt({
    required TrackMeta meta,
    required List<List<FuriToken>> tokens,
    Directory? dir,
  }) async {
    final folder = await _resolveSongDir(meta, dir);
    final path = p.join(folder.path, 'furi.txt');
    await File(path).writeAsString(encodeFuriTxt(tokens), flush: true);
    return path;
  }

  String _guessExt(String url) {
    final u = url.toLowerCase();
    if (u.contains('.flac')) return 'flac';
    if (u.contains('.m4a')) return 'm4a';
    return 'mp3';
  }

  String? _extFromUrl(String url) {
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot == -1) return null;
      return path.substring(dot + 1).split('?').first;
    } catch (_) {
      return null;
    }
  }
}
