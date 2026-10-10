import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:utaneko/core/local/local_song_folder.dart';

void main() {
  test('parseFolderMeta 拆分歌手与歌名', () {
    final a = parseFolderMeta('ヨルシカ - 晴る');
    expect(a.artists, 'ヨルシカ');
    expect(a.title, '晴る');

    final b = parseFolderMeta('仅歌名');
    expect(b.artists, isEmpty);
    expect(b.title, '仅歌名');
  });

  test('isLocalTrackId / localFolderPathFromId', () {
    expect(isLocalTrackId('local:C:\\songs\\a'), isTrue);
    expect(isLocalTrackId('2114614108'), isFalse);
    expect(localFolderPathFromId('local:D:\\UtaNeko\\曲'), 'D:\\UtaNeko\\曲');
  });

  test('loadLocalSongFolder 优先 audio.*，缺 LRC/封面不报错', () async {
    final dir = await Directory.systemTemp.createTemp('utaneko_local_');
    addTearDown(() => dir.delete(recursive: true));

    await File(p.join(dir.path, 'other.mp3')).writeAsBytes([0]);
    await File(p.join(dir.path, 'audio.flac')).writeAsBytes([1, 2]);

    final bundle = await loadLocalSongFolder(dir);
    expect(p.basename(bundle.audioPath), 'audio.flac');
    expect(bundle.coverPath, isNull);
    expect(bundle.lrcRaw, isNull);
    expect(bundle.translatedLrc, isNull);
    expect(bundle.furiTxt, isNull);
  });

  test('loadLocalSongFolder 可读 lyrics/cover/furi', () async {
    final dir = await Directory.systemTemp.createTemp('utaneko_local_full_');
    addTearDown(() => dir.delete(recursive: true));

    // 夹名用于解析 meta
    final named = Directory(p.join(dir.path, 'Artist - Title'));
    await named.create();
    await File(p.join(named.path, 'audio.mp3')).writeAsBytes([0]);
    await File(p.join(named.path, 'cover.jpg')).writeAsBytes([0, 1]);
    await File(p.join(named.path, 'lyrics.lrc')).writeAsString('[00:01.00]hello');
    await File(p.join(named.path, 'lyrics.trans.lrc'))
        .writeAsString('[00:01.00]你好');
    await File(p.join(named.path, 'furi.txt')).writeAsString('夜[よる]');

    final bundle = await loadLocalSongFolder(named);
    expect(bundle.artists, 'Artist');
    expect(bundle.title, 'Title');
    expect(bundle.coverPath, isNotNull);
    expect(bundle.lrcRaw, contains('hello'));
    expect(bundle.translatedLrc, contains('你好'));
    expect(bundle.furiTxt, contains('夜'));
  });

  test('loadLocalSongFolder 无音频时报错', () async {
    final dir = await Directory.systemTemp.createTemp('utaneko_local_empty_');
    addTearDown(() => dir.delete(recursive: true));
    await File(p.join(dir.path, 'readme.txt')).writeAsString('x');

    expect(
      () => loadLocalSongFolder(dir),
      throwsA(isA<StateError>()),
    );
  });
}
