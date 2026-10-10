import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const neteaseCookieKey = 'utaneko:netease_cookie';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final cookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore(ref.watch(secureStorageProvider));
});

final qqCookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore(
    ref.watch(secureStorageProvider),
    storageKey: 'utaneko:auth:qq',
  );
});

final kugouCookieStoreProvider = Provider<CookieStore>((ref) {
  return CookieStore(
    ref.watch(secureStorageProvider),
    storageKey: 'utaneko:auth:kugou',
  );
});

/// 各源登录凭证仅存本机。网易云沿用原来的 key，避免已保存的 Cookie 失效。
class CookieStore {
  CookieStore(this._storage, {String? storageKey})
      : _key = storageKey ?? neteaseCookieKey;

  final FlutterSecureStorage _storage;
  final String _key;

  Future<String> read() async => await _storage.read(key: _key) ?? '';

  Future<void> write(String cookie) async {
    final v = cookie.trim();
    if (v.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: v);
    }
  }

  Future<bool> get hasCookie async => (await read()).isNotEmpty;
}

final cookieStatusProvider = FutureProvider<bool>((ref) async {
  return ref.watch(cookieStoreProvider).hasCookie;
});

final qqCookieStatusProvider = FutureProvider<bool>((ref) async {
  return ref.watch(qqCookieStoreProvider).hasCookie;
});

final kugouCookieStatusProvider = FutureProvider<bool>((ref) async {
  return ref.watch(kugouCookieStoreProvider).hasCookie;
});
