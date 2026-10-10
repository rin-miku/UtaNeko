import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/storage/cookie_store.dart';
import '../../sources/auth/source_auth.dart';
import '../../sources/kugou/kugou_auth.dart';
import '../../sources/netease/netease_auth.dart';
import '../../sources/qq/qq_auth.dart';
import 'qr_login_dialog.dart';

/// 音源登录标签：一次只展示当前选中源的 Cookie、扫码和清除。
class SourceLoginTabs extends ConsumerStatefulWidget {
  const SourceLoginTabs({super.key});

  @override
  ConsumerState<SourceLoginTabs> createState() => _SourceLoginTabsState();
}

class _SourceLoginTabsState extends ConsumerState<SourceLoginTabs>
    with TickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final netease = ref.watch(cookieStatusProvider);
    final qq = ref.watch(qqCookieStatusProvider);
    final kugou = ref.watch(kugouCookieStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            _tab('网易云', netease),
            _tab('QQ音乐', qq),
            _tab('酷狗', kugou),
          ],
        ),
        ListenableBuilder(
          listenable: _tabs,
          builder: (context, _) => IndexedStack(
            index: _tabs.index,
            children: [
              SourceLoginSection(
                auth: ref.watch(neteaseAuthProvider),
                cookies: ref.watch(cookieStoreProvider),
                status: netease,
                onChanged: () => ref.invalidate(cookieStatusProvider),
                loggedIn: '已登录 · VIP 可尝试解锁',
                loggedOut: '未登录 · 部分歌曲仅试听',
                fieldHint: 'MUSIC_U=xxxxxxxx;',
                manualHint:
                    '不想扫码时，可在浏览器登录 music.163.com，'
                    '从开发者工具 → Application → Cookies 复制 MUSIC_U。'
                    '与扫码得到的是同一份登录凭证，仅存本机。',
              ),
              SourceLoginSection(
                auth: ref.watch(qqAuthProvider),
                cookies: ref.watch(qqCookieStoreProvider),
                status: qq,
                onChanged: () => ref.invalidate(qqCookieStatusProvider),
                loggedIn: '已登录 · 凭证在本机',
                loggedOut: '未登录',
                fieldHint: 'qm_keyst=...; uin=...',
                manualHint:
                    '不想扫码时，可在浏览器登录 y.qq.com，'
                    '从开发者工具复制 Cookie（含 qm_keyst 或 qqmusic_key）。仅存本机。',
              ),
              SourceLoginSection(
                auth: ref.watch(kugouAuthProvider),
                cookies: ref.watch(kugouCookieStoreProvider),
                status: kugou,
                onChanged: () => ref.invalidate(kugouCookieStatusProvider),
                loggedIn: '已登录 · 凭证在本机',
                loggedOut: '未登录',
                fieldHint: 'token=...; userid=...',
                manualHint:
                    '不想扫码时，可在浏览器登录 www.kugou.com，'
                    '从开发者工具复制 Cookie（含 token 和 userid）。仅存本机。',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tab(String label, AsyncValue<bool> status) {
    final on = status.maybeWhen(data: (has) => has, orElse: () => false);
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (on) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.circle,
              size: 8,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个音源的扫码登录和手动 Cookie。
class SourceLoginSection extends ConsumerStatefulWidget {
  const SourceLoginSection({
    super.key,
    required this.auth,
    required this.cookies,
    required this.status,
    required this.onChanged,
    required this.loggedIn,
    required this.loggedOut,
    required this.fieldHint,
    required this.manualHint,
  });

  final SourceAuth auth;
  final CookieStore cookies;
  final AsyncValue<bool> status;
  final void Function() onChanged;
  final String loggedIn;
  final String loggedOut;
  final String fieldHint;
  final String manualHint;

  @override
  ConsumerState<SourceLoginSection> createState() => _SourceLoginSectionState();
}

class _SourceLoginSectionState extends ConsumerState<SourceLoginSection> {
  final _cookieCtrl = TextEditingController();
  var _loaded = false;

  @override
  void dispose() {
    _cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    _cookieCtrl.text = await widget.cookies.read();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    _load();
    final status = widget.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(
            status.when(
              data: (has) => has ? widget.loggedIn : widget.loggedOut,
              loading: () => '读取中…',
              error: (_, _) => '读取失败',
            ),
            style: TextStyle(
              color: colors.fgDim,
              fontSize: 13,
              fontWeight: FontWeight.normal,
            ),
          ),
          trailing: Icon(
            Icons.circle,
            size: 10,
            color: status.maybeWhen(
              data: (has) =>
                  has ? Theme.of(context).colorScheme.primary : colors.fgDim,
              orElse: () => colors.fgDim,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => QrLoginDialog(auth: widget.auth),
                );
                if (ok != true || !context.mounted) return;
                _cookieCtrl.text = await widget.cookies.read();
                widget.onChanged();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已登录，凭证仅保存在本机')),
                );
              },
              child: const Text('扫码登录'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('手动填写 Cookie', style: TextStyle(color: colors.fgDim)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _cookieCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: widget.fieldHint,
              alignLabelWithHint: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  await widget.auth.saveManual(_cookieCtrl.text);
                  widget.onChanged();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _cookieCtrl.text.trim().isEmpty ? 'Cookie 已清除' : 'Cookie 已保存',
                      ),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.danger,
                ),
                onPressed: () async {
                  _cookieCtrl.clear();
                  await widget.auth.logout();
                  widget.onChanged();
                },
                child: const Text('清除'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            widget.manualHint,
            style: TextStyle(color: colors.fgDim, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}
