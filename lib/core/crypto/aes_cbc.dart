import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-128-CBC + PKCS7，对齐 Node `crypto.createCipheriv('aes-128-cbc', key, IV)`。
/// Phase 1 将基于此实现 weapi 双层加密。
abstract final class AesCbc {
  /// 网易云 weapi 固定 IV（ASCII）。
  static final Uint8List neteaseIv = Uint8List.fromList(utf8.encode('0102030405060708'));

  /// 网易云 weapi 预设密钥（ASCII）。
  static final Uint8List neteasePresetKey =
      Uint8List.fromList(utf8.encode('0CoJUm6Qyw8W8jud'));

  static String encryptToBase64(String plainText, List<int> key, {List<int>? iv}) {
    final keyBytes = Uint8List.fromList(key);
    final ivBytes = Uint8List.fromList(iv ?? neteaseIv);
    if (keyBytes.length != 16) {
      throw ArgumentError('AES-128 需要 16 字节密钥');
    }
    if (ivBytes.length != 16) {
      throw ArgumentError('CBC 需要 16 字节 IV');
    }

    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(keyBytes), ivBytes),
          null,
        ),
      );

    final input = Uint8List.fromList(utf8.encode(plainText));
    final out = cipher.process(input);
    return base64Encode(out);
  }
}
