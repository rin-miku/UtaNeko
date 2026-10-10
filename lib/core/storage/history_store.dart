import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sources/models.dart';
import 'prefs.dart';

const _histKey = 'utaneko:hist';
const _histMax = 10;

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(sharedPreferencesProvider));
});

final historyProvider =
    NotifierProvider<HistoryNotifier, List<TrackMeta>>(HistoryNotifier.new);

class HistoryRepository {
  HistoryRepository(this._prefs);

  final SharedPreferences _prefs;

  List<TrackMeta> load() {
    final raw = _prefs.getString(_histKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      final items = [
        for (final e in list)
          if (e is Map) TrackMeta.fromJson(Map<String, dynamic>.from(e)),
      ];
      if (items.length <= _histMax) return items;
      final trimmed = items.take(_histMax).toList();
      unawaited(save(trimmed));
      return trimmed;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<TrackMeta> items) async {
    await _prefs.setString(
      _histKey,
      jsonEncode([for (final t in items) t.toJson()]),
    );
  }
}

class HistoryNotifier extends Notifier<List<TrackMeta>> {
  @override
  List<TrackMeta> build() => ref.watch(historyRepositoryProvider).load();

  Future<void> push(TrackMeta track) async {
    final next = [
      track,
      ...state.where((t) => t.id != track.id),
    ].take(_histMax).toList();
    state = next;
    await ref.read(historyRepositoryProvider).save(next);
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(historyRepositoryProvider).save(state);
  }
}
