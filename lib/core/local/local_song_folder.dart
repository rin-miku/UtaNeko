import 'dart:io';

import 'package:path/path.dart' as p;

/// 本地歌曲夹扫描结果（与下载落盘约定一致）。
class LocalSongBundle {
  const LocalSongBundle({
    required this.directory,
    required this.audioPath,
    required this.title,
    required this.artists,
    this.coverPath,
    this.lrcRaw,
    this.translatedLrc,
    this.furiTxt,
  });

  final Directory directory;
  final String audioPath;
  final String title;
  final String artists;
  final String? coverPath;
  final String? lrcRaw;
  /// 旁路翻译 LRC（`lyrics.trans.lrc`）。
  final String? translatedLrc;
  final String? furiTxt;
}

const _audioExts = {'mp3', 'flac', 'm4a', 'wav', 'ogg', 'aac'};
const _coverExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'};

/// 是否为本地曲目 id（`local:` + 文件夹绝对路径）。
bool isLocalTrackId(String? id) => id != null && id.startsWith('local:');

/// 从 `local:/path` 还原文件夹路径。
String? localFolderPathFromId(String id) {
  if (!isLocalTrackId(id)) return null;
  return id.substring('local:'.length);
}

/// 夹名 `歌手 - 歌名`：按第一个 ` - ` 拆分；无分隔符则整段为歌名。
({String artists, String title}) parseFolderMeta(String folderName) {
  final name = folderName.trim();
  if (name.isEmpty) {
    return (artists: '', title: '未知曲目');
  }
  final sep = ' - ';
  final i = name.indexOf(sep);
  if (i <= 0) {
    return (artists: '', title: name);
  }
  final artists = name.substring(0, i).trim();
  final title = name.substring(i + sep.length).trim();
  if (title.isEmpty) {
    return (artists: '', title: name);
  }
  return (artists: artists, title: title);
}

/// 扫描单曲文件夹；无音频则抛 [StateError]。
Future<LocalSongBundle> loadLocalSongFolder(Directory dir) async {
  if (!await dir.exists()) {
    throw StateError('文件夹不存在');
  }

  final entities = await dir.list(followLinks: false).toList();
  final files = <File>[];
  for (final e in entities) {
    if (e is File) files.add(e);
  }

  final audioPath = _pickAudio(files);
  if (audioPath == null) {
    throw StateError('文件夹内未找到音频（需要 audio.* 或 mp3/flac/m4a 等）');
  }

  final coverPath = _pickCover(files);
  String? lrcRaw;
  final lrcFile = File(p.join(dir.path, 'lyrics.lrc'));
  if (await lrcFile.exists()) {
    lrcRaw = await lrcFile.readAsString();
  }

  String? translatedLrc;
  final transFile = File(p.join(dir.path, 'lyrics.trans.lrc'));
  if (await transFile.exists()) {
    translatedLrc = await transFile.readAsString();
  }

  String? furiTxt;
  final furiFile = File(p.join(dir.path, 'furi.txt'));
  if (await furiFile.exists()) {
    furiTxt = await furiFile.readAsString();
  }

  final meta = parseFolderMeta(p.basename(dir.path));
  return LocalSongBundle(
    directory: dir,
    audioPath: audioPath,
    title: meta.title,
    artists: meta.artists,
    coverPath: coverPath,
    lrcRaw: lrcRaw,
    translatedLrc: translatedLrc,
    furiTxt: furiTxt,
  );
}

String? _pickAudio(List<File> files) {
  File? preferred;
  File? fallback;
  for (final f in files) {
    final name = p.basename(f.path);
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (!_audioExts.contains(ext)) continue;
    final stem = p.basenameWithoutExtension(name).toLowerCase();
    if (stem == 'audio') {
      preferred ??= f;
    } else {
      fallback ??= f;
    }
  }
  return (preferred ?? fallback)?.path;
}

String? _pickCover(List<File> files) {
  for (final f in files) {
    final name = p.basename(f.path);
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (!_coverExts.contains(ext)) continue;
    if (p.basenameWithoutExtension(name).toLowerCase() == 'cover') {
      return f.path;
    }
  }
  return null;
}
