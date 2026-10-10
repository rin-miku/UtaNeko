import 'dart:convert';

/// 从酷狗分享链提取 chain，以及从分享页 HTML 提取 hash / album 信息。
abstract final class KugouLinkParser {
  static final _chainQuery = RegExp(
    r'[?&]chain=([0-9A-Za-z]+)',
    caseSensitive: false,
  );
  static final _chainPath = RegExp(
    r'/share/([0-9A-Za-z]+)\.html',
    caseSensitive: false,
  );

  /// 支持 `?chain=`、`/share/xxx.html`，或纯 chain 字符串。
  static String? extractChain(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    // 去掉 hash 片段再匹配
    final noHash = s.split('#').first;
    if (RegExp(r'^[0-9A-Za-z]{6,32}$').hasMatch(noHash) &&
        !noHash.contains('://')) {
      return noHash;
    }
    return _chainQuery.firstMatch(noHash)?.group(1) ??
        _chainPath.firstMatch(noHash)?.group(1);
  }

  /// 解析分享页：移动端 `phpParam` 或桌面端 `dataFromSmarty`。
  static KugouShareIds? extractShareIdsFromHtml(String html) {
    return _fromPhpParam(html) ?? _fromDataFromSmarty(html);
  }

  static KugouShareIds? _fromPhpParam(String html) {
    final marker = RegExp(r'var\s+phpParam\s*=\s*').firstMatch(html);
    if (marker == null) return null;
    final braceStart = html.indexOf('{', marker.end - 1);
    if (braceStart < 0) return null;
    final jsonText = _extractBalanced(html, braceStart, '{', '}');
    if (jsonText == null) return null;
    try {
      return KugouShareIds.fromPhpParam(jsonDecode(jsonText));
    } catch (_) {
      return null;
    }
  }

  /// 桌面落地页：`var dataFromSmarty = [{...}],//注释`
  static KugouShareIds? _fromDataFromSmarty(String html) {
    final marker = RegExp(r'var\s+dataFromSmarty\s*=\s*').firstMatch(html);
    if (marker == null) return null;
    final arrStart = html.indexOf('[', marker.end - 1);
    if (arrStart < 0) return null;
    final jsonText = _extractBalanced(html, arrStart, '[', ']');
    if (jsonText == null) return null;
    try {
      final list = jsonDecode(jsonText);
      if (list is! List || list.isEmpty || list.first is! Map) return null;
      return KugouShareIds.fromSmarty(Map<String, dynamic>.from(list.first as Map));
    } catch (_) {
      return null;
    }
  }

  static String? _extractBalanced(
    String s,
    int start,
    String open,
    String close,
  ) {
    if (start >= s.length || s[start] != open) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        continue;
      }
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }
}

class KugouShareIds {
  const KugouShareIds({
    required this.hash,
    required this.albumId,
    required this.albumAudioId,
    this.fileName = '',
    this.durationMs = 0,
  });

  final String hash;
  final String albumId;
  final String albumAudioId;
  final String fileName;
  final int durationMs;

  /// 复合 trackId：`hash:albumId:albumAudioId`
  String get trackId => '$hash:$albumId:$albumAudioId';

  static KugouShareIds? tryParseTrackId(String trackId) {
    final parts = trackId.split(':');
    if (parts.length != 3) return null;
    if (parts.any((p) => p.isEmpty)) return null;
    return KugouShareIds(
      hash: parts[0],
      albumId: parts[1],
      albumAudioId: parts[2],
    );
  }

  factory KugouShareIds.fromPhpParam(dynamic raw) {
    if (raw is! Map) throw FormatException('phpParam 非对象');
    final decoded = Map<String, dynamic>.from(raw);
    Map<String, dynamic>? songData;
    final songInfo = decoded['song_info'];
    if (songInfo is Map) {
      final data = songInfo['data'];
      if (data is Map) songData = Map<String, dynamic>.from(data);
    }

    final hash = '${songData?['hash'] ?? decoded['hash'] ?? ''}'.trim();
    final albumId =
        '${songData?['albumid'] ?? decoded['album_id'] ?? '0'}'.trim();
    final albumAudioId =
        '${songData?['album_audio_id'] ?? decoded['album_audio_id'] ?? '0'}'
            .trim();
    if (hash.isEmpty) throw FormatException('phpParam 缺少 hash');

    final fileName = decodeJsUnicode(
      '${decoded['filename'] ?? songData?['fileName'] ?? ''}',
    );
    final durationMs = (decoded['timelen'] as num?)?.toInt() ??
        ((songData?['timeLength'] as num?)?.toInt() ?? 0) * 1000;

    return KugouShareIds(
      hash: hash,
      albumId: albumId.isEmpty ? '0' : albumId,
      albumAudioId: albumAudioId.isEmpty ? '0' : albumAudioId,
      fileName: fileName,
      durationMs: durationMs > 0 ? durationMs : 0,
    );
  }

  factory KugouShareIds.fromSmarty(Map<String, dynamic> item) {
    final hash = '${item['hash'] ?? ''}'.trim();
    if (hash.isEmpty) throw FormatException('dataFromSmarty 缺少 hash');
    final albumId = '${item['album_id'] ?? '0'}'.trim();
    final albumAudioId =
        '${item['album_audio_id'] ?? item['mixsongid'] ?? '0'}'.trim();
    final fileName = '${item['audio_name'] ?? ''}'.trim().isNotEmpty
        ? '${item['audio_name']}'.trim()
        : [
            if ('${item['author_name'] ?? ''}'.trim().isNotEmpty)
              '${item['author_name']}'.trim(),
            if ('${item['song_name'] ?? ''}'.trim().isNotEmpty)
              '${item['song_name']}'.trim(),
          ].join(' - ');
    final durationMs = (item['timelength'] as num?)?.toInt() ?? 0;
    return KugouShareIds(
      hash: hash,
      albumId: albumId.isEmpty ? '0' : albumId,
      albumAudioId: albumAudioId.isEmpty ? '0' : albumAudioId,
      fileName: fileName,
      durationMs: durationMs,
    );
  }
}

/// 解码酷狗 `filename` 里的 `%uXXXX` / `%XX`。
String decodeJsUnicode(String s) {
  return s.replaceAllMapped(RegExp(r'%u([0-9a-fA-F]{4})'), (m) {
    return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
  }).replaceAllMapped(RegExp(r'%([0-9a-fA-F]{2})'), (m) {
    return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
  });
}
