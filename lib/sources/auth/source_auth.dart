import 'dart:typed_data';

/// 各源登录。扫码和手动填写最终都写入该源自己的本机凭证。
abstract class SourceAuth {
  String get sourceId;

  String get displayName;

  /// 二维码下方的等待提示。
  String get scanTip => '请用$displayName App 扫码';

  /// 出码并轮询，直到成功、失败，或调用方取消订阅。
  Stream<QrLoginUpdate> startQrLogin();

  Future<void> saveManual(String raw);

  Future<void> logout();
}

enum QrPhase { waiting, scanned, success, error }

class QrLoginUpdate {
  const QrLoginUpdate(
    this.phase, {
    this.qrUrl,
    this.qrImage,
    this.message,
  });

  final QrPhase phase;

  /// 画成二维码的登录链接。
  final String? qrUrl;

  /// 服务端直接下发的二维码图片（QQ 登录）。
  final Uint8List? qrImage;

  final String? message;
}
