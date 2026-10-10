import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/core/crypto/aes_cbc.dart';

/// 与 utasensei-main/server.js 的 aesEnc 对照（同明文 / 密钥 / IV → 同 Base64）。
void main() {
  const plain = '{"ids":["123"],"br":320000}';
  final iv = utf8.encode('0102030405060708');

  test('AES-128-CBC 与 Node aesEnc 一致（随机密钥样例）', () {
    final key = utf8.encode('0123456789abcdef');
    final actual = AesCbc.encryptToBase64(plain, key, iv: iv);
    expect(actual, 'gfW7AiH90fP0lWiDaFKPm1wpgK3Lhn84O91h/sPfSWs=');
  });

  test('AES-128-CBC 与 Node aesEnc 一致（weapi PRESET_KEY）', () {
    final actual = AesCbc.encryptToBase64(
      plain,
      AesCbc.neteasePresetKey,
      iv: AesCbc.neteaseIv,
    );
    expect(actual, '1+NZF/yrkxhnaUjjrpQw8IelLyARY8YG6+kg0UFjyfE=');
  });
}
