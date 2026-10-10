import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/core/furigana/furi_token.dart';
import 'package:utaneko/core/furigana/furi_txt.dart';

void main() {
  const sampleTokens = [
    [
      FuriToken(surface: '夜', reading: 'ヨル', pos: '名詞', basicForm: '夜'),
      FuriToken(surface: 'に', reading: 'ニ', pos: '助詞', basicForm: 'に'),
      FuriToken(surface: '駆', reading: 'カ', pos: '動詞', basicForm: '駆ける'),
      FuriToken(surface: 'ける', reading: 'ケル', pos: '動詞', basicForm: 'ける'),
    ],
    [
      FuriToken(surface: '働', reading: 'ハタラク', pos: '動詞', basicForm: '働く'),
      FuriToken(surface: 'く', reading: 'ク', pos: '動詞', basicForm: 'く'),
    ],
  ];

  test('encodeFuriTxt 仅给汉字注音', () {
    final raw = encodeFuriTxt(sampleTokens);
    expect(raw, '夜[よる]に駆[か]ける\n働[はたらく]く');
  });

  test('parseFuriTxt 往返保留读音', () {
    final raw = encodeFuriTxt(sampleTokens);
    final parsed = parseFuriTxt(raw);
    expect(parsed.length, 2);
    expect(parsed[0].map((t) => t.surface).join(), '夜に駆ける');
    expect(parsed[0][0].reading, 'よる');
    expect(parsed[0][2].reading, 'か');
    expect(parsed[1][0].reading, 'はたらく');
  });

  test('parseFuriTxt 无括号行整段为一个 token', () {
    final parsed = parseFuriTxt('あいうえお\nかきくけこ');
    expect(parsed.length, 2);
    expect(parsed[0].single.surface, 'あいうえお');
    expect(parsed[0].single.reading, isEmpty);
  });

  test('parseFuriTxt 剥掉末尾多余换行', () {
    final parsed = parseFuriTxt('夜[よる]\n');
    expect(parsed.length, 1);
    expect(parsed[0].single.surface, '夜');
  });

  test('validateFuriLineCount 行数不匹配时抛错', () {
    final tokens = parseFuriTxt('夜[よる]\nに');
    expect(() => validateFuriLineCount(tokens, 2), returnsNormally);
    expect(
      () => validateFuriLineCount(tokens, 3),
      throwsA(
        isA<FuriImportException>().having(
          (e) => e.message,
          'message',
          contains('行数不匹配'),
        ),
      ),
    );
  });

  test('parseFuriTxt 括号不成对时报错', () {
    expect(
      () => parseFuriTxt('夜[よる'),
      throwsA(isA<FuriImportException>()),
    );
    expect(
      () => parseFuriTxt('夜よる]'),
      throwsA(isA<FuriImportException>()),
    );
    expect(
      () => parseFuriTxt('[よる]夜'),
      throwsA(isA<FuriImportException>()),
    );
  });

  test('parseFuriTxt 支持送假名与の夹在汉字中', () {
    final parsed = parseFuriTxt('目[め]を閉じ[とじ]ては夕暮れ[ゆうぐれ]\n雲の上[くものうえ]では晴[はれ]る');
    expect(parsed.length, 2);
    expect(parsed[0].map((t) => t.surface).join(), '目を閉じては夕暮れ');
    expect(parsed[0][2].surface, '閉じ');
    expect(parsed[0][2].reading, 'とじ');
    expect(parsed[1][0].surface, '雲の上');
    expect(parsed[1][0].reading, 'くものうえ');
  });

  test('parseFuriTxt 可解析晴る导出样例行', () {
    final line = '通り雨[とおりあめ]　草[くさ]を靡か[なびか]せ';
    final parsed = parseFuriTxt(line);
    expect(parsed.single.map((t) => t.surface).join(), '通り雨　草を靡かせ');
    expect(parsed.single.where((t) => t.reading.isNotEmpty).map((t) => t.surface).toList(), [
      '通り雨',
      '草',
      '靡か',
    ]);
  });
}
