/// 音质档位，br 与网易云一致。
enum AudioQuality {
  k128(128000, '128K'),
  k192(192000, '192K'),
  k320(320000, '320K'),
  lossless(999000, '无损');

  const AudioQuality(this.br, this.label);
  final int br;
  final String label;

  static AudioQuality fromBr(int? br) {
    if (br == null) return AudioQuality.k320;
    return AudioQuality.values.firstWhere(
      (q) => q.br == br,
      orElse: () => AudioQuality.k320,
    );
  }
}

class TrackMeta {
  const TrackMeta({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    required this.coverUrl,
    required this.durationMs,
  });

  final String id;
  final String title;
  final String artists;
  final String album;
  final String coverUrl;
  final int durationMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artists': artists,
        'album': album,
        'coverUrl': coverUrl,
        'durationMs': durationMs,
      };

  factory TrackMeta.fromJson(Map<String, dynamic> json) => TrackMeta(
        id: '${json['id']}',
        title: json['title'] as String? ?? '',
        artists: json['artists'] as String? ?? '',
        album: json['album'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      );
}

class LyricBundle {
  const LyricBundle({required this.lrc, this.translatedLrc = ''});

  final String lrc;
  final String translatedLrc;
}

class PlayUrl {
  const PlayUrl({
    required this.url,
    this.br,
    this.type,
    this.fee,
    this.level,
    this.freeTrialEndSec,
  });

  final String? url;
  final int? br;
  final String? type;
  final int? fee;
  final String? level;

  /// 试听结束秒数；非试听为 null。
  final int? freeTrialEndSec;

  bool get isTrial => freeTrialEndSec != null;
}
