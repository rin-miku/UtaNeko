import 'furi_ruby.dart';
import 'furi_token.dart';

/// 注音 TXT 解析/导入错误。
class FuriImportException implements Exception {
  const FuriImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

final _kanjiChar = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]');

/// 编码为 Anki 风格：`汉字[读音]`，一句一行。
String encodeFuriTxt(List<List<FuriToken>> tokenLines) {
  return tokenLines.map((line) {
    final buf = StringBuffer();
    for (final t in line) {
      if (t.surface.isEmpty) continue;
      if (needsRuby(t)) {
        buf.write('${t.surface}[${toHiragana(t.reading)}]');
      } else {
        buf.write(t.surface);
      }
    }
    return buf.toString();
  }).join('\n');
}

/// 解析 `furi.txt`：每行一组 token；`表面[读音]` 为带注音段。
List<List<FuriToken>> parseFuriTxt(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // 编辑器常在末尾多一个换行，剥掉一个以免多出空行。
  if (text.endsWith('\n')) {
    text = text.substring(0, text.length - 1);
  }
  final lines = text.split('\n');
  return [for (var i = 0; i < lines.length; i++) _parseLine(lines[i], i + 1)];
}

List<FuriToken> _parseLine(String line, int lineNo) {
  final tokens = <FuriToken>[];
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (ch == '[') {
      throw FuriImportException('第 $lineNo 行：读音括号前缺少汉字');
    }
    if (ch == ']') {
      throw FuriImportException('第 $lineNo 行：多余的 ]');
    }

    final bracket = line.indexOf('[', i);
    if (bracket == -1) {
      final rest = line.substring(i);
      if (rest.contains(']')) {
        throw FuriImportException('第 $lineNo 行：多余的 ]');
      }
      tokens.add(FuriToken(
        surface: rest,
        reading: '',
        pos: '',
        basicForm: rest,
      ));
      break;
    }

    final before = line.substring(i, bracket);
    final close = line.indexOf(']', bracket + 1);
    if (close == -1) {
      throw FuriImportException('第 $lineNo 行：缺少配对的 ]');
    }
    final nested = line.indexOf('[', bracket + 1);
    if (nested != -1 && nested < close) {
      throw FuriImportException('第 $lineNo 行：不支持嵌套 []');
    }
    final reading = line.substring(bracket + 1, close);
    if (reading.isEmpty) {
      throw FuriImportException('第 $lineNo 行：[] 内读音为空');
    }
    if (before.isEmpty) {
      throw FuriImportException('第 $lineNo 行：读音括号前缺少汉字');
    }

    // 注音表面形 = 从第一个汉字起直到 '['（含送假名，如 閉じ[とじ]、雲の上[くものうえ]）
    final split = _splitPlainAndSurface(before);
    if (split.plain.isNotEmpty) {
      tokens.add(FuriToken(
        surface: split.plain,
        reading: '',
        pos: '',
        basicForm: split.plain,
      ));
    }
    if (split.surface.isEmpty) {
      throw FuriImportException('第 $lineNo 行：读音括号前缺少汉字');
    }
    tokens.add(FuriToken(
      surface: split.surface,
      reading: reading,
      pos: '',
      basicForm: split.surface,
    ));
    i = close + 1;
  }
  return tokens;
}

/// 拆成「纯假名/符号前缀」+「含汉字的注音表面形（可带送假名）」。
({String plain, String surface}) _splitPlainAndSurface(String before) {
  if (before.isEmpty) return (plain: '', surface: '');
  var firstKanji = -1;
  for (var i = 0; i < before.length; i++) {
    if (_kanjiChar.hasMatch(before[i])) {
      firstKanji = i;
      break;
    }
  }
  if (firstKanji == -1) return (plain: before, surface: '');
  return (
    plain: before.substring(0, firstKanji),
    surface: before.substring(firstKanji),
  );
}

/// 校验行数；不匹配则抛 [FuriImportException]。
void validateFuriLineCount(List<List<FuriToken>> tokens, int lineCount) {
  if (tokens.length != lineCount) {
    throw FuriImportException(
      '行数不匹配：文件 ${tokens.length} 行，当前歌词 $lineCount 行',
    );
  }
}
