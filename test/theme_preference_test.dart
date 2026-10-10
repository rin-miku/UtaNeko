import 'package:flutter_test/flutter_test.dart';
import 'package:utaneko/app/theme/theme_preference.dart';

void main() {
  test('主题偏好默认跟随系统', () {
    expect(ThemeModePreference.fromStorage(null), ThemeModePreference.system);
    expect(ThemeModePreference.fromStorage('oops'), ThemeModePreference.system);
  });

  test('主题偏好往返序列化', () {
    for (final p in ThemeModePreference.values) {
      expect(ThemeModePreference.fromStorage(p.storageValue), p);
    }
  });
}
