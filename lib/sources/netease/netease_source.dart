import 'dart:convert';

import 'package:dio/dio.dart';

import '../models.dart';
import '../music_source.dart';
import 'link_parser.dart';
import 'weapi.dart';

typedef CookieReader = Future<String> Function();

/// 网易云源：进程内 dio 直连，对照 server.js 行为（无本地 HTTP 服务）。
class NeteaseSource implements MusicSource {
  NeteaseSource({
    Dio? dio,
    CookieReader? cookieReader,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                headers: {
                  'User-Agent': _ua,
                  'Referer': 'https://music.163.com/',
                  'Origin': 'https://music.163.com',
                  'Accept': '*/*',
                },
                validateStatus: (s) => s != null && s < 500,
              ),
            ),
        _cookieReader = cookieReader ?? (() async => '');

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const _host = 'https://music.163.com';

  final Dio _dio;
  final CookieReader _cookieReader;
  final Map<String, ({DateTime t, PlayUrl v})> _urlCache = {};

  @override
  String get id => 'netease';

  @override
  String get displayName => '网易云音乐';

  @override
  Map<String, String> get mediaHeaders => const {
        'User-Agent': _ua,
        'Referer': 'https://music.163.com/',
      };

  @override
  Future<TrackMeta> resolve(String input) async {
    final songId = await resolveId(input);
    if (songId == null) {
      throw StateError('无法解析歌曲 ID，请粘贴网易云链接或数字 ID');
    }
    return getDetail(songId);
  }

  Future<String?> resolveId(String input) async {
    var id = NeteaseLinkParser.extractSongId(input);
    if (id != null) return id;

    var cur = input.trim();
    for (var i = 0; i < 5; i++) {
      if (!cur.startsWith('http://') && !cur.startsWith('https://')) break;
      final res = await _dio.getUri(
        Uri.parse(cur),
        options: Options(
          followRedirects: false,
          maxRedirects: 0,
          headers: {'User-Agent': _ua},
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final loc = res.headers.value('location');
      if (loc == null || loc.isEmpty) break;
      cur = Uri.parse(cur).resolve(loc).toString();
      id = NeteaseLinkParser.extractSongId(cur);
      if (id != null) return id;
    }
    return NeteaseLinkParser.extractSongId(cur);
  }

  @override
  Future<TrackMeta> getDetail(String trackId) async {
    Object? weapiError;

    try {
      final j = await _weapiPost(
        '/weapi/v3/song/detail?csrf_token=',
        {
          'c': '[{"id":${int.parse(trackId)},"v":0}]',
          'csrf_token': '',
        },
        withCookie: false,
      );
      final songs = j['songs'] as List?;
      final d = _mapDetail(songs?.isNotEmpty == true ? songs!.first : null);
      if (d != null && d.title.isNotEmpty) return d;
      weapiError = 'weapi 返回空 songs (code=${j['code']})';
    } catch (e) {
      weapiError = e;
    }

    try {
      final res = await _dio.get(
        '$_host/api/song/detail',
        queryParameters: {'ids': '[$trackId]'},
        options: Options(
          headers: {'Cookie': 'os=pc; appver=8.9.75'},
        ),
      );
      final j = asJsonMap(res.data);
      final songs = j['songs'] as List?;
      final d = _mapDetail(songs?.isNotEmpty == true ? songs!.first : null);
      if (d != null && d.title.isNotEmpty) return d;
      throw StateError(
        '未找到歌曲信息 id=$trackId code=${j['code']}；weapi: $weapiError',
      );
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError('未找到歌曲信息 id=$trackId；weapi: $weapiError；fallback: $e');
    }
  }

  @override
  Future<LyricBundle> getLyric(String trackId) async {
    try {
      final j = await _weapiPost(
        '/weapi/song/lyric?csrf_token=',
        {
          'id': int.parse(trackId),
          'lv': -1,
          'tv': -1,
          'csrf_token': '',
        },
        withCookie: false,
      );
      return LyricBundle(
        lrc: (j['lrc'] as Map?)?['lyric'] as String? ?? '',
        translatedLrc: (j['tlyric'] as Map?)?['lyric'] as String? ?? '',
      );
    } catch (_) {
      final res = await _dio.get(
        '$_host/api/song/lyric',
        queryParameters: {
          'os': 'pc',
          'id': trackId,
          'lv': -1,
          'kv': -1,
          'tv': -1,
        },
      );
      final j = asJsonMap(res.data);
      return LyricBundle(
        lrc: (j['lrc'] as Map?)?['lyric'] as String? ?? '',
        translatedLrc: (j['tlyric'] as Map?)?['lyric'] as String? ?? '',
      );
    }
  }

  @override
  Future<PlayUrl> getPlayUrl(
    String trackId, {
    required AudioQuality quality,
  }) async {
    final cookie = await _cookieReader();
    // 登录前后分开缓存，避免扫码后仍命中试听地址。
    final key = '$trackId:${quality.br}:${cookie.isEmpty ? 0 : 1}';
    final hit = _urlCache[key];
    if (hit != null &&
        DateTime.now().difference(hit.t) < const Duration(minutes: 10)) {
      return hit.v;
    }

    Map<String, dynamic>? j;
    if (cookie.isNotEmpty) {
      try {
        j = await _weapiPost(
          '/weapi/song/enhance/player/url?csrf_token=',
          {
            'ids': [int.parse(trackId)],
            'br': quality.br,
            'csrf_token': '',
          },
          withCookie: true,
        );
      } catch (_) {
        j = null;
      }
    }

    if (j == null) {
      final cookieHeader =
          'os=pc; appver=8.9.75${cookie.isNotEmpty ? '; $cookie' : ''}';
      final res = await _dio.post(
        '$_host/api/song/enhance/player/url',
        data: {
          'ids': '[$trackId]',
          'br': '${quality.br}',
          'os': 'pc',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Cookie': cookieHeader},
        ),
      );
      j = asJsonMap(res.data);
    }

    final data = (j['data'] as List?)?.firstOrNull as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('获取播放地址失败 code=${j['code']}');
    }

    final rawUrl = data['url'] as String?;
    final trial = data['freeTrialInfo'] as Map?;
    final v = PlayUrl(
      url: rawUrl?.replaceFirst(RegExp(r'^http://'), 'https://'),
      br: (data['br'] as num?)?.toInt(),
      type: data['type'] as String?,
      fee: (data['fee'] as num?)?.toInt(),
      level: data['level'] as String?,
      freeTrialEndSec: (trial?['end'] as num?)?.toInt() ??
          (trial?['endSec'] as num?)?.toInt(),
    );
    _urlCache[key] = (t: DateTime.now(), v: v);
    return v;
  }

  Future<Map<String, dynamic>> _weapiPost(
    String pathAndQuery,
    Map<String, dynamic> payload, {
    required bool withCookie,
  }) async {
    final cookie = await _cookieReader();
    // 与 Node 一致：带 cookie 时用用户凭证；否则用默认 os/appver
    final cookieHeader = withCookie && cookie.isNotEmpty
        ? cookie
        : 'os=pc; appver=8.9.75';

    // 用 Map 交给 Dio 做 form-urlencoded，避免预编码字符串被二次处理
    final fields = Weapi.formFields(payload);

    final res = await _dio.post(
      '$_host$pathAndQuery',
      data: fields,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Cookie': cookieHeader,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      ),
    );

    final json = asJsonMap(res.data, httpStatus: res.statusCode);
    final code = json['code'];
    if (code != null && code != 200) {
      throw StateError(
        '网易云接口错误 code=$code'
        '${json['message'] != null ? ' ${json['message']}' : ''}'
        ' (HTTP ${res.statusCode})',
      );
    }
    return json;
  }

  TrackMeta? _mapDetail(dynamic raw) {
    if (raw is! Map) return null;
    final s = Map<String, dynamic>.from(raw);
    final al = (s['al'] ?? s['album']) as Map? ?? {};
    final ars = (s['ar'] ?? s['artists']) as List? ?? [];
    final artists = ars
        .map((a) => a is Map ? (a['name'] as String? ?? '') : '')
        .where((n) => n.isNotEmpty)
        .join(' / ');
    final pic = ((al['picUrl'] as String?) ?? '')
        .replaceFirst(RegExp(r'^http:'), 'https:');
    return TrackMeta(
      id: '${s['id']}',
      title: s['name'] as String? ?? '',
      artists: artists,
      album: al['name'] as String? ?? '',
      coverUrl: pic,
      durationMs: (s['dt'] as num?)?.toInt() ??
          (s['duration'] as num?)?.toInt() ??
          0,
    );
  }
}

/// 统一把 Dio 响应收成 Map（兼容已解析 Map / JSON 字符串）。
Map<String, dynamic> asJsonMap(dynamic data, {int? httpStatus}) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String) {
    final s = data.trim();
    if (s.isEmpty) {
      throw StateError('空响应${httpStatus != null ? ' HTTP $httpStatus' : ''}');
    }
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      final preview = s.length > 120 ? '${s.substring(0, 120)}…' : s;
      throw StateError(
        '响应非 JSON${httpStatus != null ? ' HTTP $httpStatus' : ''}: $preview',
      );
    }
  }
  if (data == null) {
    throw StateError('空响应${httpStatus != null ? ' HTTP $httpStatus' : ''}');
  }
  throw StateError(
    '无法解析响应类型 ${data.runtimeType}'
    '${httpStatus != null ? ' HTTP $httpStatus' : ''}',
  );
}
