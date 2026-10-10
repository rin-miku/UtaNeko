import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';

import '../../core/storage/cookie_store.dart';
import '../auth/source_auth.dart';

final kugouAuthProvider = Provider<SourceAuth>((ref) {
  return KugouAuth(ref.watch(kugouCookieStoreProvider));
});

/// 酷狗网页扫码：`/v2/qrcode` 出码，确认后把 `token` / `userid` 写入本机。
class KugouAuth extends SourceAuth {
  KugouAuth(this._cookies, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {
                  'User-Agent': _ua,
                  'Referer': 'https://www.kugou.com/',
                },
                validateStatus: _ok,
              ),
            );

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const _salt = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';

  final CookieStore _cookies;
  final Dio _dio;
  final String _mid = md5Hex('utaneko-kugou');

  @override
  String get sourceId => 'kugou';

  @override
  String get displayName => '酷狗音乐';

  @override
  Future<void> saveManual(String raw) => _cookies.write(raw);

  @override
  Future<void> logout() => _cookies.write('');

  @override
  Stream<QrLoginUpdate> startQrLogin() async* {
    try {
      var refreshed = false;
      while (true) {
        final key = await _createKey();
        final url =
            'https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=$key';
        yield QrLoginUpdate(
          QrPhase.waiting,
          qrUrl: url,
          message: refreshed ? '二维码已刷新，请重新扫码' : null,
        );
        while (true) {
          await Future<void>.delayed(const Duration(seconds: 2));
          final data = await _check(key);
          final status = (data['status'] as num?)?.toInt() ?? -1;
          if (status == 1) continue;
          if (status == 2) {
            yield QrLoginUpdate(QrPhase.scanned, qrUrl: url);
            continue;
          }
          if (status == 4) {
            final token = data['token'];
            final userid = data['userid'];
            if (token == null || userid == null) {
              yield const QrLoginUpdate(
                QrPhase.error,
                message: '已确认登录，但没有取得凭证',
              );
              return;
            }
            await _cookies.write('token=$token; userid=$userid');
            yield const QrLoginUpdate(QrPhase.success);
            return;
          }
          if (status == 0) {
            refreshed = true;
            break;
          }
          yield QrLoginUpdate(QrPhase.error, message: '登录失败（$status）');
          return;
        }
      }
    } on DioException {
      yield const QrLoginUpdate(QrPhase.error, message: '网络异常，请重试');
    } catch (e) {
      yield QrLoginUpdate(QrPhase.error, message: '$e');
    }
  }

  Future<String> _createKey() async {
    final json = await _get('/v2/qrcode', {
      'appid': '1014',
      'type': '1',
      'plat': '4',
      'qrcode_txt':
          'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=1005&',
      'srcappid': '2919',
    });
    final key = json['qrcode'] as String?;
    if (key == null || key.isEmpty) throw StateError('获取二维码失败');
    return key;
  }

  Future<Map<String, dynamic>> _check(String key) {
    return _get('/v2/get_userinfo_qrcode', {
      'plat': '4',
      'appid': '1005',
      'srcappid': '2919',
      'qrcode': key,
    });
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> extra,
  ) async {
    final params = {
      'dfid': '-',
      'mid': _mid,
      'uuid': '-',
      'clientver': '20489',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      ...extra,
    };
    params['signature'] = kugouWebSign(params);
    final res = await _dio.get<dynamic>(
      'https://login-user.kugou.com$path',
      queryParameters: params,
    );
    final body = res.data;
    final json = body is Map
        ? Map<String, dynamic>.from(body)
        : Map<String, dynamic>.from(jsonDecode(body as String) as Map);
    final data = json['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return json;
  }
}

bool _ok(int? status) => status != null && status < 500;

/// Web 签名：盐 + 按 `key=value` 排序拼接 + 盐，再 MD5。
String kugouWebSign(Map<String, String> params) {
  final joined = params.keys.map((k) => '$k=${params[k]}').toList()..sort();
  return md5Hex('${KugouAuth._salt}${joined.join()}${KugouAuth._salt}');
}

String md5Hex(String input) {
  final out = MD5Digest().process(Uint8List.fromList(utf8.encode(input)));
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
