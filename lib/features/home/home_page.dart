import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/theme/app_colors.dart';
import '../../core/download/download_service.dart';
import '../../core/furigana/furi_txt.dart';
import '../../core/furigana/furigana_service.dart';
import '../../core/local/local_song_folder.dart';
import '../../core/storage/history_store.dart';
import '../../core/storage/lyric_scale.dart';
import '../../core/storage/prefs.dart';
import '../../core/window/app_window_chrome.dart';
import '../../sources/models.dart';
import '../download/download_dialog.dart';
import '../furigana/dict_download_dialog.dart';
import '../mini/mini_mode_controller.dart';
import '../player/lyric_lookup_page.dart';
import '../player/lyric_panel.dart';
import '../player/player_controller.dart';

/// 远程 URL 用网络图；本地路径用文件图。
ImageProvider? coverImageProvider(String coverUrl) {
  if (coverUrl.isEmpty) return null;
  if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
    return NetworkImage(coverUrl);
  }
  final file = File(coverUrl);
  if (file.existsSync()) return FileImage(file);
  return null;
}

Widget coverImageWidget(String coverUrl, {BoxFit fit = BoxFit.cover}) {
  final provider = coverImageProvider(coverUrl);
  if (provider == null) {
    return const ColoredBox(
      color: Color(0x22000000),
      child: Icon(Icons.album_outlined, size: 36),
    );
  }
  return Image(image: provider, fit: fit);
}

bool get _showVolume => defaultTargetPlatform == TargetPlatform.windows;

/// 播放主页：粘贴链接 → 播放 → 歌词。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with DictDownloadDialogListener {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider);
    final furi = ref.watch(furiganaServiceProvider);
    final colors = context.appColors;
    final ctrl = ref.read(playerControllerProvider.notifier);
    final furiCtrl = ref.read(furiganaServiceProvider.notifier);

    listenDictDownloadDialog();

    ref.listen(playerControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }

      // 切歌时只清 tokens，不立刻跑重活
      final id = next.track?.id;
      if (id != null && id != prev?.track?.id) {
        furiCtrl.prepareForTrack(id);
      }

      // 播放链路完成（loading false）后再注音，与播歌并行、不抢事件循环
      final playReady = prev?.loading == true &&
          next.loading == false &&
          next.track != null &&
          next.lines.isNotEmpty &&
          next.error == null;
      if (playReady) {
        final pending = ctrl.takePendingFuriTxt();
        if (pending != null && pending.trim().isNotEmpty) {
          // 本地 furi.txt：导入并写缓存，跳过自动分词
          final trackId = next.track!.id;
          final lines = next.lines;
          unawaited(() async {
            try {
              await furiCtrl.importFuriTxtText(
                trackId: trackId,
                lineCount: lines.length,
                raw: pending,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('本地注音导入失败: $e')),
                );
              }
            }
          }());
        } else {
          // fire-and-forget：绝不 await，避免听回调卡住
          furiCtrl.onTrackChanged(next.track!.id, next.lines);
        }
      }
    });

    ref.listen(furiganaServiceProvider, (prev, next) {
      if (next.dictError != null && next.dictError != prev?.dictError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('注音词典: ${next.dictError}（已显示原文）')),
        );
      }
    });

    // Windows：自绘标题栏已有品牌，去掉空 AppBar；
    // Android：品牌栏右侧放下载 / 历史 / 设置（无窗口按钮）。
    final canDownload =
        state.track != null && !isLocalTrackId(state.track!.id);
    final sourceId = ref.watch(selectedSourceIdProvider);
    return Scaffold(
      appBar: supportsCustomWindowChrome
          ? null
          : AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/icon/icon-utaneko-1024.png', width: 28, height: 28),
                  const SizedBox(width: 8),
                  const Text('UtaNeko'),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: '下载',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: canDownload
                      ? () => showDownloadDialog(context, ref)
                      : null,
                ),
                IconButton(
                  tooltip: '历史记录',
                  icon: const Icon(Icons.history_outlined),
                  onPressed: () => _showHistoryDialog(context, ref),
                ),
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                _SourcePicker(
                  value: sourceId,
                  onChanged: (id) =>
                      ref.read(selectedSourceIdProvider.notifier).set(id),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: InputDecoration(
                      hintText: _hintForSource(sourceId),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _go(),
                    textInputAction: TextInputAction.go,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state.loading ? null : _go,
                  child: state.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('播放'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state.loading ? null : _openLocalFolder,
                  child: const Text('本地'),
                ),
              ],
            ),
          ),
          if (state.trialHint != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                state.trialHint!,
                style: TextStyle(color: colors.danger, fontSize: 12),
              ),
            ),
          _MetaHeader(state: state),
          _TransportBar(showVolume: _showVolume),
          const SizedBox(height: 4),
          Expanded(
            child: LyricPanel(
              scale: ref.watch(lyricScaleProvider),
              lines: state.lines,
              activeIndex: state.lyricIndex,
              showTranslation: state.showTranslation,
              onTapLine: ctrl.seekLyric,
              onLongPressLine: (i) {
                final lines = state.lines;
                if (i < 0 || i >= lines.length) return;
                final tokenLines = furiCtrl.tokensForLines(lines.length);
                final toks =
                    i < tokenLines.length ? tokenLines[i] : null;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LyricLookupPage(
                      line: lines[i],
                      showTranslation: state.showTranslation,
                      tokens: toks,
                    ),
                  ),
                );
              },
              showFurigana: furi.enabled,
              tokenLines: furiCtrl.tokensForLines(state.lines.length),
            ),
          ),
        ],
      ),
    );
  }

  void _go() {
    ref.read(playerControllerProvider.notifier).resolveAndPlay(_input.text);
  }

  Future<void> _openLocalFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择歌曲文件夹');
    if (path == null || !mounted) return;
    await ref.read(playerControllerProvider.notifier).playLocalFolder(Directory(path));
  }
}

String _hintForSource(String sourceId) {
  switch (sourceId) {
    case 'qq':
      return '粘贴 QQ 链接（songid）或分享短链';
    case 'kugou':
      return '粘贴酷狗分享链接（chain= 或 /share/xxx.html）';
    case 'netease':
    default:
      return '粘贴网易云链接或歌曲 ID';
  }
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _items = [
    ('netease', '网易云'),
    ('qq', 'QQ音乐'),
    ('kugou', '酷狗'),
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        borderRadius: BorderRadius.circular(8),
        items: [
          for (final (id, label) in _items)
            DropdownMenuItem(value: id, child: Text(label)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

void _showHistoryDialog(BuildContext context, WidgetRef ref) {
  final items = ref.read(historyProvider).take(10).toList();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('历史记录'),
      content: SizedBox(
        width: 360,
        child: items.isEmpty
            ? const Text('暂无播放历史')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = items[i];
                    final cover = coverImageProvider(t.coverUrl);
                    return ListTile(
                      leading: cover != null
                          ? CircleAvatar(backgroundImage: cover)
                          : const CircleAvatar(
                              child: Icon(Icons.music_note, size: 16),
                            ),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(t.artists, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        ref.read(playerControllerProvider.notifier).playTrack(t);
                      },
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 封面 + 曲目信息；Windows 右侧放 Mini / 下载 / 历史 / 设置（2×2）。
/// Android 这些入口已在 AppBar.actions，此处不再重复。
class _MetaHeader extends ConsumerWidget {
  const _MetaHeader({required this.state});
  final PlayerViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.track;
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, supportsCustomWindowChrome ? 8 : 16, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 72,
              height: 72,
              child: track?.coverUrl.isNotEmpty == true
                  ? coverImageWidget(track!.coverUrl)
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.album_outlined, size: 36),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? '尚未播放',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  track == null
                      ? '粘贴链接或打开本地文件夹'
                      : [
                          track.artists,
                          track.album,
                        ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: colors.fgDim, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (supportsCustomWindowChrome)
            _MetaActions(
              canDownload: track != null && !isLocalTrackId(track.id),
            ),
        ],
      ),
    );
  }
}

class _MetaActions extends ConsumerWidget {
  const _MetaActions({required this.canDownload});
  final bool canDownload;

  static const _btnConstraints = BoxConstraints.tightFor(width: 40, height: 40);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget btn({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 24),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: _btnConstraints,
        onPressed: onPressed,
      );
    }

    return SizedBox(
      height: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(
                tooltip: '下载',
                icon: Icons.download_outlined,
                onPressed:
                    canDownload ? () => showDownloadDialog(context, ref) : null,
              ),
              if (supportsMiniMode)
                btn(
                  tooltip: 'Mini 歌词窗',
                  icon: Icons.picture_in_picture_alt_outlined,
                  onPressed: () async {
                    try {
                      await ref.read(miniModeProvider.notifier).enterMini();
                      if (!context.mounted) return;
                      context.go('/mini');
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('进入 Mini 失败: $e')),
                      );
                    }
                  },
                ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(
                tooltip: '历史记录',
                icon: Icons.history_outlined,
                onPressed: () => _showHistoryDialog(context, ref),
              ),
              btn(
                tooltip: '设置',
                icon: Icons.settings_outlined,
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransportBar extends ConsumerWidget {
  const _TransportBar({required this.showVolume});
  final bool showVolume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final furi = ref.watch(furiganaServiceProvider);
    final ctrl = ref.read(playerControllerProvider.notifier);
    final player = ctrl.player;
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: player.durationStream,
                builder: (context, dSnap) {
                  final dur = dSnap.data ?? Duration.zero;
                  final maxMs =
                      dur.inMilliseconds < 1 ? 1.0 : dur.inMilliseconds.toDouble();
                  final value = pos.inMilliseconds
                      .clamp(0, maxMs.round())
                      .toDouble();
                  return Column(
                    children: [
                      Slider(
                        value: value,
                        max: maxMs,
                        onChanged: (v) =>
                            ctrl.seek(Duration(milliseconds: v.round())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(pos),
                                style: TextStyle(color: colors.fgDim, fontSize: 11)),
                            Text(_fmt(dur),
                                style: TextStyle(color: colors.fgDim, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, snap) {
                    final playing = snap.data?.playing ?? false;
                    return IconButton.filled(
                      onPressed: () => ctrl.togglePlay(),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    );
                  },
                ),
                if (showVolume) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.volume_up, size: 18),
                  SizedBox(
                    width: 96,
                    child: StreamBuilder<double>(
                      stream: player.volumeStream,
                      builder: (context, snap) {
                        final v = (snap.data ?? 1.0).clamp(0.0, 1.0);
                        return Slider(
                          value: v,
                          onChanged: ctrl.setVolume,
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                _QualityMenu(
                  quality: state.quality,
                  onSelected: (q) => ctrl.setQuality(q),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('翻译'),
                  selected: state.showTranslation,
                  onSelected: ctrl.setShowTranslation,
                ),
                const SizedBox(width: 6),
                _FuriChipWithMenu(furi: furi, state: state),
                if (state.levelInfo != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    state.levelInfo!,
                    style: TextStyle(color: colors.fgDim, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 注音开关 + 导出/打开菜单。
class _FuriChipWithMenu extends ConsumerWidget {
  const _FuriChipWithMenu({required this.furi, required this.state});

  final FuriganaState furi;
  final PlayerViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final furiCtrl = ref.read(furiganaServiceProvider.notifier);
    final canFileOps = state.track != null && state.lines.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          label: Text(
            furi.tokenizing
                ? '注音…'
                : furi.dictStatus == DictStatus.downloading
                    ? '辞書 ${(furi.dictProgress * 100).round()}%'
                    : '注音',
          ),
          selected: furi.enabled,
          onSelected: (v) async {
            if (!v) {
              await furiCtrl.setEnabled(false);
              return;
            }
            // 无词典时先下载，完成后再启用并分词。
            await furiCtrl.requestEnable(
              trackId: state.track?.id,
              lines: state.lines,
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: '注音文件',
          enabled: canFileOps,
          padding: EdgeInsets.zero,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelected: (action) async {
            if (action == 'export') {
              await _exportFuri(context, ref);
            } else if (action == 'import') {
              await _importFuri(context, ref);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'export', child: Text('导出注音')),
            PopupMenuItem(value: 'import', child: Text('打开注音文件')),
          ],
          child: const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.arrow_drop_down, size: 20),
          ),
        ),
      ],
    );
  }

  Future<void> _exportFuri(BuildContext context, WidgetRef ref) async {
    final track = state.track;
    if (track == null || state.lines.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final furiCtrl = ref.read(furiganaServiceProvider.notifier);
      await furiCtrl.ensureForTrack(track.id, state.lines, force: true);
      final tokens = ref.read(furiganaServiceProvider).tokens;
      if (tokens == null || tokens.length != state.lines.length) {
        throw StateError('注音未就绪');
      }

      final svc = DownloadService();
      final prefs = ref.read(sharedPreferencesProvider);
      final custom = prefs.getString(kDownloadDirPrefKey);
      final root = (custom != null && custom.isNotEmpty)
          ? Directory(custom)
          : await svc.defaultSaveDir();
      if (!await root.exists()) await root.create(recursive: true);
      final songDir = await svc.songFolder(track, root);
      final path = await svc.saveFuriTxt(
        meta: track,
        tokens: tokens,
        dir: songDir,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('已导出注音\n$path'), duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _importFuri(BuildContext context, WidgetRef ref) async {
    final track = state.track;
    if (track == null || state.lines.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: true,
        dialogTitle: '打开注音文件',
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String raw;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        raw = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        raw = await File(file.path!).readAsString();
      } else {
        throw StateError('无法读取所选文件');
      }

      await ref.read(furiganaServiceProvider.notifier).importFuriTxtText(
            trackId: track.id,
            lineCount: state.lines.length,
            raw: raw,
          );
      messenger.showSnackBar(const SnackBar(content: Text('注音已导入并保存')));
    } on FuriImportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }
}

class _QualityMenu extends StatelessWidget {
  const _QualityMenu({required this.quality, required this.onSelected});

  final AudioQuality quality;
  final ValueChanged<AudioQuality> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<AudioQuality>(
      key: ValueKey(quality),
      initialSelection: quality,
      width: 108,
      requestFocusOnTap: false,
      textStyle: const TextStyle(fontSize: 13),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8),
        constraints: BoxConstraints(maxHeight: 40, minHeight: 40),
      ),
      dropdownMenuEntries: [
        for (final q in AudioQuality.values)
          DropdownMenuEntry(value: q, label: q.label),
      ],
      onSelected: (q) {
        if (q != null) onSelected(q);
      },
    );
  }
}

