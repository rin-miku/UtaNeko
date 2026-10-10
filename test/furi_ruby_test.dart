import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/core/furigana/furi_ruby.dart';
import 'package:utaneko/core/furigana/furi_token.dart';

void main() {
  test('toHiragana 片假名转平假名', () {
    expect(toHiragana('カタカナ'), 'かたかな');
  });

  test('旧缓存缺少基本形时标记为未持久化', () {
    final old = FuriToken.fromJson({'s': '働', 'r': 'ハタラク', 'p': '動詞'});
    expect(old.hasBasicForm, isFalse);
    final fresh = FuriToken.fromJson({
      's': '働',
      'r': 'ハタラク',
      'p': '動詞',
      'b': '働く',
    });
    expect(fresh.hasBasicForm, isTrue);
    expect(fresh.basicForm, '働く');
  });

  test('needsRuby 汉字带读音才注音', () {
    expect(
      needsRuby(const FuriToken(surface: '働', reading: 'ハタラク', pos: '動詞')),
      isTrue,
    );
    expect(
      needsRuby(const FuriToken(surface: 'a', reading: '', pos: '記号')),
      isFalse,
    );
  });
}
