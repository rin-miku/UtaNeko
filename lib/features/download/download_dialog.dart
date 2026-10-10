import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_service.dart';
import '../../core/furigana/furigana_service.dart';
import '../../core/storage/prefs.dart';
import '../../sources/models.dart';
import '../player/player_controller.dart';

/// 下载弹窗：歌曲夹内音频 / LRC / 封面 / 注音 TXT。
Future<void> showDownloadDialog(BuildContext context, WidgetRef ref) async {
  final player = ref.read(playerControllerProvider);
  final track = player.track;
  if (track == null) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => _DownloadDialogBody(track: track),
  );
}

class _DownloadDialogBody extends ConsumerStatefulWidget {
  const _DownloadDialogBody({required this.track});
  final TrackMeta track;

  @override
  ConsumerState<_DownloadDialogBody> createState() => _DownloadDialogBodyState();
}

class _DownloadDialogBodyState extends ConsumerState<_DownloadDialogBody> {
  var _audio = true;
  var _lrc = true;
  var _cover = true;
  var _furiTxt = true;
  var _busy = false;
  String? _status;
  double? _progress;

  bool get _anySelected => _audio || _lrc || _cover || _furiTxt;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final qLabel = player.quality.label;
    final level = player.levelInfo;

    return AlertDialog(
      title: const Text('下载到本机'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.track.artists.isNotEmpty ? '${widget.track.artists} — ' : ''}${widget.track.title}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '音质: $qLabel${level != null ? ' · $level' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '将保存到「歌手 - 歌名」子文件夹',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _audio,
              onChanged: _busy ? null : (v) => setState(() => _audio = v ?? true),
              title: const Text('音频'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _lrc,
              onChanged: _busy ? null : (v) => setState(() => _lrc = v ?? true),
              title: const Text('歌词 lyrics.lrc（有翻译则另存 lyrics.trans.lrc）'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _cover,
              onChanged: _busy ? null : (v) => setState(() => _cover = v ?? true),
              title: const Text('封面图'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: _furiTxt,
              onChanged:
                  _busy ? null : (v) => setState(() => _furiTxt = v ?? true),
              title: const Text('注音 furi.txt（可编辑）'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress!.clamp(0, 1)),
            ],
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _pickDir,
          child: const Text('选择目录'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _busy || !_anySelected ? null : _start,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('开始'),
        ),
      ],
    );
  }

  Future<void> _pickDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择下载目录');
    if (path == null || !mounted) return;
    await ref.read(sharedPreferencesProvider).setString(kDownloadDirPrefKey, path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存目录: $path')),
      );
    }
  }

  Future<Directory?> _rootDir() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final customDir = prefs.getString(kDownloadDirPrefKey);
    if (customDir != null && customDir.isNotEmpty) {
      final dir = Directory(customDir);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    return null;
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _status = '准备中…';
      _progress = null;
    });

    final svc = DownloadService();
    final dir = await _rootDir();
    final songDir = await svc.songFolder(
      widget.track,
      dir ?? await svc.defaultSaveDir(),
    );

    final ctrl = ref.read(playerControllerProvider.notifier);
    final player = ref.read(playerControllerProvider);
    final furigana = ref.read(furiganaServiceProvider.notifier);
    final results = <String>[];

    try {
      if (_furiTxt) {
        setState(() => _status = '注音分词…');
        await furigana.ensureForTrack(
          widget.track.id,
          player.lines,
          force: true,
        );
      }

      if (_audio) {
        final url = await ctrl.resolvePlayUrlForDownload();
        if (url == null) throw StateError('无法获取下载地址');
        setState(() => _status = '下载音频…');
        final path = await svc.downloadAudio(
          meta: widget.track,
          url: url,
          quality: player.quality,
          dir: songDir,
          headers: ref.read(musicSourceProvider).mediaHeaders,
          onProgress: (p) => setState(() => _progress = p),
        );
        results.add(path);
      }

      if (_lrc) {
        setState(() {
          _status = '保存 LRC…';
          _progress = null;
        });
        final raw = ctrl.lrcRaw;
        if (raw == null || raw.isEmpty) throw StateError('无歌词可保存');
        results.add(
          await svc.saveLrc(meta: widget.track, lrcRaw: raw, dir: songDir),
        );
        final trans = ctrl.translatedLrc;
        if (trans != null && trans.trim().isNotEmpty) {
          final transPath = await svc.saveTranslatedLrc(
            meta: widget.track,
            translatedLrc: trans,
            dir: songDir,
          );
          if (transPath != null) results.add(transPath);
        }
      }

      if (_cover) {
        setState(() => _status = '下载封面…');
        results.add(await svc.saveCover(meta: widget.track, dir: songDir));
      }

      if (_furiTxt) {
        final furiState = ref.read(furiganaServiceProvider);
        final tokens = furiState.tokens;
        if (tokens == null || tokens.length != player.lines.length) {
          throw StateError('注音未就绪');
        }
        setState(() => _status = '导出注音 TXT…');
        results.add(
          await svc.saveFuriTxt(
            meta: widget.track,
            tokens: tokens,
            dir: songDir,
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存 ${results.length} 个文件\n${songDir.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '失败: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }
}
