import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../features/mini/boss_hide_controller.dart';
import '../../features/mini/mini_mode_controller.dart';
import '../../features/player/player_controller.dart';
import 'prefs.dart';

const hotkeyPrevLyricKey = 'utaneko:hotkey_prev_lyric';
const hotkeyNextLyricKey = 'utaneko:hotkey_next_lyric';
const hotkeyBossHideKey = 'utaneko:hotkey_boss_hide';
const hotkeyBossShowKey = 'utaneko:hotkey_boss_show';
const hotkeyPlayPauseKey = 'utaneko:hotkey_play_pause';
const hotkeyToggleMiniKey = 'utaneko:hotkey_toggle_mini';

const hotkeyIdPrevLyric = 'utaneko:prev_lyric';
const hotkeyIdNextLyric = 'utaneko:next_lyric';
const hotkeyIdBossHide = 'utaneko:boss_hide';
const hotkeyIdBossShow = 'utaneko:boss_show';
const hotkeyIdPlayPause = 'utaneko:play_pause';
const hotkeyIdToggleMini = 'utaneko:toggle_mini';

/// 允许的修饰键：Ctrl / Shift / Alt（不含 Win / Caps / Fn）。
const allowedHotkeyModifiers = {
  HotKeyModifier.control,
  HotKeyModifier.shift,
  HotKeyModifier.alt,
};

bool get isWindowsDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

HotKey defaultPrevLyricHotKey() => HotKey(
      identifier: hotkeyIdPrevLyric,
      key: PhysicalKeyboardKey.arrowUp,
      modifiers: const [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

HotKey defaultNextLyricHotKey() => HotKey(
      identifier: hotkeyIdNextLyric,
      key: PhysicalKeyboardKey.arrowDown,
      modifiers: const [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

HotKey defaultBossHideHotKey() => HotKey(
      identifier: hotkeyIdBossHide,
      key: PhysicalKeyboardKey.arrowLeft,
      modifiers: const [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

HotKey defaultBossShowHotKey() => HotKey(
      identifier: hotkeyIdBossShow,
      key: PhysicalKeyboardKey.arrowRight,
      modifiers: const [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

HotKey defaultPlayPauseHotKey() => HotKey(
      identifier: hotkeyIdPlayPause,
      key: PhysicalKeyboardKey.keyP,
      modifiers: const [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

HotKey defaultToggleMiniHotKey() => HotKey(
      identifier: hotkeyIdToggleMini,
      key: PhysicalKeyboardKey.keyM,
      modifiers: const [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

class HotkeyBindings {
  const HotkeyBindings({
    required this.prevLyric,
    required this.nextLyric,
    required this.bossHide,
    required this.bossShow,
    required this.playPause,
    required this.toggleMini,
  });

  final HotKey prevLyric;
  final HotKey nextLyric;
  final HotKey bossHide;
  final HotKey bossShow;
  final HotKey playPause;
  final HotKey toggleMini;

  List<HotKey> get all =>
      [prevLyric, nextLyric, bossHide, bossShow, playPause, toggleMini];

  HotkeyBindings copyWith({
    HotKey? prevLyric,
    HotKey? nextLyric,
    HotKey? bossHide,
    HotKey? bossShow,
    HotKey? playPause,
    HotKey? toggleMini,
  }) {
    return HotkeyBindings(
      prevLyric: prevLyric ?? this.prevLyric,
      nextLyric: nextLyric ?? this.nextLyric,
      bossHide: bossHide ?? this.bossHide,
      bossShow: bossShow ?? this.bossShow,
      playPause: playPause ?? this.playPause,
      toggleMini: toggleMini ?? this.toggleMini,
    );
  }
}

/// 校验结果：null 表示通过，否则为给用户看的中文提示。
String? validateHotKeyBinding(
  HotKey candidate, {
  List<HotKey> others = const [],
}) {
  final mods = candidate.modifiers ?? const <HotKeyModifier>[];
  if (mods.contains(HotKeyModifier.meta)) {
    return '不支持 Win 键作为修饰键';
  }
  if (mods.any((m) => !allowedHotkeyModifiers.contains(m))) {
    return '仅支持 Ctrl / Shift / Alt 作为修饰键';
  }
  final usable = mods.where(allowedHotkeyModifiers.contains).toList();
  if (usable.isEmpty) {
    return '请配合 Ctrl / Shift / Alt 使用';
  }
  if (_isModifierPhysicalKey(candidate.physicalKey)) {
    return '请按下主键（勿只按修饰键）';
  }
  for (final other in others) {
    if (hotKeysConflict(candidate, other)) {
      return '与另一快捷键冲突，请换一组';
    }
  }
  return null;
}

bool hotKeysConflict(HotKey a, HotKey b) {
  if (a.physicalKey != b.physicalKey) return false;
  final am = {...(a.modifiers ?? const <HotKeyModifier>[])}
    ..removeWhere((m) => !allowedHotkeyModifiers.contains(m));
  final bm = {...(b.modifiers ?? const <HotKeyModifier>[])}
    ..removeWhere((m) => !allowedHotkeyModifiers.contains(m));
  return am.length == bm.length && am.containsAll(bm);
}

bool _isModifierPhysicalKey(PhysicalKeyboardKey key) {
  for (final mod in HotKeyModifier.values) {
    if (mod.physicalKeys.contains(key)) return true;
  }
  return false;
}

String formatHotKeyLabel(HotKey hotKey) {
  final parts = <String>[];
  for (final mod in hotKey.modifiers ?? const <HotKeyModifier>[]) {
    parts.add(switch (mod) {
      HotKeyModifier.control => 'Ctrl',
      HotKeyModifier.shift => 'Shift',
      HotKeyModifier.alt => 'Alt',
      HotKeyModifier.meta => 'Win',
      HotKeyModifier.capsLock => 'Caps',
      HotKeyModifier.fn => 'Fn',
    });
  }
  parts.add(_physicalKeyLabel(hotKey.physicalKey));
  return parts.join(' + ');
}

String _physicalKeyLabel(PhysicalKeyboardKey key) {
  // 箭头键单独映射，保证设置页显示一致。
  if (key == PhysicalKeyboardKey.arrowUp) return '↑';
  if (key == PhysicalKeyboardKey.arrowDown) return '↓';
  if (key == PhysicalKeyboardKey.arrowLeft) return '←';
  if (key == PhysicalKeyboardKey.arrowRight) return '→';
  // 勿用 debugName：Release 下为 null，字母键会显示成「?」。
  // hotkey_manager 的 keyLabel 自带 A–Z / 数字等映射，Release 也可用。
  final label = key.keyLabel;
  if (label.isEmpty || label == 'Unknown') return '?';
  return label;
}

HotKey withStableId(HotKey source, String identifier) {
  return HotKey(
    identifier: identifier,
    key: source.key is PhysicalKeyboardKey
        ? source.key
        : source.physicalKey,
    modifiers: [
      for (final m in source.modifiers ?? const <HotKeyModifier>[])
        if (allowedHotkeyModifiers.contains(m)) m,
    ],
    scope: HotKeyScope.system,
  );
}

final hotkeyBindingsProvider =
    NotifierProvider<HotkeyBindingsNotifier, HotkeyBindings>(
  HotkeyBindingsNotifier.new,
);

class HotkeyBindingsNotifier extends Notifier<HotkeyBindings> {
  @override
  HotkeyBindings build() {
    if (!isWindowsDesktop) {
      return HotkeyBindings(
        prevLyric: defaultPrevLyricHotKey(),
        nextLyric: defaultNextLyricHotKey(),
        bossHide: defaultBossHideHotKey(),
        bossShow: defaultBossShowHotKey(),
        playPause: defaultPlayPauseHotKey(),
        toggleMini: defaultToggleMiniHotKey(),
      );
    }

    final prefs = ref.read(sharedPreferencesProvider);
    final bindings = HotkeyBindings(
      prevLyric: _load(prefs.getString(hotkeyPrevLyricKey), defaultPrevLyricHotKey),
      nextLyric: _load(prefs.getString(hotkeyNextLyricKey), defaultNextLyricHotKey),
      bossHide: _load(prefs.getString(hotkeyBossHideKey), defaultBossHideHotKey),
      bossShow: _load(prefs.getString(hotkeyBossShowKey), defaultBossShowHotKey),
      playPause:
          _load(prefs.getString(hotkeyPlayPauseKey), defaultPlayPauseHotKey),
      toggleMini:
          _load(prefs.getString(hotkeyToggleMiniKey), defaultToggleMiniHotKey),
    );

    ref.onDispose(() {
      unawaitedUnregisterAll();
    });

    Future.microtask(() async {
      try {
        await _reregister(bindings);
      } catch (_) {}
    });
    return bindings;
  }

  Future<void> unawaitedUnregisterAll() async {
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }

  HotKey _load(String? raw, HotKey Function() fallback) {
    final fb = fallback();
    if (raw == null || raw.isEmpty) return fb;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = HotKey.fromJson(map);
      return withStableId(parsed, fb.identifier);
    } catch (_) {
      return fb;
    }
  }

  Future<void> _persist(HotkeyBindings bindings) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      hotkeyPrevLyricKey,
      jsonEncode(bindings.prevLyric.toJson()),
    );
    await prefs.setString(
      hotkeyNextLyricKey,
      jsonEncode(bindings.nextLyric.toJson()),
    );
    await prefs.setString(
      hotkeyBossHideKey,
      jsonEncode(bindings.bossHide.toJson()),
    );
    await prefs.setString(
      hotkeyBossShowKey,
      jsonEncode(bindings.bossShow.toJson()),
    );
    await prefs.setString(
      hotkeyPlayPauseKey,
      jsonEncode(bindings.playPause.toJson()),
    );
    await prefs.setString(
      hotkeyToggleMiniKey,
      jsonEncode(bindings.toggleMini.toJson()),
    );
  }

  Future<void> _reregister(HotkeyBindings bindings) async {
    if (!isWindowsDesktop) return;
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}

    await hotKeyManager.register(
      bindings.prevLyric,
      keyDownHandler: (_) {
        ref.read(playerControllerProvider.notifier).seekPrevLyric();
      },
    );
    await hotKeyManager.register(
      bindings.nextLyric,
      keyDownHandler: (_) {
        ref.read(playerControllerProvider.notifier).seekNextLyric();
      },
    );
    await hotKeyManager.register(
      bindings.bossHide,
      keyDownHandler: (_) {
        ref.read(bossHideProvider.notifier).hideToTray();
      },
    );
    await hotKeyManager.register(
      bindings.bossShow,
      keyDownHandler: (_) {
        ref.read(bossHideProvider.notifier).reveal();
      },
    );
    await hotKeyManager.register(
      bindings.playPause,
      keyDownHandler: (_) {
        ref.read(playerControllerProvider.notifier).togglePlay();
      },
    );
    await hotKeyManager.register(
      bindings.toggleMini,
      keyDownHandler: (_) {
        ref.read(miniModeProvider.notifier).toggleMini();
      },
    );
  }

  List<HotKey> _othersExcept(HotkeyBindings b, String id) {
    return [
      for (final hk in b.all)
        if (hk.identifier != id) hk,
    ];
  }

  Future<String?> _apply(HotkeyBindings candidate) async {
    try {
      await _reregister(candidate);
    } catch (_) {
      try {
        await _reregister(state);
      } catch (_) {}
      return '快捷键注册失败，可能与系统或其他软件冲突';
    }
    state = candidate;
    await _persist(candidate);
    return null;
  }

  Future<String?> setPrevLyric(HotKey recorded) async {
    final next = withStableId(recorded, hotkeyIdPrevLyric);
    final err = validateHotKeyBinding(
      next,
      others: _othersExcept(state, hotkeyIdPrevLyric),
    );
    if (err != null) return err;
    return _apply(state.copyWith(prevLyric: next));
  }

  Future<String?> setNextLyric(HotKey recorded) async {
    final next = withStableId(recorded, hotkeyIdNextLyric);
    final err = validateHotKeyBinding(
      next,
      others: _othersExcept(state, hotkeyIdNextLyric),
    );
    if (err != null) return err;
    return _apply(state.copyWith(nextLyric: next));
  }

  Future<String?> setBossHide(HotKey recorded) async {
    final next = withStableId(recorded, hotkeyIdBossHide);
    final err = validateHotKeyBinding(
      next,
      others: _othersExcept(state, hotkeyIdBossHide),
    );
    if (err != null) return err;
    return _apply(state.copyWith(bossHide: next));
  }

  Future<String?> setBossShow(HotKey recorded) async {
    final next = withStableId(recorded, hotkeyIdBossShow);
    final err = validateHotKeyBinding(
      next,
      others: _othersExcept(state, hotkeyIdBossShow),
    );
    if (err != null) return err;
    return _apply(state.copyWith(bossShow: next));
  }

  Future<String?> setPlayPause(HotKey recorded) async {
    final next = withStableId(recorded, hotkeyIdPlayPause);
    final err = validateHotKeyBinding(
      next,
      others: _othersExcept(state, hotkeyIdPlayPause),
    );
    if (err != null) return err;
    return _apply(state.copyWith(playPause: next));
  }

  Future<String?> setToggleMini(HotKey recorded) async {
    final next = withStableId(recorded, hotkeyIdToggleMini);
    final err = validateHotKeyBinding(
      next,
      others: _othersExcept(state, hotkeyIdToggleMini),
    );
    if (err != null) return err;
    return _apply(state.copyWith(toggleMini: next));
  }

  Future<String?> resetToDefaults() async {
    final candidate = HotkeyBindings(
      prevLyric: defaultPrevLyricHotKey(),
      nextLyric: defaultNextLyricHotKey(),
      bossHide: defaultBossHideHotKey(),
      bossShow: defaultBossShowHotKey(),
      playPause: defaultPlayPauseHotKey(),
      toggleMini: defaultToggleMiniHotKey(),
    );
    return _apply(candidate);
  }
}
