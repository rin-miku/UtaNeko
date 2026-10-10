import 'package:utaneko/sources/kugou/kugou_source.dart';
import 'package:utaneko/sources/models.dart';
import 'package:utaneko/sources/qq/qq_source.dart';

/// 联调 QQ / 酷狗分享链（需本机可访问对应域名）。
///
/// dart run tool/smoke_multi_source.dart
Future<void> main() async {
  final qq = QqSource();
  final qqMeta = await qq.resolve(
    'https://c6.y.qq.com/base/fcgi-bin/u?__=H0K1hfVr9FDC',
  );
  final qqLyric = await qq.getLyric(qqMeta.id);
  final qqUrl = await qq.getPlayUrl(qqMeta.id, quality: AudioQuality.k128);
  print('QQ: ${qqMeta.title} / ${qqMeta.artists}');
  print('  lyric=${qqLyric.lrc.isNotEmpty} url=${qqUrl.url != null} trial=${qqUrl.isTrial}');

  final kg = KugouSource();
  final kgMeta = await kg.resolve(
    'https://m.kugou.com/share/song.html?chain=LCBNd3G6V3',
  );
  final kgLyric = await kg.getLyric(kgMeta.id);
  final kgUrl = await kg.getPlayUrl(kgMeta.id, quality: AudioQuality.k128);
  print('酷狗: ${kgMeta.title} / ${kgMeta.artists}');
  print('  lyric=${kgLyric.lrc.isNotEmpty} url=${kgUrl.url != null}');
}
