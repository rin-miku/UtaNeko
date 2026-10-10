import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show asJsonMap;
import 'link_parser.dart';

typedef CookieReader = Future<String> Function();

/// QQ 音乐源：分享短链 / songid / songmid → 详情、歌词、播放地址。
/// 协议对照开源 qq-music-api / musicu.fcg CgiGetVkey。
class QqSource implements MusicSource {
  QqSource({
    Dio? dio,
    CookieReader? cookieReader,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.plain,
                headers: {
                  'User-Agent': _ua,
                  'Referer': 'https://y.qq.com/',
                  'Origin': 'https://y.qq.com',
                  'Accept': '*/*',
                },
                validateStatus: (s) => s != null && s < 500,
              ),
            ),
        _cookieReader = cookieReader ?? (() async => '');

  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
      'Mobile/15E148 Safari/604.1';

  final Dio _dio;
  final CookieReader _cookieReader;
  final Map<String, ({DateTime t, PlayUrl v})> _urlCache = {};
  final Map<String, _QqSongCache> _songCache = {};

  @override
  String get id => 'qq';

  @override
  String get displayName => 'QQ 音乐';

  @override
  Map<String, String> get mediaHeaders => const {
        'User-Agent': _ua,
        'Referer': 'https://y.qq.com/',
      };

  @override
  Future<TrackMeta> resolve(String input) async {
    final mid = await resolveMid(input);
    if (mid == null) {
      throw StateError(
        '无法解析歌曲，请粘贴含 songid 的 QQ 音乐链接、分享短链或 songmid',
      );
    }
    return getDetail(mid);
  }

  Future<String?> resolveMid(String input) async {
    // 优先 songid（如 i.y.qq.com/v8/playsong.html?songid=…）
    final songId = QqLinkParser.extractSongId(input);
    if (songId != null) {
      final mid = await _midFromSongId(songId);
      if (mid != null) return mid;
    }

    final direct = QqLinkParser.extractSongMid(input);
    if (direct != null && !QqLinkParser.looksLikeShareUrl(input)) {
      return direct;
    }

    var cur = input.trim();
    if (!cur.startsWith('http://') && !cur.startsWith('https://')) {
      return direct;
    }

    // 短链落地页带 SSR，直接 GET 正文提取 mid / 试听地址。
    final res = await _dio.getUri(
      Uri.parse(cur),
      options: Options(
        followRedirects: true,
        headers: {'User-Agent': _ua, 'Referer': 'https://y.qq.com/'},
        responseType: ResponseType.plain,
      ),
    );
    final html = '${res.data ?? ''}';
    final fromHtmlId = QqLinkParser.extractSongId(html) ??
        QqLinkParser.extractSongId(res.realUri.toString());
    if (fromHtmlId != null) {
      final mid = await _midFromSongId(fromHtmlId);
      if (mid != null) return mid;
    }

    final mid = QqLinkParser.extractSongMid(html) ??
        QqLinkParser.extractSongMid(res.realUri.toString()) ??
        direct;
    if (mid != null) {
      final ssr = _parseSsr(html);
      if (ssr != null) _songCache[mid] = ssr;
    }
    return mid;
  }

  /// songid → songmid，并缓存详情。
  Future<String?> _midFromSongId(String songId) async {
    final song = await _fetchSingleSong(songid: songId);
    if (song == null) return null;
    final mid = '${song['mid'] ?? ''}';
    if (mid.isEmpty) return null;
    _cacheSong(song, mid);
    return mid;
  }

  @override
  Future<TrackMeta> getDetail(String trackId) async {
    final cached = _songCache[trackId];
    if (cached != null) return cached.meta;

    final song = await _fetchSingleSong(songmid: trackId);
    if (song == null) {
      throw StateError('未找到歌曲信息 mid=$trackId');
    }
    return _cacheSong(song, trackId).meta;
  }

  Future<Map<String, dynamic>?> _fetchSingleSong({
    String? songmid,
    String? songid,
  }) async {
    final params = <String, dynamic>{
      'tpl': 'yqq_song_detail',
      'format': 'json',
      'platform': 'yqq',
      'needNewCode': 0,
      if (songmid != null) 'songmid': songmid,
      if (songid != null) 'songid': songid,
    };
    final res = await _dio.get(
      'https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg',
      queryParameters: params,
      options: Options(headers: {'Referer': 'https://y.qq.com/'}),
    );
    final j = asJsonMap(res.data);
    final list = j['data'] as List?;
    if (list == null || list.isEmpty) return null;
    return Map<String, dynamic>.from(list.first as Map);
  }

  _QqSongCache _cacheSong(Map<String, dynamic> song, String trackId) {
    final meta = _mapDetail(song);
    final mediaMid =
        ((song['file'] as Map?)?['media_mid'] as String?) ?? trackId;
    final tryEnd = ((song['file'] as Map?)?['e_30s'] as num?)?.toInt();
    final payPlay = (song['pay'] as Map?)?['pay_play'];
    final cached = _QqSongCache(
      meta: meta,
      mediaMid: mediaMid,
      trialUrl: null,
      freeTrialEndSec: (payPlay == 1 && tryEnd != null && tryEnd > 0)
          ? (tryEnd / 1000).round()
          : null,
    );
    _songCache[trackId] = cached;
    return cached;
  }

  @override
  Future<LyricBundle> getLyric(String trackId) async {
    final cookie = await _cookieReader();
    final res = await _dio.get(
      'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
      queryParameters: {
        'songmid': trackId,
        'format': 'json',
        'nobase64': 1,
        'g_tk': 5381,
      },
      options: Options(
        headers: {
          'Referer': 'https://y.qq.com/',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ),
    );
    final j = asJsonMap(res.data);
    var lrc = j['lyric'] as String? ?? '';
    var tlyric = j['trans'] as String? ?? '';
    // 个别环境仍返回 base64
    if (lrc.isNotEmpty && !lrc.contains('[')) {
      try {
        lrc = utf8.decode(base64Decode(lrc));
      } catch (_) {}
    }
    if (tlyric.isNotEmpty && !tlyric.contains('[')) {
      try {
        tlyric = utf8.decode(base64Decode(tlyric));
      } catch (_) {}
    }
    return LyricBundle(lrc: lrc, translatedLrc: tlyric);
  }

  @override
  Future<PlayUrl> getPlayUrl(
    String trackId, {
    required AudioQuality quality,
  }) async {
    final cookie = await _cookieReader();
    final key = '$trackId:${quality.br}:${cookie.isEmpty ? 0 : 1}';
    final hit = _urlCache[key];
    if (hit != null &&
        DateTime.now().difference(hit.t) < const Duration(minutes: 10)) {
      return hit.v;
    }

    await getDetail(trackId);
    final cache = _songCache[trackId];
    final mediaMid = cache?.mediaMid ?? trackId;
    final uin = _uinFromCookie(cookie);
    final guid = _guid();

    // 优先 CgiGetVkey；VIP 未登录时常返回空 purl。
    PlayUrl? fromVkey;
    try {
      fromVkey = await _fetchVkey(
        songMid: trackId,
        mediaMid: mediaMid,
        quality: quality,
        uin: uin,
        guid: guid,
        cookie: cookie,
      );
    } catch (_) {
      fromVkey = null;
    }

    PlayUrl result;
    if (fromVkey?.url != null && fromVkey!.url!.isNotEmpty) {
      result = fromVkey;
    } else if (cache?.trialUrl != null && cache!.trialUrl!.isNotEmpty) {
      result = PlayUrl(
        url: cache.trialUrl!.replaceFirst(RegExp(r'^http://'), 'https://'),
        br: AudioQuality.k128.br,
        type: 'mp3',
        freeTrialEndSec: cache.freeTrialEndSec ?? 60,
      );
    } else {
      // 再试一档 128，仍失败则报错（对齐网易：引导登录）
      if (quality != AudioQuality.k128) {
        try {
          final low = await _fetchVkey(
            songMid: trackId,
            mediaMid: mediaMid,
            quality: AudioQuality.k128,
            uin: uin,
            guid: guid,
            cookie: cookie,
          );
          if (low.url != null && low.url!.isNotEmpty) {
            result = low;
            _urlCache[key] = (t: DateTime.now(), v: result);
            return result;
          }
        } catch (_) {}
      }
      result = PlayUrl(
        url: null,
        freeTrialEndSec: cache?.freeTrialEndSec,
      );
    }

    _urlCache[key] = (t: DateTime.now(), v: result);
    return result;
  }

  Future<PlayUrl> _fetchVkey({
    required String songMid,
    required String mediaMid,
    required AudioQuality quality,
    required String uin,
    required String guid,
    required String cookie,
  }) async {
    final file = _filenameFor(mediaMid, quality);
    final payload = {
      'comm': {
        'ct': 24,
        'cv': 0,
        'format': 'json',
        'platform': 'yqq.json',
        'uin': uin,
      },
      'req_0': {
        'module': 'vkey.GetVkeyServer',
        'method': 'CgiGetVkey',
        'param': {
          'guid': guid,
          'songmid': [songMid],
          'filename': [file],
          'songtype': [0],
          'uin': uin,
          'loginflag': cookie.isEmpty ? 0 : 1,
          'platform': '20',
        },
      },
    };

    final res = await _dio.get(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      queryParameters: {'data': jsonEncode(payload)},
      options: Options(
        headers: {
          'Referer': 'https://y.qq.com/',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ),
    );
    final j = asJsonMap(res.data);
    final req = j['req_0'] as Map?;
    final data = req?['data'] as Map?;
    final infos = data?['midurlinfo'] as List?;
    final info = infos?.isNotEmpty == true
        ? Map<String, dynamic>.from(infos!.first as Map)
        : null;
    final purl = info?['purl'] as String? ?? '';
    final sips = (data?['sip'] as List?)?.cast<dynamic>() ?? const [];
    String? url;
    if (purl.isNotEmpty) {
      final sip = sips.isNotEmpty ? '${sips.first}' : 'https://ws.stream.qqmusic.qq.com/';
      url = (sip.endsWith('/') ? sip : '$sip/') + purl;
      url = url.replaceFirst(RegExp(r'^http://'), 'https://');
    }

    final resultCode = (info?['result'] as num?)?.toInt();
    // 104003 = 需登录/VIP；若有 SSR 试听则交给上层兜底
    return PlayUrl(
      url: url,
      br: quality.br,
      type: file.contains('.flac')
          ? 'flac'
          : file.contains('.m4a')
              ? 'm4a'
              : 'mp3',
      fee: resultCode == 104003 ? 1 : 0,
      freeTrialEndSec: url == null ? null : null,
    );
  }

  _QqSongCache? _parseSsr(String html) {
    final m = RegExp(
      r'window\.__ssrFirstPageData__\s*=\s*"((?:\\.|[^"\\])*)"',
    ).firstMatch(html);
    if (m == null) return null;
    try {
      // JS 字符串字面量 → JSON 文本 → 对象
      final jsonText = jsonDecode('"${m.group(1)!}"') as String;
      final root = jsonDecode(jsonText) as Map<String, dynamic>;
      final song = root['song'];
      if (song is! Map) return null;
      final s = Map<String, dynamic>.from(song);
      final mid = '${s['mid'] ?? ''}';
      if (mid.isEmpty) return null;
      final singers = (s['singer'] as List? ?? [])
          .map((e) => e is Map ? '${e['name'] ?? e['title'] ?? ''}' : '')
          .where((n) => n.isNotEmpty)
          .join(' / ');
      final album = s['album'];
      final albumName =
          album is Map ? '${album['name'] ?? album['title'] ?? ''}' : '';
      final cover =
          '${s['img'] ?? ''}'.replaceFirst(RegExp(r'^http:'), 'https:');
      final meta = TrackMeta(
        id: mid,
        title: '${s['title'] ?? s['name'] ?? ''}',
        artists: singers.isNotEmpty ? singers : '${s['singerName'] ?? ''}',
        album: albumName,
        coverUrl: cover,
        durationMs: ((s['interval'] as num?)?.toInt() ?? 0) * 1000,
      );
      final playUrl = '${s['playUrl'] ?? ''}'
          .replaceFirst(RegExp(r'^http://'), 'https://');
      final e30 = (s['file'] as Map?)?['e_30s'];
      final action = s['action'] as Map?;
      final isTry = action?['try'] == true || action?['tryPlay'] == true;
      final mediaMid =
          ((s['file'] as Map?)?['media_mid'] as String?) ?? mid;
      return _QqSongCache(
        meta: meta,
        mediaMid: mediaMid,
        trialUrl: playUrl.isEmpty ? null : playUrl,
        freeTrialEndSec: isTry
            ? (((e30 as num?)?.toInt() ?? 60000) / 1000).round()
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  TrackMeta _mapDetail(Map<String, dynamic> s) {
    final album = s['album'] as Map? ?? {};
    final singers = (s['singer'] as List? ?? [])
        .map((e) => e is Map ? '${e['name'] ?? e['title'] ?? ''}' : '')
        .where((n) => n.isNotEmpty)
        .join(' / ');
    final pmid = '${album['pmid'] ?? album['mid'] ?? ''}';
    final cover = pmid.isEmpty
        ? ''
        : 'https://y.qq.com/music/photo_new/T002R500x500M000$pmid.jpg';
    return TrackMeta(
      id: '${s['mid'] ?? ''}',
      title: '${s['title'] ?? s['name'] ?? ''}',
      artists: singers,
      album: '${album['title'] ?? album['name'] ?? ''}',
      coverUrl: cover,
      durationMs: ((s['interval'] as num?)?.toInt() ?? 0) * 1000,
    );
  }

  static String _filenameFor(String mediaMid, AudioQuality q) {
    switch (q) {
      case AudioQuality.lossless:
        return 'F000$mediaMid.flac';
      case AudioQuality.k320:
        return 'M800$mediaMid.mp3';
      case AudioQuality.k192:
        return 'C600$mediaMid.m4a';
      case AudioQuality.k128:
        return 'M500$mediaMid.mp3';
    }
  }

  static String _uinFromCookie(String cookie) {
    final m = RegExp(r'(?:^|;\s*)uin=o?(\d+)').firstMatch(cookie);
    return m?.group(1) ?? '0';
  }

  static String _guid() {
    final r = Random();
    return List.generate(10, (_) => r.nextInt(10)).join();
  }
}

class _QqSongCache {
  const _QqSongCache({
    required this.meta,
    required this.mediaMid,
    required this.trialUrl,
    required this.freeTrialEndSec,
  });

  final TrackMeta meta;
  final String mediaMid;
  final String? trialUrl;
  final int? freeTrialEndSec;
}
