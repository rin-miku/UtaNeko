import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/core/lyric/lrc_parser.dart';
import 'package:utaneko/sources/kugou/link_parser.dart';
import 'package:utaneko/sources/netease/link_parser.dart';
import 'package:utaneko/sources/qq/link_parser.dart';

void main() {
  group('NeteaseLinkParser', () {
    test('纯 ID', () {
      expect(NeteaseLinkParser.extractSongId('123456'), '123456');
    });

    test('song 链接', () {
      expect(
        NeteaseLinkParser.extractSongId(
          'https://music.163.com/#/song?id=123456',
        ),
        '123456',
      );
    });
  });

  group('QqLinkParser', () {
    test('纯 songmid', () {
      expect(QqLinkParser.extractSongMid('003mgM2o0oyQBz'), '003mgM2o0oyQBz');
    });

    test('播放页 songmid URL', () {
      expect(
        QqLinkParser.extractSongMid(
          'https://i2.y.qq.com/n3/other/pages/playsong/index.html?songmid=003mgM2o0oyQBz',
        ),
        '003mgM2o0oyQBz',
      );
    });

    test('playsong.html songid', () {
      expect(
        QqLinkParser.extractSongId(
          'https://i.y.qq.com/v8/playsong.html?songid=107769306&songtype=0#webchat_redirect',
        ),
        '107769306',
      );
    });

    test('纯数字按 songid', () {
      expect(QqLinkParser.extractSongId('107769306'), '107769306');
      expect(QqLinkParser.extractSongMid('107769306'), isNull);
    });
  });

  group('KugouLinkParser', () {
    test('chain 查询参数', () {
      expect(
        KugouLinkParser.extractChain(
          'https://m.kugou.com/share/song.html?chain=LCBNd3G6V3',
        ),
        'LCBNd3G6V3',
      );
    });

    test('www share 落地页 chain + hash 片段', () {
      expect(
        KugouLinkParser.extractChain(
          'https://www.kugou.com/share/LO7Vd8G6V3.html#12qvf696',
        ),
        'LO7Vd8G6V3',
      );
    });

    test('phpParam HTML', () {
      const html = '''
<script>
var phpParam = {"hash":"abc","album_id":"1","album_audio_id":"2","filename":"%u9e7f%u4e43 - hi","timelen":1000,"song_info":{"data":{"hash":"ABC123","albumid":1,"album_audio_id":2,"fileName":"x - y","timeLength":10}}};
</script>
''';
      final ids = KugouLinkParser.extractShareIdsFromHtml(html);
      expect(ids, isNotNull);
      expect(ids!.hash, 'ABC123');
      expect(ids.albumId, '1');
      expect(ids.albumAudioId, '2');
      expect(ids.trackId, 'ABC123:1:2');
    });

    test('dataFromSmarty HTML（桌面落地页）', () {
      const html = '''
<script>
var dataFromSmarty = [{"hash":"233660D7913706A94A06832F66C84F73","author_name":"双笙","song_name":"心做し","audio_name":"双笙 - 心做し","album_id":"2650597","timelength":268800,"mixsongid":"65079186","encode_album_audio_id":"12qvf696"}],//当前页面歌曲信息
    playType = "single";
</script>
''';
      final ids = KugouLinkParser.extractShareIdsFromHtml(html);
      expect(ids, isNotNull);
      expect(ids!.hash, '233660D7913706A94A06832F66C84F73');
      expect(ids.albumId, '2650597');
      expect(ids.albumAudioId, '65079186');
      expect(ids.durationMs, 268800);
    });
  });

  group('LrcParser', () {
    test('解析时间戳与翻译对齐', () {
      const lrc = '[00:01.00]一行\n[00:02.50]二行';
      const tlyric = '[00:01.00]one\n[00:02.40]two';
      final lines = LrcParser.parse(lrc, translatedRaw: tlyric);
      expect(lines.length, 2);
      expect(lines[0].text, '一行');
      expect(lines[0].translation, 'one');
      expect(lines[1].translation, 'two');
      expect(lines[0].time, const Duration(seconds: 1));
    });
  });
}
