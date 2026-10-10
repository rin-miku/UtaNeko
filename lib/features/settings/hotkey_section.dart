import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/storage/hotkey_bindings.dart';

/// Windows 全局快捷键设置栏（录制 / 冲突提示 / 恢复默认）。
class HotkeySection extends ConsumerWidget {
  const HotkeySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isWindowsDesktop) return const SizedBox.shrink();

    final bindings = ref.watch(hotkeyBindingsProvider);
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        const ListTile(
          title: Text('快捷键'),
          subtitle: Text('仅 Windows · 全局生效 · 点击后按下想要的组合键'),
        ),
        ListTile(
          title: const Text('上一句歌词'),
          subtitle: Text(
            formatHotKeyLabel(bindings.prevLyric),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          trailing: OutlinedButton(
            onPressed: () => _record(
              context,
              ref,
              title: '设置「上一句」快捷键',
              current: bindings.prevLyric,
              others: bindings.all
                  .where((e) => e.identifier != bindings.prevLyric.identifier)
                  .toList(),
              onSave: (hk) =>
                  ref.read(hotkeyBindingsProvider.notifier).setPrevLyric(hk),
            ),
            child: const Text('更改'),
          ),
        ),
        ListTile(
          title: const Text('下一句歌词'),
          subtitle: Text(
            formatHotKeyLabel(bindings.nextLyric),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          trailing: OutlinedButton(
            onPressed: () => _record(
              context,
              ref,
              title: '设置「下一句」快捷键',
              current: bindings.nextLyric,
              others: bindings.all
                  .where((e) => e.identifier != bindings.nextLyric.identifier)
                  .toList(),
              onSave: (hk) =>
                  ref.read(hotkeyBindingsProvider.notifier).setNextLyric(hk),
            ),
            child: const Text('更改'),
          ),
        ),
        ListTile(
          title: const Text('老板键 · 隐藏到托盘'),
          subtitle: Text(
            formatHotKeyLabel(bindings.bossHide),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          trailing: OutlinedButton(
            onPressed: () => _record(
              context,
              ref,
              title: '设置「隐藏到托盘」快捷键',
              current: bindings.bossHide,
              others: bindings.all
                  .where((e) => e.identifier != bindings.bossHide.identifier)
                  .toList(),
              onSave: (hk) =>
                  ref.read(hotkeyBindingsProvider.notifier).setBossHide(hk),
            ),
            child: const Text('更改'),
          ),
        ),
        ListTile(
          title: const Text('老板键 · 显示窗口'),
          subtitle: Text(
            formatHotKeyLabel(bindings.bossShow),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          trailing: OutlinedButton(
            onPressed: () => _record(
              context,
              ref,
              title: '设置「显示窗口」快捷键',
              current: bindings.bossShow,
              others: bindings.all
                  .where((e) => e.identifier != bindings.bossShow.identifier)
                  .toList(),
              onSave: (hk) =>
                  ref.read(hotkeyBindingsProvider.notifier).setBossShow(hk),
            ),
            child: const Text('更改'),
          ),
        ),
        ListTile(
          title: const Text('暂停 / 播放'),
          subtitle: Text(
            formatHotKeyLabel(bindings.playPause),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          trailing: OutlinedButton(
            onPressed: () => _record(
              context,
              ref,
              title: '设置「暂停/播放」快捷键',
              current: bindings.playPause,
              others: bindings.all
                  .where((e) => e.identifier != bindings.playPause.identifier)
                  .toList(),
              onSave: (hk) =>
                  ref.read(hotkeyBindingsProvider.notifier).setPlayPause(hk),
            ),
            child: const Text('更改'),
          ),
        ),
        ListTile(
          title: const Text('切换 Mini 模式'),
          subtitle: Text(
            formatHotKeyLabel(bindings.toggleMini),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          trailing: OutlinedButton(
            onPressed: () => _record(
              context,
              ref,
              title: '设置「切换 Mini」快捷键',
              current: bindings.toggleMini,
              others: bindings.all
                  .where((e) => e.identifier != bindings.toggleMini.identifier)
                  .toList(),
              onSave: (hk) =>
                  ref.read(hotkeyBindingsProvider.notifier).setToggleMini(hk),
            ),
            child: const Text('更改'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () async {
                final err =
                    await ref.read(hotkeyBindingsProvider.notifier).resetToDefaults();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      err ??
                          '已恢复默认：Ctrl+↑/↓ 切句，Ctrl+←/→ 老板键，Ctrl+P 播放，Ctrl+M Mini',
                    ),
                  ),
                );
              },
              child: const Text('恢复默认'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _record(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required HotKey current,
    required List<HotKey> others,
    required Future<String?> Function(HotKey) onSave,
  }) async {
    final result = await showDialog<HotKey>(
      context: context,
      builder: (ctx) => _HotKeyRecordDialog(
        title: title,
        initial: current,
        others: others,
      ),
    );
    if (result == null || !context.mounted) return;

    final err = await onSave(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '快捷键已更新：${formatHotKeyLabel(result)}')),
    );
  }
}

class _HotKeyRecordDialog extends StatefulWidget {
  const _HotKeyRecordDialog({
    required this.title,
    required this.initial,
    required this.others,
  });

  final String title;
  final HotKey initial;
  final List<HotKey> others;

  @override
  State<_HotKeyRecordDialog> createState() => _HotKeyRecordDialogState();
}

class _HotKeyRecordDialogState extends State<_HotKeyRecordDialog> {
  HotKey? _preview;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _preview = widget.initial;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }

    final physicalKeysPressed = HardwareKeyboard.instance.physicalKeysPressed;
    final key = event.physicalKey;

    if (_isModifierKey(key)) return true;

    var modifiers = HotKeyModifier.values
        .where((e) => e.physicalKeys.any(physicalKeysPressed.contains))
        .where((e) => !e.physicalKeys.contains(key))
        .toList();

    final hasMeta = modifiers.contains(HotKeyModifier.meta);
    modifiers = modifiers.where(allowedHotkeyModifiers.contains).toList();

    final candidate = HotKey(
      identifier: widget.initial.identifier,
      key: key,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );

    if (hasMeta) {
      const msg = '不支持 Win 键作为修饰键';
      setState(() {
        _preview = candidate;
        _hint = msg;
      });
      _toast(msg);
      return true;
    }

    final err = validateHotKeyBinding(candidate, others: widget.others);
    if (err != null) {
      setState(() {
        _preview = candidate;
        _hint = err;
      });
      _toast(err);
      return true;
    }

    Navigator.of(context).pop(candidate);
    return true;
  }

  bool _isModifierKey(PhysicalKeyboardKey key) {
    for (final mod in HotKeyModifier.values) {
      if (mod.physicalKeys.contains(key)) return true;
    }
    return false;
  }

  void _toast(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '请按下组合键（需含 Ctrl / Shift / Alt，Esc 取消）',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            _preview == null ? '等待输入…' : formatHotKeyLabel(_preview!),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_hint != null) ...[
            const SizedBox(height: 12),
            Text(_hint!, style: TextStyle(color: colors.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
