/// 从 QQ 音乐分享短链 / 播放页 URL / 纯 songmid·songid 中提取标识。
abstract final class QqLinkParser {
  static final _midOnly = RegExp(r'^[0-9A-Za-z]{10,16}$');
  static final _digitsOnly = RegExp(r'^\d{5,}$');
  static final _midInUrl = RegExp(
    r'(?:songmid|song_mid)=([0-9A-Za-z]{10,16})',
    caseSensitive: false,
  );
  static final _songIdInUrl = RegExp(
    r'(?:^|[?&#])songid=(\d{5,})',
    caseSensitive: false,
  );
  static final _ssrSongmid = RegExp(
    r'"mid"\s*:\s*"([0-9A-Za-z]{10,16})"',
  );

  /// 纯 mid、`songmid=`，或 SSR JSON 片段中的 mid。
  /// 纯数字交给 [extractSongId]，避免与 songid 混淆。
  static String? extractSongMid(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (_midOnly.hasMatch(s) &&
        !s.contains('://') &&
        !_digitsOnly.hasMatch(s)) {
      return s;
    }

    final fromQuery = _midInUrl.firstMatch(s)?.group(1);
    if (fromQuery != null) return fromQuery;

    final fromSsr = _ssrSongmid.firstMatch(s)?.group(1);
    if (fromSsr != null) return fromSsr;

    return null;
  }

  /// `playsong.html?songid=…` 或纯数字 songid。
  static String? extractSongId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (_digitsOnly.hasMatch(s) && !s.contains('://')) return s;
    return _songIdInUrl.firstMatch(s)?.group(1);
  }

  /// 是否为 QQ 分享短链（需拉页面解析）。
  static bool looksLikeShareUrl(String input) {
    final s = input.trim().toLowerCase();
    return s.contains('y.qq.com') || s.contains('qq.com/base/fcgi-bin/u');
  }
}
