/// 单行歌词（原文 + 可选翻译）。
class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
  });

  final Duration time;
  final String text;
  final String? translation;
}

/// 移植 public/app.js 的 parseLRC + 翻译时间对齐。
abstract final class LrcParser {
  static List<LyricLine> parse(String raw, {String translatedRaw = ''}) {
    final lines = _parseRaw(raw);
    if (lines.isEmpty) return const [];

    final tr = translatedRaw.trim().isEmpty ? const <_Timed>[] : _parseRaw(translatedRaw);
    var ti = 0;

    return [
      for (final ln in lines)
        LyricLine(
          time: ln.time,
          text: ln.text,
          translation: () {
            if (tr.isEmpty) return null;
            String? matched;
            while (ti < tr.length &&
                tr[ti].time.inMilliseconds <= ln.time.inMilliseconds + 600) {
              if ((tr[ti].time - ln.time).abs() <
                  const Duration(milliseconds: 800)) {
                matched = tr[ti].text;
              }
              ti++;
            }
            return matched;
          }(),
        ),
    ];
  }

  static List<_Timed> _parseRaw(String raw) {
    if (raw.isEmpty) return const [];
    final out = <_Timed>[];
    final timeRe = RegExp(r'\[(\d{1,3}):(\d{1,2}(?:\.\d{1,3})?)\]');

    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final times = timeRe.allMatches(line).toList();
      if (times.isEmpty) continue;
      final text = line.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
      if (text.isEmpty) continue;

      for (final m in times) {
        final mm = int.parse(m.group(1)!);
        final rest = m.group(2)!;
        final dot = rest.indexOf('.');
        final ss =
            dot == -1 ? int.parse(rest) : int.parse(rest.substring(0, dot));
        final frac =
            dot == -1 ? 0.0 : double.parse('0.${rest.substring(dot + 1)}');
        out.add(
          _Timed(
            Duration(milliseconds: ((mm * 60 + ss + frac) * 1000).round()),
            text,
          ),
        );
      }
    }

    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}

class _Timed {
  const _Timed(this.time, this.text);
  final Duration time;
  final String text;
}
