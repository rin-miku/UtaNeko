import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/sources/netease/weapi.dart';

void main() {
  test('weapi 固定 secret 时 params/encSecKey 与 Node 一致', () {
    final r = Weapi.encrypt(
      {
        'ids': [123],
        'br': 320000,
        'csrf_token': '',
      },
      secretOverride: '0123456789abcdef',
    );

    expect(
      r.params,
      'z9rfI6MsSox2iU3FhYDGxgVX4WwVgvuJtE+8UmGGakC7BFmWxu2hsdn+cm/8KR8s+9TIXKbN257G+7divg2JBaMje8m1QEAGDCIcvdyEd4M=',
    );
    expect(
      r.encSecKey,
      '35701388baf89fed412e11269b9c76625d095ecaf17f03fa018abe19ea2d38b949debf242ee39a71ca1f6cda71b1b86a45aa909ee27f7e78e267d34e732f0de948206c3340a788d0003372183e2f753c1f78b66ac23d134ac1fc9b993156520ea826b8aa89a962d4491b4b8d7e08738e1da9b07aa39bf4a7ef0b1c210728cd52',
    );
  });
}
