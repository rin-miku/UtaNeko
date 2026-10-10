import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/local/local_song_folder.dart';
import '../../core/lyric/lrc_parser.dart';
import '../../core/storage/cookie_store.dart';
import '../../core/storage/history_store.dart';
import '../../core/storage/prefs.dart';
import '../../sources/kugou/kugou_source.dart';
import '../../sources/models.dart';
import '../../sources/music_source.dart';
import '../../sources/netease/netease_source.dart';
import '../../sources/qq/qq_source.dart';

const _brKey = 'utaneko:br';
const _transKey = 'utaneko:trans';
const _volKey = 'utaneko:vol';
const _sourceKey = 'utaneko:source';

/// 首页手动选择的音源：netease / qq / kugou。
final selectedSourceIdProvider =
    NotifierProvider<SelectedSourceId, String>(SelectedSourceId.new);

class SelectedSourceId extends Notifier<String> {
  static const supported = ['netease', 'qq', 'kugou'];

  @override
  String build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_sourceKey);
    if (saved != null && supported.contains(saved)) return saved;
    return 'netease';
  }

  Future<void> set(String id) async {
    if (!supported.contains(id) || id == state) return;
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_sourceKey, id);
  }
}

final musicSourceProvider = Provider<MusicSource>((ref) {
  final sourceId = ref.watch(selectedSourceIdProvider);
  switch (sourceId) {
    case 'qq':
      final cookies = ref.watch(qqCookieStoreProvider);
      return QqSource(cookieReader: cookies.read);
    case 'kugou':
      final cookies = ref.watch(kugouCookieStoreProvider);
      return KugouSource(cookieReader: cookies.read);
    case 'netease':
    default:
      final cookies = ref.watch(cookieStoreProvider);
      return NeteaseSource(cookieReader: cookies.read);
  }
});

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerViewState>(PlayerController.new);

class PlayerViewState {
  const PlayerViewState({
    this.track,
    this.lines = const [],
    this.lyricIndex = -1,
    this.quality = AudioQuality.k320,
    this.showTranslation = true,
    this.loading = false,
    this.error,
    this.trialHint,
    this.levelInfo,
  });

  final TrackMeta? track;
  final List<LyricLine> lines;
  final int lyricIndex;
  final AudioQuality quality;
  final bool showTranslation;
  final bool loading;
  final String? error;
  final String? trialHint;
  final String? levelInfo;

  PlayerViewState copyWith({
    TrackMeta? track,
    List<LyricLine>? lines,
    int? lyricIndex,
    AudioQuality? quality,
    bool? showTranslation,
    bool? loading,
    String? error,
    bool clearError = false,
    String? trialHint,
    bool clearTrial = false,
    String? levelInfo,
  }) {
    return PlayerViewState(
      track: track ?? this.track,
      lines: lines ?? this.lines,
      lyricIndex: lyricIndex ?? this.lyricIndex,
      quality: quality ?? this.quality,
      showTranslation: showTranslation ?? this.showTranslation,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      trialHint: clearTrial ? null : (trialHint ?? this.trialHint),
      levelInfo: levelInfo ?? this.levelInfo,
    );
  }
}

class PlayerController extends Notifier<PlayerViewState> {
  late final AudioPlayer _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerException>? _errSub;
  List<LyricLine> _lines = const [];
  String? _lrcRaw;
  String? _translatedLrc;
  String? _lastPlayUrl;

  /// 本地曲夹导入注音用；Home playReady 时消费并清空。
  String? pendingFuriTxt;

  AudioPlayer get player => _player;
  String? get lrcRaw => _lrcRaw;
  /// 翻译 LRC 原文（对应下载旁路 `lyrics.trans.lrc`）。
  String? get translatedLrc => _translatedLrc;

  String? takePendingFuriTxt() {
    final t = pendingFuriTxt;
    pendingFuriTxt = null;
    return t;
  }

  @override
  PlayerViewState build() {
    _player = AudioPlayer();
    ref.onDispose(() {
      _posSub?.cancel();
      _errSub?.cancel();
      _player.dispose();
    });

    final prefs = ref.read(sharedPreferencesProvider);
    final quality = AudioQuality.fromBr(int.tryParse(prefs.getString(_brKey) ?? ''));
    final showTrans = prefs.getBool(_transKey) ?? true;
    final vol = prefs.getDouble(_volKey);
    if (vol != null) {
      unawaited(_player.setVolume(vol.clamp(0.0, 1.0)));
    }

    _posSub = _player.positionStream.listen(_onPosition);
    _errSub = _player.errorStream.listen((e) {
      final msg = (e.message == null || e.message!.isEmpty)
          ? e.toString()
          : e.message!;
      state = state.copyWith(loading: false, error: msg);
    });

    return PlayerViewState(quality: quality, showTranslation: showTrans);
  }

  Future<void> resolveAndPlay(String input) async {
    final q = input.trim();
    if (q.isEmpty) return;

    state = state.copyWith(loading: true, clearError: true, clearTrial: true);
    try {
      final source = ref.read(musicSourceProvider);
      final meta = await source.resolve(q);
      await playTrack(meta);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> playTrack(TrackMeta meta) async {
    if (isLocalTrackId(meta.id)) {
      final path = localFolderPathFromId(meta.id);
      if (path == null || path.isEmpty) {
        state = state.copyWith(loading: false, error: '无效的本地曲目');
        return;
      }
      await playLocalFolder(Directory(path));
      return;
    }

    pendingFuriTxt = null;
    _lrcRaw = null;
    _translatedLrc = null;
    state = state.copyWith(
      loading: true,
      track: meta,
      clearError: true,
      clearTrial: true,
      lyricIndex: -1,
    );

    final source = ref.read(musicSourceProvider);
    try {
      final lyricFut = source.getLyric(meta.id);
      final urlFut = source.getPlayUrl(meta.id, quality: state.quality);

      final lyric = await lyricFut;
      _lrcRaw = lyric.lrc;
      _translatedLrc =
          lyric.translatedLrc.trim().isEmpty ? null : lyric.translatedLrc;
      _lines = LrcParser.parse(lyric.lrc, translatedRaw: lyric.translatedLrc);
      state = state.copyWith(lines: _lines);

      final play = await urlFut;
      _lastPlayUrl = play.url;
      if (play.url == null || play.url!.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: '无法获取播放地址（可能是 VIP，请在设置中配置 Cookie）',
        );
        return;
      }

      String? trialHint;
      if (play.isTrial) {
        trialHint =
            'VIP 试听约 ${play.freeTrialEndSec ?? 30} 秒 — 设置中配置 Cookie 可听完整版';
      }
      final level = [
        if (play.level != null) play.level,
        if (play.br != null) '${(play.br! / 1000).round()}K',
      ].join(' ');

      await _setAudioUri(Uri.parse(play.url!), headers: true);
      // 安卓上 play() 要等到歌曲结束（或暂停/拖动）才完成，不能 await。
      _beginPlay();

      await ref.read(historyProvider.notifier).push(meta);

      state = state.copyWith(
        loading: false,
        trialHint: trialHint,
        clearTrial: trialHint == null,
        levelInfo: level.isEmpty ? null : level,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// 打开本地下载约定的单曲文件夹并播放。
  Future<void> playLocalFolder(Directory dir) async {
    state = state.copyWith(
      loading: true,
      clearError: true,
      clearTrial: true,
      lyricIndex: -1,
    );
    pendingFuriTxt = null;

    try {
      final bundle = await loadLocalSongFolder(dir);
      final absDir = dir.absolute.path;
      final meta = TrackMeta(
        id: 'local:$absDir',
        title: bundle.title,
        artists: bundle.artists,
        album: '',
        coverUrl: bundle.coverPath ?? '',
        durationMs: 0,
      );

      _lrcRaw = bundle.lrcRaw;
      _translatedLrc = bundle.translatedLrc;
      _lines = (bundle.lrcRaw != null && bundle.lrcRaw!.isNotEmpty)
          ? LrcParser.parse(
              bundle.lrcRaw!,
              translatedRaw: bundle.translatedLrc ?? '',
            )
          : const [];
      _lastPlayUrl = null;
      if (_lines.isNotEmpty &&
          bundle.furiTxt != null &&
          bundle.furiTxt!.trim().isNotEmpty) {
        pendingFuriTxt = bundle.furiTxt;
      }

      state = state.copyWith(track: meta, lines: _lines);

      await _setAudioUri(Uri.file(bundle.audioPath), headers: false);
      _beginPlay();

      await ref.read(historyProvider.notifier).push(meta);

      state = state.copyWith(
        loading: false,
        clearTrial: true,
        levelInfo: '本地',
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      _beginPlay();
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> seekLyric(int index) async {
    if (index < 0 || index >= _lines.length) return;
    await _player.seek(_lines[index].time);
    // 点击歌词 / 上一句下一句（快捷键、滚轮）时，暂停中则直接开播。
    if (!_player.playing) {
      _beginPlay();
    }
  }

  /// 上一句：固定跳到 lyricIndex - 1。
  Future<void> seekPrevLyric() async {
    final i = state.lyricIndex;
    if (i <= 0 || _lines.isEmpty) return;
    await seekLyric(i - 1);
  }

  /// 下一句：固定跳到 lyricIndex + 1；尚未对齐到任何句时从第 0 句开始。
  Future<void> seekNextLyric() async {
    if (_lines.isEmpty) return;
    final i = state.lyricIndex;
    if (i < 0) {
      await seekLyric(0);
      return;
    }
    if (i >= _lines.length - 1) return;
    await seekLyric(i + 1);
  }

  Future<void> setQuality(AudioQuality quality) async {
    if (quality == state.quality) return;
    state = state.copyWith(quality: quality);
    await ref.read(sharedPreferencesProvider).setString(_brKey, '${quality.br}');

    final track = state.track;
    if (track == null) return;
    // 本地曲无 CDN 音质切换。
    if (isLocalTrackId(track.id)) return;

    final pos = _player.position;
    final wasPlaying = _player.playing;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final play = await ref
          .read(musicSourceProvider)
          .getPlayUrl(track.id, quality: quality);
      if (play.url == null) {
        state = state.copyWith(loading: false, error: '该音质无可用地址');
        return;
      }
      _lastPlayUrl = play.url;
      await _setAudioUri(Uri.parse(play.url!), headers: true);
      await _player.seek(pos);
      if (wasPlaying) _beginPlay();
      state = state.copyWith(loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> setShowTranslation(bool value) async {
    state = state.copyWith(showTranslation: value);
    await ref.read(sharedPreferencesProvider).setBool(_transKey, value);
  }

  Future<void> setVolume(double value) async {
    await _player.setVolume(value.clamp(0.0, 1.0));
    await ref.read(sharedPreferencesProvider).setDouble(_volKey, value);
  }

  /// 下载用：优先缓存的播放 URL，否则重新请求。本地曲返回 null。
  Future<String?> resolvePlayUrlForDownload() async {
    final track = state.track;
    if (track != null && isLocalTrackId(track.id)) return null;
    if (_lastPlayUrl != null && _lastPlayUrl!.isNotEmpty) return _lastPlayUrl;
    if (track == null) return null;
    final play = await ref
        .read(musicSourceProvider)
        .getPlayUrl(track.id, quality: state.quality);
    _lastPlayUrl = play.url;
    return play.url;
  }

  /// 开始播放，不等待播完。失败由 [errorStream] 或 Future 兜底写到 [state.error]。
  void _beginPlay() {
    unawaited(_player.play().then<void>((_) {}, onError: (Object e, StackTrace _) {
      final msg = e.toString();
      if (state.error == msg) return;
      state = state.copyWith(loading: false, error: msg);
    }));
  }

  Future<void> _setAudioUri(Uri uri, {required bool headers}) async {
    if (headers) {
      await _player.setAudioSource(
        AudioSource.uri(
          uri,
          headers: ref.read(musicSourceProvider).mediaHeaders,
        ),
      );
    } else {
      await _player.setAudioSource(AudioSource.uri(uri));
    }
  }

  void _onPosition(Duration pos) {
    if (_lines.isEmpty) return;
    var idx = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != state.lyricIndex) {
      state = state.copyWith(lyricIndex: idx);
    }
  }
}
