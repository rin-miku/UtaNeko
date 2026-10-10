/// 生成安全文件名（Windows / Android 通用）。
String safeDownloadBaseName({
  required String title,
  required String artists,
  String kind = '',
  String ext = 'mp3',
}) {
  final cleaned = safeFolderName(title: title, artists: artists, kind: kind);
  return '$cleaned.$ext';
}

/// 歌曲文件夹名：`歌手 - 歌名`（无扩展名）。
String safeFolderName({
  required String title,
  required String artists,
  String kind = '',
}) {
  final base = '${artists.isNotEmpty ? '$artists - ' : ''}$title$kind';
  return base.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
}
