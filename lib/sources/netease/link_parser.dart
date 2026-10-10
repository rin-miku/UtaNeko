/// 从分享链接 / 短链落地 URL / 纯数字中提取网易云歌曲 ID。
abstract final class NeteaseLinkParser {
  static String? extractSongId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d{5,}$').hasMatch(s)) return s;

    final patterns = [
      RegExp(r'[?&]id=(\d+)'),
      RegExp(r'song/(\d+)'),
      RegExp(r'outchain[^?]*\?[^#]*id=(\d+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m != null) return m.group(1);
    }
    return null;
  }
}
