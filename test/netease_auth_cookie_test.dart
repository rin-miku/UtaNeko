import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/sources/netease/eapi.dart';
import 'package:utaneko/sources/netease/netease_auth.dart';

void main() {
  test('Set-Cookie 只保留 name=value，并拼成 Cookie 头', () {
    final cookie = cookiePairsFromSetCookie([
      'MUSIC_U=abc; Max-Age=1296000; Path=/; Domain=.music.163.com',
      '__csrf=token; Path=/',
    ]);
    expect(cookie, 'MUSIC_U=abc; __csrf=token');
  });

  test('eapi 与 Node 样例一致', () {
    expect(
      Eapi.formFields('/api/login/qrcode/unikey', {'type': 1})['params'],
      '1CA81A97B7BAEB099F29A9B99A25CD6E58E7BA5B35F25231033065C776830C0A'
      'E9501BB40807A3A221D4F4389D41380F74EE53123086A844BA0B2684B90B43C1'
      'A412AA65A18F2D654CBEC160231A6793481C9F88AFE922DDDC7C50BEFC29A135',
    );
  });

  test('空列表不产生 Cookie', () {
    expect(cookiePairsFromSetCookie(null), isNull);
    expect(cookiePairsFromSetCookie([]), isNull);
  });
}
