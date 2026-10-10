import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 网易云 eapi。扫码登录的 weapi 现在会返回空正文，需走这条。
abstract final class Eapi {
  static const _key = 'e82ckenh8dichen8';

  /// [apiPath] 形如 `/api/login/qrcode/unikey`，参与摘要，不直接当请求地址。
  static Map<String, String> formFields(
    String apiPath,
    Map<String, dynamic> payload,
  ) {
    final text = jsonEncode(payload);
    final digest = _md5('nobody${apiPath}use${text}md5forencrypt');
    final data = '$apiPath-36cd479b6b5-$text-36cd479b6b5-$digest';
    return {'params': _aesEcbHex(data)};
  }

  static String _md5(String input) {
    final out = MD5Digest().process(Uint8List.fromList(utf8.encode(input)));
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _aesEcbHex(String plain) {
    final key = Uint8List.fromList(utf8.encode(_key));
    final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters(KeyParameter(key), null),
      );
    final out = cipher.process(Uint8List.fromList(utf8.encode(plain)));
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }
}
