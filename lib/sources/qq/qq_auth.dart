import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/cookie_store.dart';
import '../auth/source_auth.dart';

final qqAuthProvider = Provider<SourceAuth>((ref) {
  return QqAuth(ref.watch(qqCookieStoreProvider));
});

/// QQ 音乐网页扫码：QQ 互联出码，确认后换成 `qqmusic_key` 写入本机。
class QqAuth extends SourceAuth {
  QqAuth(this._cookies, {Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {
                  'User-Agent': _ua,
                  'Referer': 'https://xui.ptlogin2.qq.com/',
                },
                validateStatus: _ok,
              ),
            );

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final CookieStore _cookies;
  final Dio _dio;

  @override
  String get sourceId => 'qq';

  @override
  String get displayName => 'QQ 音乐';

  @override
  String get scanTip => '请用手机 QQ 扫码';

  @override
  Future<void> saveManual(String raw) => _cookies.write(raw);

  @override
  Future<void> logout() => _cookies.write('');

  @override
  Stream<QrLoginUpdate> startQrLogin() async* {
    try {
      var refreshed = false;
      while (true) {
        final issued = await _issue();
        yield QrLoginUpdate(
          QrPhase.waiting,
          qrImage: issued.image,
          message: refreshed ? '二维码已刷新，请重新扫码' : null,
        );
        while (true) {
          await Future<void>.delayed(const Duration(seconds: 2));
          final status = await _poll(issued.qrsig);
          final code = status.code;
          if (code == 66) continue;
          if (code == 67) {
            yield QrLoginUpdate(QrPhase.scanned, qrImage: issued.image);
            continue;
          }
          if (code == 0) {
            final cookie = await _exchange(status.jumpUrl);
            await _cookies.write(cookie);
            yield const QrLoginUpdate(QrPhase.success);
            return;
          }
          if (code == 65) {
            refreshed = true;
            break;
          }
          if (code == 68) {
            yield const QrLoginUpdate(QrPhase.error, message: '已取消登录');
            return;
          }
          yield QrLoginUpdate(
            QrPhase.error,
            message: status.message ?? '登录失败（$code）',
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

  Future<({Uint8List image, String qrsig})> _issue() async {
    final res = await _dio.get<List<int>>(
      'https://ssl.ptlogin2.qq.com/ptqrshow',
      queryParameters: const {
        'appid': '716027609',
        'e': '2',
        'l': 'M',
        's': '3',
        'd': '72',
        'v': '4',
        't': '0.5',
        'daid': '383',
        'pt_3rd_aid': '100497308',
      },
      options: Options(responseType: ResponseType.bytes),
    );
    final qrsig = _cookieValue(res.headers.map['set-cookie'], 'qrsig');
    final bytes = res.data;
    if (qrsig == null || bytes == null || bytes.isEmpty) {
      throw StateError('获取二维码失败');
    }
    return (image: Uint8List.fromList(bytes), qrsig: qrsig);
  }

  Future<({int code, String? jumpUrl, String? message})> _poll(
    String qrsig,
  ) async {
    final res = await _dio.get<String>(
      'https://ssl.ptlogin2.qq.com/ptqrlogin',
      queryParameters: {
        'u1': 'https://graph.qq.com/oauth2.0/login_jump',
        'ptqrtoken': '${hash33(qrsig)}',
        'ptredirect': '0',
        'h': '1',
        't': '1',
        'g': '1',
        'from_ui': '1',
        'ptlang': '2052',
        'action': '0-0-${DateTime.now().millisecondsSinceEpoch}',
        'js_ver': '20102616',
        'js_type': '1',
        'pt_uistyle': '40',
        'aid': '716027609',
        'daid': '383',
        'pt_3rd_aid': '100497308',
        'has_onekey': '1',
      },
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Cookie': 'qrsig=$qrsig'},
      ),
    );
    return _parsePtui(res.data ?? '');
  }

  Future<String> _exchange(String? jumpUrl) async {
    if (jumpUrl == null || jumpUrl.isEmpty) {
      throw StateError('已确认登录，但没有取得跳转地址');
    }
    final jump = Uri.parse(jumpUrl);
    final sigx = jump.queryParameters['ptsigx'];
    final uin = jump.queryParameters['uin'];
    if (sigx == null || uin == null) {
      throw StateError('已确认登录，但没有取得凭证');
    }

    final check = await _dio.get<String>(
      'https://ssl.ptlogin2.graph.qq.com/check_sig',
      queryParameters: {
        'uin': uin,
        'pttype': '1',
        'service': 'ptqrlogin',
        'nodirect': '0',
        'ptsigx': sigx,
        's_url': 'https://graph.qq.com/oauth2.0/login_jump',
        'ptlang': '2052',
        'ptredirect': '100',
        'aid': '716027609',
        'daid': '383',
        'j_later': '0',
        'low_login_hour': '0',
        'regmaster': '0',
        'pt_login_type': '3',
        'pt_aid': '0',
        'pt_aaid': '16',
        'pt_light': '0',
        'pt_3rd_aid': '100497308',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final session = _pairs(check.headers.map['set-cookie']);
    final pSkey = _one(session, 'p_skey');
    if (pSkey == null) throw StateError('已确认登录，但没有取得 p_skey');

    final auth = await _dio.post<String>(
      'https://graph.qq.com/oauth2.0/authorize',
      data: {
        'response_type': 'code',
        'client_id': '100497308',
        'redirect_uri':
            'https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/',
        'scope': 'get_user_info,get_app_friends',
        'state': 'state',
        'switch': '',
        'from_ptlogin': '1',
        'src': '1',
        'update_auth': '1',
        'openapi': '1010_1030',
        'g_tk': '${hash33(pSkey, 5381)}',
        'auth_time': '${DateTime.now().millisecondsSinceEpoch}',
        'ui': '${DateTime.now().microsecondsSinceEpoch}',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
        headers: {'Cookie': session, 'Referer': 'https://graph.qq.com/'},
      ),
    );
    final location = auth.headers.value('location') ?? '';
    final code = Uri.tryParse(location)?.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('已确认登录，但没有取得授权码');
    }

    final login = await _dio.post<dynamic>(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      data: {
        'comm': {
          'g_tk': 5381,
          'uin': 0,
          'format': 'json',
          'ct': 24,
          'cv': 0,
          'tmeLoginType': 2,
        },
        'req_0': {
          'module': 'QQConnectLogin.LoginServer',
          'method': 'QQLogin',
          'param': {'code': code},
        },
      },
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Referer': 'https://y.qq.com/',
          'Origin': 'https://y.qq.com',
        },
      ),
    );
    final root = login.data is Map
        ? Map<String, dynamic>.from(login.data as Map)
        : Map<String, dynamic>.from(jsonDecode('${login.data}') as Map);
    final req = root['req_0'];
    final data = req is Map ? req['data'] : null;
    if (data is! Map) throw StateError('登录成功，但没有取得音乐凭证');
    final musicid = data['musicid'] ?? data['str_musicid'];
    final musickey = data['musickey'];
    if (musicid == null || musickey == null) {
      throw StateError('登录成功，但没有取得音乐凭证');
    }
    return 'uin=$musicid; qqmusic_key=$musickey; qm_keyst=$musickey';
  }
}

bool _ok(int? status) => status != null && status < 500;

({int code, String? jumpUrl, String? message}) _parsePtui(String text) {
  final call = RegExp(r'ptuiCB\((.*)\)').firstMatch(text);
  if (call == null) throw StateError('无法识别扫码状态');
  final args = RegExp(r"'((?:\\.|[^'])*)'")
      .allMatches(call.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
  if (args.isEmpty) throw StateError('无法识别扫码状态');
  return (
    code: int.tryParse(args[0]) ?? -1,
    jumpUrl: args.length > 2 ? args[2] : null,
    message: args.length > 4 ? args[4] : null,
  );
}

String? _cookieValue(List<String>? lines, String name) {
  final pairs = _pairs(lines);
  return _one(pairs, name);
}

String? _one(String pairs, String name) {
  for (final part in pairs.split(';')) {
    final t = part.trim();
    final i = t.indexOf('=');
    if (i <= 0) continue;
    if (t.substring(0, i) == name) return t.substring(i + 1);
  }
  return null;
}

String _pairs(List<String>? lines) {
  if (lines == null) return '';
  final parts = <String>[];
  for (final line in lines) {
    final pair = line.split(';').first.trim();
    if (pair.contains('=')) parts.add(pair);
  }
  return parts.join('; ');
}

/// 与 QQ 网页 `hash33` 一致。`h` 用于 `g_tk`（初始值 5381）。
int hash33(String s, [int h = 0]) {
  for (final c in s.codeUnits) {
    h = (h << 5) + h + c;
  }
  return h & 2147483647;
}
