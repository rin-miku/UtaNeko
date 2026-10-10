import 'models.dart';

/// 音源抽象；网易云 / QQ / 酷狗各自实现，由首页手动切换。
abstract class MusicSource {
  String get id;
  String get displayName;

  /// 播放与下载音频时的 HTTP 头（防盗链 Referer 等）。
  Map<String, String> get mediaHeaders;

  Future<TrackMeta> resolve(String input);
  Future<TrackMeta> getDetail(String trackId);
  Future<LyricBundle> getLyric(String trackId);
  Future<PlayUrl> getPlayUrl(String trackId, {required AudioQuality quality});
}
