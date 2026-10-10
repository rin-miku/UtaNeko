import 'package:utaneko/sources/models.dart';
import 'package:utaneko/sources/netease/netease_source.dart';

Future<void> main() async {
  final src = NeteaseSource();
  try {
    final meta = await src.getDetail('347230');
    print('DETAIL ok title=${meta.title} artist=${meta.artists} id=${meta.id}');
  } catch (e) {
    print('DETAIL fail: $e');
  }
  try {
    final url = await src.getPlayUrl('347230', quality: AudioQuality.k128);
    print('URL ok hasUrl=${url.url != null} br=${url.br} preview=${url.url?.substring(0, (url.url!.length < 60) ? url.url!.length : 60)}');
  } catch (e) {
    print('URL fail: $e');
  }
}
