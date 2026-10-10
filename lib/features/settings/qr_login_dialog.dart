import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../sources/auth/source_auth.dart';

/// 各源共用的扫码弹窗，只依赖 [SourceAuth]。
class QrLoginDialog extends StatefulWidget {
  const QrLoginDialog({super.key, required this.auth});

  final SourceAuth auth;

  @override
  State<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<QrLoginDialog> {
  StreamSubscription<QrLoginUpdate>? _sub;
  QrLoginUpdate? _update;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.auth.startQrLogin().listen((update) {
      if (!mounted) return;
      if (update.phase == QrPhase.success) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _update = update);
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    final url = update?.qrUrl;
    final image = update?.qrImage;
    final failed = update?.phase == QrPhase.error;
    final colors = Theme.of(context).colorScheme;
    final name = widget.auth.displayName;

    return AlertDialog(
      title: Text('扫码登录$name'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null)
              ColoredBox(
                color: Colors.white,
                child: Image.memory(
                  image,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              )
            else if (url != null)
              ColoredBox(
                color: Colors.white,
                child: QrImageView(
                  data: url,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              )
            else if (!failed)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 12),
            Text(_status(update), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              '扫码用于登录你自己的$name账号，以获取登录凭证（Cookie）。\n'
              '凭证只保存在本机，不会上传。可随时在设置中清除。\n'
              '若不希望扫码，请关闭此窗口，在下方手动填写 Cookie。',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() => _update = null);
                  _listen();
                },
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  String _status(QrLoginUpdate? update) {
    if (update == null) return '正在获取二维码…';
    return switch (update.phase) {
      QrPhase.waiting => update.message ?? widget.auth.scanTip,
      QrPhase.scanned => '已扫码，请在手机上确认',
      QrPhase.success => '登录成功',
      QrPhase.error => update.message ?? '登录失败',
    };
  }
}
