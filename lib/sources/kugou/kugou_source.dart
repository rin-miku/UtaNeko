import 'dart:convert';

import 'package:dio/dio.dart';

import '../models.dart';
import '../music_source.dart';
import '../netease/netease_source.dart' show asJsonMap;
import 'kugou_auth.dart' show md5Hex;
import 'link_parser.dart';

typedef CookieReader = Future<String> Function();

/// 酷狗源：仅分享链 `chain=` → 详情、歌词、播放地址。
/// 分享页 phpParam + m.kugou.com getSongInfo；歌词对照 lyrics.kugou.com。
class KugouSource implements MusicSource {
  KugouSource({
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
                  // 桌面 UA / Referer 会把 m 站 302 到 www，移动 UA 才能拿到 phpParam
                  'Referer': 'https://m.kugou.com/',
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
  final Map<String, KugouShareIds> _idCache = {};
  final Map<String, TrackMeta> _metaCache = {};

  @override
  String get id => 'kugou';

  @override
  String get displayName => '酷狗音乐';

  @override
  Map<String, String> get mediaHeaders => const {
        'User-Agent': _ua,
        'Referer': 'https://www.kugou.com/',
      };

  @override
  Future<TrackMeta> resolve(String input) async {
    final ids = await resolveShareIds(input);
    if (ids == null) {
      throw StateError(
        '无法解析酷狗分享链，请粘贴 '
        'm.kugou.com/...chain=… 或 www.kugou.com/share/xxx.html',
      );
    }
    _idCache[ids.trackId] = ids;
    return getDetail(ids.trackId);
  }

  Future<KugouShareIds?> resolveShareIds(String input) async {
    final chain = KugouLinkParser.extractChain(input);
    if (chain == null) return null;

    // 1) 移动分享页（phpParam）；部分环境会 302 到桌面页
    final mobileHtml = await _fetchShareHtml(
      'https://m.kugou.com/share/song.html?chain=$chain',
      referer: 'https://m.kugou.com/',
    );
    var ids = KugouLinkParser.extractShareIdsFromHtml(mobileHtml);
    // 2) 桌面落地页（dataFromSmarty）— 浏览器点开后常见
    //    https://www.kugou.com/share/LO7Vd8G6V3.html#…
    if (ids == null) {
      final wwwHtml = await _fetchShareHtml(
        'https://www.kugou.com/share/$chain.html',
        referer: 'https://www.kugou.com/',
      );
      ids = KugouLinkParser.extractShareIdsFromHtml(wwwHtml);
    }
    if (ids != null) _idCache[ids.trackId] = ids;
    return ids;
  }

  Future<String> _fetchShareHtml(String url, {required String referer}) async {
    final res = await _dio.getUri(
      Uri.parse(url),
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        headers: {
          'User-Agent': _ua,
          'Referer': referer,
          'Accept': 'text/html,*/*',
        },
        responseType: ResponseType.plain,
      ),
    );
    return '${res.data ?? ''}';
  }

  @override
  Future<TrackMeta> getDetail(String trackId) async {
    final hit = _metaCache[trackId];
    if (hit != null) return hit;

    final ids = _idCache[trackId] ?? KugouShareIds.tryParseTrackId(trackId);
    if (ids == null) {
      throw StateError('无效的酷狗 trackId');
    }

    final info = await _getSongInfo(ids);
    final title = '${info['songName'] ?? ''}'.trim();
    final artists = '${info['author_name'] ?? info['singerName'] ?? ''}'.trim();
    final fileName = '${info['fileName'] ?? ids.fileName}'.trim();
    var parsedTitle = title;
    var parsedArtists = artists;
    if (parsedTitle.isEmpty && fileName.contains(' - ')) {
      final i = fileName.indexOf(' - ');
      parsedArtists = fileName.substring(0, i).trim();
      parsedTitle = fileName.substring(i + 3).trim();
    }

    final albumImg = '${info['album_img'] ?? info['imgUrl'] ?? ''}'
        .replaceAll('{size}', '480')
        .replaceFirst(RegExp(r'^http:'), 'https:');

    final meta = TrackMeta(
      id: trackId,
      title: parsedTitle.isEmpty ? (fileName.isEmpty ? trackId : fileName) : parsedTitle,
      artists: parsedArtists,
      album: '',
      coverUrl: albumImg,
      durationMs: ((info['timeLength'] as num?)?.toInt() ?? 0) * 1000,
    );
    _metaCache[trackId] = meta;
    _idCache[trackId] = ids;
    return meta;
  }

  @override
  Future<LyricBundle> getLyric(String trackId) async {
    final ids = _idCache[trackId] ?? KugouShareIds.tryParseTrackId(trackId);
    if (ids == null) return const LyricBundle(lrc: '');

    final meta = _metaCache[trackId];
    final durationMs = meta?.durationMs ?? ids.durationMs;
    final keyword = [
      if (meta?.artists.isNotEmpty == true) meta!.artists,
      if (meta?.title.isNotEmpty == true) meta!.title,
    ].join('');

    final search = await _dio.get(
      'https://lyrics.kugou.com/search',
      queryParameters: {
        'ver': 1,
        'man': 'yes',
        'client': 'pc',
        'keyword': keyword,
        'duration': durationMs > 0 ? durationMs : '',
        'hash': ids.hash,
      },
    );
    final sj = asJsonMap(search.data);
    final candidates = sj['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return const LyricBundle(lrc: '');

    final best = Map<String, dynamic>.from(candidates.first as Map);
    final lyricId = '${best['id'] ?? ''}';
    final accessKey = '${best['accesskey'] ?? ''}';
    if (lyricId.isEmpty || accessKey.isEmpty) {
      return const LyricBundle(lrc: '');
    }

    final dl = await _dio.get(
      'https://lyrics.kugou.com/download',
      queryParameters: {
        'ver': 1,
        'client': 'pc',
        'id': lyricId,
        'accesskey': accessKey,
        'fmt': 'lrc',
        'charset': 'utf8',
      },
    );
    final dj = asJsonMap(dl.data);
    var content = dj['content'] as String? ?? '';
    if (content.isEmpty) return const LyricBundle(lrc: '');
    if (!content.contains('[')) {
      try {
        content = utf8.decode(base64Decode(content));
      } catch (_) {}
    }
    // 去掉 BOM
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    return LyricBundle(lrc: content);
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
        DateTime.now().difference(hit.t) < const Duration(minutes: 8)) {
      return hit.v;
    }

    final ids = _idCache[trackId] ?? KugouShareIds.tryParseTrackId(trackId);
    if (ids == null) throw StateError('无效的酷狗 trackId');

    final info = await _getSongInfo(ids, quality: quality, cookie: cookie);
    var url = '${info['url'] ?? ''}';
    if (url.isEmpty) {
      final backups = info['backup_url'];
      if (backups is List && backups.isNotEmpty) {
        url = '${backups.first}';
      }
    }
    url = url.replaceFirst(RegExp(r'^http://'), 'https://');

    final br = (info['bitRate'] as num?)?.toInt();
    final v = PlayUrl(
      url: url.isEmpty ? null : url,
      br: br != null && br > 0 ? br * 1000 : quality.br,
      type: '${info['extName'] ?? 'mp3'}',
      fee: (info['privilege'] as num?)?.toInt(),
    );
    _urlCache[key] = (t: DateTime.now(), v: v);
    return v;
  }

  Future<Map<String, dynamic>> _getSongInfo(
    KugouShareIds ids, {
    AudioQuality quality = AudioQuality.k128,
    String cookie = '',
  }) async {
    // 先取一遍拿各音质 hash，再按目标音质请求。
    final base = await _requestSongInfo(ids.hash, ids, cookie: cookie);
    final hash = _pickHash(base, quality) ?? ids.hash;
    if (hash.toLowerCase() == ids.hash.toLowerCase()) return base;
    try {
      return await _requestSongInfo(hash, ids, cookie: cookie);
    } catch (_) {
      return base;
    }
  }

  Future<Map<String, dynamic>> _requestSongInfo(
    String hash,
    KugouShareIds ids, {
    required String cookie,
  }) async {
    final mid = md5Hex('utaneko-${DateTime.now().millisecondsSinceEpoch}');
    final headers = <String, dynamic>{
      'User-Agent': _ua,
      'Referer': 'https://m.kugou.com/',
      'Cookie': [
        'kg_mid=$mid',
        if (cookie.isNotEmpty) cookie,
      ].join('; '),
    };
    final res = await _dio.get(
      'https://m.kugou.com/app/i/getSongInfo.php',
      queryParameters: {
        'hash': hash,
        'cmd': 'playInfo',
        'album_id': ids.albumId,
        'album_audio_id': ids.albumAudioId,
      },
      options: Options(headers: headers),
    );
    final j = asJsonMap(res.data);
    final err = j['errcode'] ?? j['error_code'];
    if (err != null && err != 0) {
      throw StateError('酷狗 getSongInfo 失败 err=$err ${j['error'] ?? ''}');
    }
    return j;
  }

  String? _pickHash(Map<String, dynamic> info, AudioQuality quality) {
    final extra = info['extra'];
    if (extra is! Map) return info['hash'] as String?;
    final e = Map<String, dynamic>.from(extra);
    switch (quality) {
      case AudioQuality.lossless:
        return _nonEmpty(e['sqhash']) ??
            _nonEmpty(e['highhash']) ??
            _nonEmpty(e['320hash']) ??
            _nonEmpty(e['128hash']);
      case AudioQuality.k320:
      case AudioQuality.k192:
        return _nonEmpty(e['320hash']) ?? _nonEmpty(e['128hash']);
      case AudioQuality.k128:
        return _nonEmpty(e['128hash']) ?? info['hash'] as String?;
    }
  }

  String? _nonEmpty(dynamic v) {
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
}

