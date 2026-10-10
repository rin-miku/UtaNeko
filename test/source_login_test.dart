import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/sources/kugou/kugou_auth.dart';
import 'package:utaneko/sources/qq/qq_auth.dart';

void main() {
  test('hash33 与网页端样例一致', () {
    expect(
      hash33(
        '475f17e1bfa3c8be809a2590b5bdbe40cb6fa05b9c7d0205f4dba83678a55640'
        '0e5e25ea73c90bf774a6321cd3577577f0b6c0cece90a41be687c016bce3d799',
      ),
      820087730,
    );
  });

  test('酷狗 web 签名按 key=value 排序', () {
    expect(
      kugouWebSign({'b': '2', 'a': '1'}),
      kugouWebSign({'a': '1', 'b': '2'}),
    );
  });
}
