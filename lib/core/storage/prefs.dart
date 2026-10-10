import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在 main 中通过 override 注入，避免业务层重复 getInstance。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('请在 main 中 override sharedPreferencesProvider');
});
