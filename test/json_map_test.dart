import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/sources/netease/netease_source.dart';

void main() {
  test('asJsonMap 解析 Map 与 JSON 字符串', () {
    expect(asJsonMap({'code': 200})['code'], 200);
    expect(asJsonMap('{"code":200,"songs":[]}')['code'], 200);
  });

  test('asJsonMap 非法内容抛错', () {
    expect(() => asJsonMap('<html>'), throwsStateError);
    expect(() => asJsonMap(null), throwsStateError);
  });
}
