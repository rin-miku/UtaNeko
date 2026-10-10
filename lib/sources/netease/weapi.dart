import 'dart:convert';
import 'dart:math';

import '../../core/crypto/aes_cbc.dart';

/// 网易云 weapi：双层 AES + RSA encSecKey，对齐 server.js。
abstract final class Weapi {
  static const _pubkey = '010001';
  static const _modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

  /// [secretOverride] 仅供单测注入固定 16 位密钥。
  static ({String params, String encSecKey}) encrypt(
    Map<String, dynamic> payload, {
    String? secretOverride,
  }) {
    final text = jsonEncode(payload);
    final secret = secretOverride ?? _randomSecret();
    final params = AesCbc.encryptToBase64(
      AesCbc.encryptToBase64(text, utf8.encode(secret)),
      AesCbc.neteasePresetKey,
    );
    return (params: params, encSecKey: _rsaEncrypt(secret));
  }

  /// 供 Dio 以 Map 发 form-urlencoded（由 Dio 负责 percent-encode）。
  static Map<String, String> formFields(
    Map<String, dynamic> payload, {
    String? secretOverride,
  }) {
    final r = encrypt(payload, secretOverride: secretOverride);
    return {
      'params': r.params,
      'encSecKey': r.encSecKey,
    };
  }

  /// 已编码的 body 字符串（对照 Node / 单测用）。
  static String formBody(
    Map<String, dynamic> payload, {
    String? secretOverride,
  }) {
    final r = encrypt(payload, secretOverride: secretOverride);
    return 'params=${Uri.encodeComponent(r.params)}'
        '&encSecKey=${Uri.encodeComponent(r.encSecKey)}';
  }

  static String _randomSecret() {
    final rnd = Random.secure();
    const hex = '0123456789abcdef';
    return List.generate(16, (_) => hex[rnd.nextInt(16)]).join();
  }

  /// 翻转 secret → UTF-8 hex → RSA(e, n)，结果左侧补零至 256 hex。
  static String _rsaEncrypt(String secret) {
    final reversed = secret.split('').reversed.join();
    final hex = utf8
        .encode(reversed)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final bi = BigInt.parse(hex, radix: 16);
    final n = BigInt.parse(_modulus, radix: 16);
    final e = BigInt.parse(_pubkey, radix: 16);
    var enc = _modPow(bi, e, n).toRadixString(16);
    if (enc.length < 256) enc = enc.padLeft(256, '0');
    return enc;
  }

  static BigInt _modPow(BigInt base, BigInt exp, BigInt mod) {
    var r = BigInt.one;
    var b = base % mod;
    var e = exp;
    while (e > BigInt.zero) {
      if (e.isOdd) r = (r * b) % mod;
      b = (b * b) % mod;
      e >>= 1;
    }
    return r;
  }
}
