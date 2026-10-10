import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/furigana/furigana_service.dart';
import '../../core/furigana/kuromoji_loader.dart';

/// 词典首次下载时弹出进度。可以取消，取消会停掉下载并删掉未完成的文件。
Future<void> showDictDownloadDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DictDownloadDialog(),
  );
}

class _DictDownloadDialog extends ConsumerStatefulWidget {
  const _DictDownloadDialog();

  @override
  ConsumerState<_DictDownloadDialog> createState() => _DictDownloadDialogState();
}

class _DictDownloadDialogState extends ConsumerState<_DictDownloadDialog> {
  var _closing = false;

  void _closeOnce() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final furi = ref.watch(furiganaServiceProvider);

    ref.listen(furiganaServiceProvider, (prev, next) {
      if (next.dictStatus != DictStatus.downloading &&
          prev?.dictStatus == DictStatus.downloading) {
        _closeOnce();
      }
    });

    if (furi.dictStatus != DictStatus.downloading && !_closing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeOnce());
    }

    final pct = (furi.dictProgress * 100).clamp(0, 100).round();
    final label = furi.dictFileLabel ?? '下载注音词典…';
    final total = furi.dictTotalBytes;
    final sizeText = total == null ? '' : '（${formatDictMb(total)}）';
    final gotText = total == null
        ? ''
        : ' · ${formatDictMb((total * furi.dictProgress).round())} / ${formatDictMb(total)}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(furiganaServiceProvider.notifier).cancelDownload();
        }
      },
      child: AlertDialog(
        title: const Text('下载注音词典'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '首次使用需从网络下载 IPADIC 词典$sizeText，完成后会保存在本机。播放不受影响。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: furi.dictProgress > 0 ? furi.dictProgress.clamp(0, 1) : null,
              ),
              const SizedBox(height: 12),
              Text('$pct%$gotText · $label', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ref.read(furiganaServiceProvider.notifier).cancelDownload(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 在页面里监听：进入 downloading 时自动弹窗（防重复）。
mixin DictDownloadDialogListener<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  var dictDialogShowing = false;

  void listenDictDownloadDialog() {
    ref.listen(furiganaServiceProvider, (prev, next) {
      if (next.dictStatus == DictStatus.downloading &&
          prev?.dictStatus != DictStatus.downloading &&
          !dictDialogShowing &&
          mounted) {
        dictDialogShowing = true;
        showDictDownloadDialog(context).whenComplete(() {
          dictDialogShowing = false;
        });
      }
    });
  }
}
