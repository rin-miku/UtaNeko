/// 与 Web 端 token 结构对齐，便于缓存 JSON 互读。
class FuriToken {
  const FuriToken({
    required this.surface,
    required this.reading,
    required this.pos,
    this.basicForm = '',
    this.hasBasicForm = true,
  });

  /// 表面形
  final String surface;

  /// 读音（片假名）
  final String reading;

  /// 词性大类
  final String pos;

  /// 基本形 / 原型
  final String basicForm;

  /// 缓存里是否写过基本形。旧缓存没有该字段时为 false，需要重新分词。
  final bool hasBasicForm;

  Map<String, dynamic> toJson() => {
        's': surface,
        'r': reading,
        'p': pos,
        'b': basicForm,
      };

  factory FuriToken.fromJson(Map<String, dynamic> json) => FuriToken(
        surface: json['s'] as String? ?? '',
        reading: json['r'] as String? ?? '',
        pos: json['p'] as String? ?? '',
        basicForm: json['b'] as String? ?? '',
        hasBasicForm: json.containsKey('b'),
      );
}
