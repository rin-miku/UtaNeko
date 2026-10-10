import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dict/tomoshi_dict.dart';
import '../../core/furigana/kuromoji_loader.dart';

/// 查词词典未就绪时弹出进度。可以取消，取消会停掉下载并删掉未完成的文件。
Future<void> showTomoshiDownloadDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _TomoshiDownloadDialog(),
  );
}

class _TomoshiDownloadDialog extends ConsumerStatefulWidget {
  const _TomoshiDownloadDialog();

  @override
  ConsumerState<_TomoshiDownloadDialog> createState() =>
      _TomoshiDownloadDialogState();
}

class _TomoshiDownloadDialogState extends ConsumerState<_TomoshiDownloadDialog> {
  var _closing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && !_closing) {
        ref.read(tomoshiDictProvider.notifier).download();
      }
    });
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    try {
      await ref.read(tomoshiDictProvider.notifier).cancel();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dict = ref.watch(tomoshiDictProvider);
    final busy = dict.status == TomoshiStatus.downloading ||
        dict.status == TomoshiStatus.unknown;
    final total = dict.totalBytes;
    final sizeText = total == null ? '' : '（${formatDictMb(total)}）';
    final pct = (dict.progress * 100).clamp(0, 100).round();
    final gotText = total == null || dict.progress <= 0 || dict.progress >= 0.8
        ? ''
        : ' · ${formatDictMb((total * dict.progress / 0.8).round())} / ${formatDictMb(total)}';

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        title: Text(busy ? '下载查词词典' : '查词词典'),
        content: SizedBox(
          width: 320,
          child: busy ? _busy(sizeText, pct, gotText, dict) : _done(dict),
        ),
        actions: [
          if (busy)
            TextButton(onPressed: _cancel, child: const Text('取消'))
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
        ],
      ),
    );
  }

  Widget _busy(String sizeText, int pct, String gotText, TomoshiDictState dict) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '首次查词需从 GitHub 下载日中词典$sizeText，解压后保存在本机。'
          '释义来自 JMdict（EDRDG）与 Tomoshi（Y1Z）。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: dict.progress > 0 ? dict.progress.clamp(0, 1) : null,
        ),
        const SizedBox(height: 12),
        Text(
          '$pct%$gotText · ${dict.label ?? '准备下载…'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _done(TomoshiDictState dict) {
    final ok = dict.status == TomoshiStatus.ready;
    return Text(
      ok ? '词典已准备好，请重新划词。' : (dict.error ?? '词典下载失败'),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
