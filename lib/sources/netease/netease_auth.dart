import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cookie_store.dart';
import '../auth/source_auth.dart';
import 'eapi.dart';
import 'netease_source.dart';

final neteaseAuthProvider = Provider<SourceAuth>((ref) {
  return NeteaseAuth(ref.watch(cookieStoreProvider));
});

/// 网易云扫码：unikey → 本地二维码 → 轮询，成功后把 Cookie 写入 [CookieStore]。
class NeteaseAuth extends SourceAuth {
  NeteaseAuth(this._cookies, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                headers: const {
                  'User-Agent': _ua,
                  'Referer': 'https://music.163.com/',
                  'Origin': 'https://music.163.com',
                },
                validateStatus: _ok,
              ),
            );

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const _host = 'https://music.163.com';

  final CookieStore _cookies;
  final Dio _dio;
  var _sessionCookie = '';

  @override
  String get sourceId => 'netease';

  @override
  String get displayName => '网易云音乐';

  @override
  Future<void> saveManual(String raw) => _cookies.write(raw);

  @override
  Future<void> logout() => _cookies.write('');

  @override
  Stream<QrLoginUpdate> startQrLogin() async* {
    try {
      final deviceId = 'unknown-${Random().nextInt(1000000)}';
      var refreshed = false;
      while (true) {
        _sessionCookie = 'sDeviceId=$deviceId';
        final key = await _unikey();
        final chainId =
            'v1_${deviceId}_web_login_${DateTime.now().millisecondsSinceEpoch}';
        final url = 'https://music.163.com/login?codekey=$key&chainId=$chainId';
        yield QrLoginUpdate(
          QrPhase.waiting,
          qrUrl: url,
          message: refreshed ? '二维码已刷新，请重新扫码' : null,
        );

        while (true) {
          await Future<void>.delayed(const Duration(seconds: 2));
          final res = await _post('/api/login/qrcode/client/login', {
            'key': key,
            'type': 1,
          });
          final code = (res.json['code'] as num?)?.toInt() ?? -1;
          if (code == 801) continue;
          if (code == 802) {
            yield QrLoginUpdate(QrPhase.scanned, qrUrl: url);
            continue;
          }
          if (code == 803) {
            final cookie = _cookieOf(res);
            if (cookie == null) {
              yield const QrLoginUpdate(
                QrPhase.error,
                message: '已确认登录，但没有取得 Cookie',
              );
              return;
            }
            await _cookies.write(cookie);
            yield const QrLoginUpdate(QrPhase.success);
            return;
          }
          if (code == 800) {
            refreshed = true;
            break;
          }
          yield QrLoginUpdate(
            QrPhase.error,
            message: _failText(res.json, code),
          );
          return;
        }
      }
    } on DioException {
      yield const QrLoginUpdate(QrPhase.error, message: '网络异常，请重试');
    } catch (e) {
      yield QrLoginUpdate(QrPhase.error, message: '$e');
    }
  }

  Future<String> _unikey() async {
    final res = await _post('/api/login/qrcode/unikey', {'type': 1});
    final key = res.json['unikey'] as String?;
    if (key == null || key.isEmpty) {
      throw StateError('获取二维码失败');
    }
    return key;
  }

  Future<({Map<String, dynamic> json, List<String>? setCookies})> _post(
    String apiPath,
    Map<String, dynamic> payload,
  ) async {
    final res = await _dio.post<dynamic>(
      '$_host${apiPath.replaceFirst('/api/', '/eapi/')}',
      data: Eapi.formFields(apiPath, payload),
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          if (_sessionCookie.isNotEmpty) 'Cookie': _sessionCookie,
        },
      ),
    );
    _absorbCookies(res.headers.map['set-cookie']);
    return (
      json: asJsonMap(res.data, httpStatus: res.statusCode),
      setCookies: res.headers.map['set-cookie'],
    );
  }

  void _absorbCookies(List<String>? lines) {
    final incoming = cookiePairsFromSetCookie(lines);
    if (incoming == null) return;
    final map = <String, String>{};
    for (final part in '$_sessionCookie; $incoming'.split(';')) {
      final t = part.trim();
      final i = t.indexOf('=');
      if (i <= 0) continue;
      map[t.substring(0, i)] = t.substring(i + 1);
    }
    _sessionCookie = map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  String _failText(Map<String, dynamic> json, int code) {
    final message = json['message'];
    if (message is String && message.isNotEmpty) return message;
    return '登录失败（$code）';
  }

  String? _cookieOf(
    ({Map<String, dynamic> json, List<String>? setCookies}) res,
  ) {
    final header = cookiePairsFromSetCookie(res.setCookies);
    if (header != null && header.contains('MUSIC_U=')) return header;
    final body = res.json['cookie'];
    if (body is String && body.contains('MUSIC_U=')) return body.trim();
    return null;
  }
}

bool _ok(int? status) => status != null && status < 500;

/// 从 Set-Cookie 取出 `name=value`，丢掉 Path / Domain 等属性。
String? cookiePairsFromSetCookie(List<String>? lines) {
  if (lines == null || lines.isEmpty) return null;
  final pairs = <String>[];
  for (final line in lines) {
    final pair = line.split(';').first.trim();
    if (pair.contains('=')) pairs.add(pair);
  }
  if (pairs.isEmpty) return null;
  return pairs.join('; ');
}
