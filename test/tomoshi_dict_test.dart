import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/core/dict/tomoshi_dict.dart';

void main() {
  test('按义项列出简体释义，并跳过仅供检索的写法', () {
    final entry = parseTomoshiEntry(
      '''
      {
        "kanji": [
          {"text": "見る", "info": []},
          {"text": "覧る", "info": ["search-only kanji form"]}
        ],
        "kana": [{"text": "みる", "info": []}],
        "senses": []
      }
      ''',
      '''
      {
        "senses": {
          "1": {"glosses": [{"text": "检查；审视"}]},
          "0": {"glosses": [{"text": "看；观看"}]}
        }
      }
      ''',
    );
    expect(entry, isNotNull);
    expect(entry!.headword, '見る');
    expect(entry.reading, 'みる');
    expect(entry.glosses, ['看；观看', '检查；审视']);
  });

  test('没有 zh_defs 时用词条里的简体义项', () {
    final entry = parseTomoshiEntry(
      '''
      {
        "kanji": [],
        "kana": [{"text": "みる"}],
        "senses": [
          {"glosses": [
            {"text": "to see", "lang": "eng"},
            {"text": "看", "lang": "zho"}
          ]}
        ]
      }
      ''',
      null,
    );
    expect(entry!.headword, 'みる');
    expect(entry.glosses, ['看']);
  });
}
