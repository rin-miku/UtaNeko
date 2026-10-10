import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_controller.dart';
import '../../app/theme/theme_preference.dart';
import '../../core/dict/tomoshi_dict.dart';
import '../../core/furigana/furigana_service.dart';
import '../../core/storage/lyric_scale.dart';
import '../../core/storage/history_store.dart';
import '../furigana/dict_download_dialog.dart';
import 'hotkey_section.dart';
import 'source_login_section.dart';

/// 设置：主题、Cookie、快捷键（Windows）、关于。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with DictDownloadDialogListener {
  var _tomoshiBytesLoaded = false;
  int? _tomoshiBytes;

  Future<void> _refreshTomoshiBytes() async {
    final n = await ref.read(tomoshiDictProvider.notifier).diskBytes();
    if (!mounted) return;
    setState(() => _tomoshiBytes = n);
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(themeControllerProvider);
    final lyricScale = ref.watch(lyricScaleProvider);
    final colors = context.appColors;
    final furi = ref.watch(furiganaServiceProvider);
    final furiCtrl = ref.read(furiganaServiceProvider.notifier);
    listenDictDownloadDialog();
    if (!_tomoshiBytesLoaded) {
      _tomoshiBytesLoaded = true;
      unawaited(_refreshTomoshiBytes());
    }
    ref.listen(tomoshiDictProvider, (prev, next) {
      if (prev?.status != next.status && next.status != TomoshiStatus.downloading) {
        unawaited(_refreshTomoshiBytes());
      }
    });

    String dictLabel(FuriganaState s) {
      switch (s.dictStatus) {
        case DictStatus.ready:
          return '辞書: 已下载到本机';
        case DictStatus.downloading:
          return '辞書: 下载中 ${(s.dictProgress * 100).round()}%'
              '${s.dictFileLabel != null ? ' · ${s.dictFileLabel}' : ''}';
        case DictStatus.failed:
          return '辞書: 失败 — ${s.dictError ?? ''}';
        case DictStatus.unknown:
          return '辞書: 未下载 · 开启注音或点「重新下载」';
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const ListTile(
            title: Text('外观'),
            subtitle: Text('亮色 / 暗色 / 跟随系统，即时生效'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeModePreference>(
              segments: const [
                ButtonSegment(
                  value: ThemeModePreference.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('亮色'),
                ),
                ButtonSegment(
                  value: ThemeModePreference.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('暗色'),
                ),
                ButtonSegment(
                  value: ThemeModePreference.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('系统'),
                ),
              ],
              selected: {preference},
              onSelectionChanged: (selected) {
                ref
                    .read(themeControllerProvider.notifier)
                    .setPreference(selected.first);
              },
            ),
          ),
          ListTile(
            title: const Text('歌词字号'),
            subtitle: Text(
              '${(lyricScale * 100).round()}% · 歌词、注音、翻译一起缩放',
              style: TextStyle(color: colors.fgDim),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: lyricScale,
              min: lyricScaleMin,
              max: lyricScaleMax,
              divisions: lyricScaleDivisions,
              label: '${(lyricScale * 100).round()}%',
              onChanged: (v) {
                ref.read(lyricScaleProvider.notifier).setScale(v);
              },
            ),
          ),
          const Divider(height: 32),
          const ListTile(
            title: Text('音源登录'),
            subtitle: Text('切换标签查看对应音源的 Cookie'),
          ),
          const SourceLoginTabs(),
          const HotkeySection(),
          const Divider(height: 32),
          ListTile(
            title: const Text('注音词典（IPADIC）'),
            subtitle: Text(dictLabel(furi), style: TextStyle(color: colors.fgDim)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '词典来自 jsDelivr（kuromoji IPADIC），仅存应用目录；加载失败时歌词仍显示原文，不影响播放。',
              style: TextStyle(color: colors.fgDim, fontSize: 12, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: furi.dictStatus == DictStatus.downloading
                      ? null
                      : () async {
                          await furiCtrl.preloadDictionary();
                          if (!context.mounted) return;
                          final s = ref.read(furiganaServiceProvider);
                          if (s.dictStatus == DictStatus.ready) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('词典已就绪')),
                            );
                          }
                        },
                  child: Text(
                    furi.dictStatus == DictStatus.ready ? '校验词典' : '重新下载词典',
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                  ),
                  onPressed: furi.dictStatus == DictStatus.downloading
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除注音词典？'),
                              content: const Text(
                                '将删除本机 IPADIC 文件。下次开启注音时会重新下载。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await furiCtrl.clearDictionary();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('词典已删除')),
                            );
                          }
                        },
                  child: const Text('删除词典'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await furiCtrl.clearTokenCache();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('注音缓存已清空')),
                      );
                    }
                  },
                  child: const Text('清空缓存'),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          ListTile(
            title: const Text('查词词典（Tomoshi）'),
            subtitle: Text(
              _tomoshiBytes == null
                  ? '正在计算占用…'
                  : _tomoshiBytes == 0
                      ? '未下载'
                      : '占用 ${_formatBytes(_tomoshiBytes!)}',
              style: TextStyle(color: colors.fgDim),
            ),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
              ),
              onPressed: (_tomoshiBytes ?? 0) == 0
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('删除查词词典？'),
                          content: const Text('将删除本机日中词典。下次划词查义时会重新下载。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await ref.read(tomoshiDictProvider.notifier).deleteDictionary();
                      await _refreshTomoshiBytes();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('查词词典已删除')),
                        );
                      }
                    },
              child: const Text('删除词典'),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            title: const Text('清除播放历史'),
            subtitle: Text('最多保留 10 首', style: TextStyle(color: colors.fgDim)),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
              ),
              onPressed: () async {
                await ref.read(historyProvider.notifier).clear();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('历史已清除')),
                  );
                }
              },
              child: const Text('清除'),
            ),
          ),
          const Divider(height: 32),
          const ListTile(title: Text('关于')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/icon/icon-utaneko-1024.png',
                      width: 80,
                      height: 80,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Text(
                    'UtaNeko 1.0.1\n© 2026 Replastic.',
                    style: TextStyle(
                      color: colors.fgDim,
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
