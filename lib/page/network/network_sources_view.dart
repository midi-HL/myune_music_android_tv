import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tv/tv_focus_nav.dart';
import '../../page/playlist/playlist_content_notifier.dart';
import '../../page/playlist/playlist_models.dart';
import '../../services/network/network_library.dart';
import '../../services/network/network_media_service.dart';
import '../../services/network/network_tag_reader.dart';
import '../../services/network/remote_entry.dart';
import '../../services/network/remote_source.dart';
import '../../services/network/remote_stream.dart';
import 'google_drive_pairing.dart';
import 'tv_network_widgets.dart';

/// 「网络硬盘 / 共享网盘」标签页。
///
/// 两态布局：
///   * 未进入某个网盘：显示连接配置列表（添加 / 编辑 / 删除）；
///   * 进入某个网盘：配置面板与常驻入口全部隐藏，文件列表占满可用区域，
///     只用「上一步」逐级返回，退到根后再按一次即回到源列表。
///
/// 列表严格只显示「文件夹 + 音频文件」，网盘里的视频文件不会混进来；
/// 播放器仍支持视频容器「仅音频播放」，由「更多」里的显式选项触发。
class NetworkSourcesView extends StatefulWidget {
  const NetworkSourcesView({super.key});

  @override
  State<NetworkSourcesView> createState() => NetworkSourcesViewState();
}

class NetworkSourcesViewState extends State<NetworkSourcesView>
    with AutomaticKeepAliveClientMixin {
  List<RemoteSource> _sources = <RemoteSource>[];
  RemoteSource? _active;
  String _currentPath = '';
  final List<String> _history = <String>[];
  List<RemoteEntry> _entries = <RemoteEntry>[];
  String? _artworkUrl;
  bool _loading = false;
  String? _error;
  bool _enqueueMode = false;
  bool _readTagsEnabled = true;
  bool _prefetching = false;

  static const String _readTagsKey = 'starnote.network.readEmbeddedTags';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sources = RemoteSourceStore.instance.sources;
    unawaited(_loadTagPreference());
  }

  Future<void> _loadTagPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_readTagsKey) ?? true;
    NetworkTagReader.enabled = enabled;
    if (mounted) setState(() => _readTagsEnabled = enabled);
  }

  Future<void> _toggleReadTags() async {
    final next = !_readTagsEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_readTagsKey, next);
    NetworkTagReader.enabled = next;
    if (mounted) setState(() => _readTagsEnabled = next);
  }

  /// 两态切换后把焦点重新落到本页视觉上最靠前的入口控件
  /// （源列表的「添加网络源」/ 浏览态的「上一步」），避免焦点停在已销毁的
  /// 控件上。用页面类型限定候选，不持有固定 FocusNode，规避互斥 pane 切换时
  /// 同一节点被重复 attach 的风险。
  void _focusEntry() {
    TvFocusController.instance.scheduleFocusWhere(
      (context) =>
          context.findAncestorWidgetOfExactType<NetworkSourcesView>() != null,
    );
  }

  void _refreshSources() {
    setState(() {
      _sources = RemoteSourceStore.instance.sources;
      if (_active != null && !_sources.any((s) => s.id == _active!.id)) {
        _active = null;
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _error = null;
      }
    });
  }

  Future<void> _addSource() async {
    final source = await showTvSourceEditor(context: context);
    if (source == null) return;
    await RemoteSourceStore.instance.upsert(source);
    _refreshSources();
    if (mounted) {
      await showTvAlert(context, '已保存「${source.name}」，选中后即可开始浏览');
    }
  }

  /// 扫码添加一个只读 Google Drive 源。
  /// 电视显示二维码 / 局域网配页，手机或电脑提交 client_id /
  /// refresh_token 后由配对服务校验并直接落库，电视上不需要输入任何长串。
  Future<void> _addGoogleDriveSource() async {
    final result = await showDrivePairingDialog(context);
    if (result == null) return;
    final id = 'gd-${DateTime.now().microsecondsSinceEpoch}';
    await RemoteSourceStore.instance.upsert(result.toSource(id));
    _refreshSources();
    if (mounted) {
      await showTvAlert(
        context,
        '已添加「${result.toSource(id).name}」（只读）\n'
        '${result.account.isEmpty ? '' : '账号：${result.account}\n'}'
        '选中后即可浏览云端硬盘里的音频',
      );
    }
  }

  Future<void> _editSource() async {
    final active = _active ?? _selectedSource;
    if (active == null) {
      await showTvAlert(context, '请先选择一个网络源');
      return;
    }
    final updated = await showTvSourceEditor(
      context: context,
      existing: active,
    );
    if (updated == null) return;
    await RemoteSourceStore.instance.upsert(updated);
    _refreshSources();
    setState(() {
      _active = updated;
      _history.clear();
      _currentPath = '';
    });
    await _loadDirectory();
  }

  Future<void> _deleteSource() async {
    final active = _active ?? _selectedSource;
    if (active == null) {
      await showTvAlert(context, '请先选择一个网络源');
      return;
    }
    final confirmed = await showTvConfirm(
      context,
      '确定删除网络源「${active.name}」吗？已保存的播放队列里若有该源的歌曲将无法播放。',
    );
    if (!confirmed) return;
    await RemoteSourceStore.instance.remove(active.id);
    setState(() {
      _active = null;
      _selectedSource = null;
      _entries = <RemoteEntry>[];
      _artworkUrl = null;
      _error = null;
      _history.clear();
    });
    _refreshSources();
    _focusEntry();
  }

  RemoteSource? _selectedSource;

  Future<void> _openSource(RemoteSource source) async {
    setState(() {
      _active = source;
      _selectedSource = source;
      _history.clear();
      _currentPath = NetworkMediaService.rootOf(source);
      _artworkUrl = null;
    });
    _focusEntry();
    await _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    final source = _active;
    if (source == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await NetworkMediaService.listDirectory(
        source,
        _currentPath,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        // GDrive 的目录封面走文件头内嵌标签（NetworkTagReader），不走 NAS 相对路径。
        _artworkUrl = source.isGoogleDrive
            ? null
            : NetworkMediaService.directoryArtworkUrl(source, entries);
        _loading = false;
      });
      // 反哺自 network.1：进目录后按需读内嵌标签，标题 / 歌手 / 时长 / 封面
      // 就地回填，结果落盘缓存，重启不重读。关闭开关后不产生额外流量。
      unawaited(_prefetchCurrentDirectory());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _loading = false;
        _error = '$error';
      });
    }
  }

  /// 「上一步」：有上级目录就回上级，已经到根就退出到源列表。
  /// 浏览视图里不提供任何其它退出 / 编辑 / 网络音乐入口。
  Future<void> _goUp() async {
    if (_history.isEmpty) {
      setState(() {
        _active = null;
        _entries = <RemoteEntry>[];
        _artworkUrl = null;
        _error = null;
      });
      _focusEntry();
      return;
    }
    setState(() => _currentPath = _history.removeLast());
    await _loadDirectory();
  }

  void _openEntry(RemoteEntry entry) {
    if (entry.isDirectory) {
      setState(() {
        _history.add(_currentPath);
        _currentPath = entry.path;
      });
      _loadDirectory();
    } else if (entry.isPlayableMedia) {
      _playAudioAt(entry);
    } else {
      showTvAlert(context, '「${entry.name}」不是支持的音频格式');
    }
  }

  /// 列表只显示目录与音频，不混入视频文件。
  List<RemoteEntry> get _visibleEntries =>
      _entries.where((e) => e.isDirectory || e.isAudio).toList();

  List<RemoteEntry> get _audioEntries =>
      _entries.where((e) => e.isAudio).toList();

  /// 播放「全部媒体」时包含视频容器（mpv 无视频输出时只出声）。
  List<RemoteEntry> get _playableEntries =>
      _entries.where((e) => e.isPlayableMedia).toList();

  String get _albumLabel {
    final source = _active;
    if (source == null) return '网络媒体';
    final dir = remoteEntryName(_currentPath, isDirectory: true);
    return dir.isEmpty || dir == '目录' ? source.name : '${source.name} · $dir';
  }

  Song _songOf(RemoteEntry entry) {
    final source = _active!;
    if (source.isGoogleDrive) {
      return NetworkMediaService.driveSong(
        source: source,
        entry: entry,
        album: _albumLabel,
      );
    }
    return NetworkMediaService.nasSong(
      source: source,
      entry: entry,
      album: _albumLabel,
      artworkUrl: _artworkUrl,
    );
  }

  /// 列表行标题：读过内嵌标签就用真实「标题 · 歌手」，否则回退文件名。
  String _displayLabel(RemoteEntry entry, Song? song) {
    if (entry.isDirectory || song == null) return entry.name;
    final info = NetworkTagReader.cached(song.filePath);
    final title = info?.title?.trim();
    if (title == null || title.isEmpty) return entry.name;
    final artist = info?.artist?.trim();
    return (artist != null && artist.isNotEmpty) ? '$title · $artist' : title;
  }

  /// 列表行右侧信息：内嵌时长优先，否则显示文件大小。
  String? _displayValue(RemoteEntry entry, Song? song) {
    if (entry.isDirectory) return '目录';
    if (song == null) return entry.sizeLabel;
    final info = NetworkTagReader.cached(song.filePath);
    final ms = info?.durationMs;
    if (ms != null && ms > 0) {
      final total = ms ~/ 1000;
      final mm = (total ~/ 60).toString().padLeft(2, '0');
      final ss = (total % 60).toString().padLeft(2, '0');
      return '$mm:$ss';
    }
    return entry.sizeLabel;
  }

  /// 进目录后按需读取内嵌标签（2 并发、只拉文件头、结果落盘）。
  /// 读到就刷新列表，标题 / 歌手 / 时长 / 封面会就地回填。
  Future<void> _prefetchCurrentDirectory({bool manual = false}) async {
    if (_prefetching || !NetworkTagReader.enabled) return;
    final urls = _audioEntries.map((e) => _songOf(e).filePath).toList();
    if (urls.isEmpty) {
      if (manual && mounted) {
        await showTvAlert(context, '当前目录没有音频文件');
      }
      return;
    }
    _prefetching = true;
    try {
      final found = await NetworkTagReader.prefetchAll(
        urls,
        concurrency: 2,
        onProgress: (done, total) {
          // 每读几首刷新一次，避免频繁 rebuild，同时让封面陆续出现。
          if (mounted && (done % 4 == 0 || done == total)) setState(() {});
        },
      );
      if (mounted) setState(() {});
      if (manual && mounted) {
        await showTvAlert(
          context,
          found > 0
              ? '已读取 $found 首的内嵌标签与封面，已缓存到本机'
              : '没有读到内嵌标签（可能是不支持的格式），仍按文件名显示',
        );
      }
    } finally {
      _prefetching = false;
    }
  }

  /// 默认「收藏」歌单 id：网络硬盘歌曲加进这里，就能在收藏分类直接看到并播放。
  String? _favoritesPlaylistId() {
    for (final playlist in context.read<PlaylistContentNotifier>().playlists) {
      if (playlist.isDefault) return playlist.id;
    }
    return null;
  }

  Future<void> _syncFavoritesToPlaylist(Iterable<Song> songs) async {
    final id = _favoritesPlaylistId();
    if (id == null) return;
    await context.read<PlaylistContentNotifier>().addSongsToPlaylistById(
      id,
      songs.map((s) => s.filePath).toList(),
    );
  }

  Future<void> _addAllToFavorites() async {
    final songs = _audioEntries.map(_songOf).toList();
    if (songs.isEmpty) {
      await showTvAlert(context, '当前目录没有可收藏的音频文件');
      return;
    }
    final added = await NetworkLibraryStore.instance.addAll(songs);
    await _syncFavoritesToPlaylist(songs);
    if (!mounted) return;
    setState(() {});
    await showTvAlert(
      context,
      added > 0
          ? '已把 $added 首网络硬盘歌曲加入「收藏」，可在收藏列表直接播放'
          : '这些歌曲已经在「收藏」里了',
    );
  }

  Future<void> _toggleFavorite(RemoteEntry entry) async {
    final song = _songOf(entry);
    final added = await NetworkLibraryStore.instance.toggle(song);
    if (added) {
      await _syncFavoritesToPlaylist([song]);
    } else {
      final id = _favoritesPlaylistId();
      if (id != null) {
        await context
            .read<PlaylistContentNotifier>()
            .removeSongPathsFromPlaylist(id, [song.filePath]);
      }
    }
    if (mounted) setState(() {});
  }

  Future<bool> _ensureProxy() async {
    if (await NetworkMediaService.ensureProxy()) return true;
    await showTvAlert(
      context,
      '本机流代理未启动（端口 18765-18774 可能被占用），请重启应用后再试',
    );
    return false;
  }

  Future<void> _playAudioAt(RemoteEntry entry) async {
    final source = _active;
    if (source == null) return;
    if (!await _ensureProxy()) return;
    final playable = _playableEntries;
    final index = playable.indexWhere((e) => e.path == entry.path);
    if (index < 0) return;
    final songs = playable.map(_songOf).toList();
    await _dispatch(songs, index);
  }

  Future<void> _playAll({required bool includeVideo}) async {
    final source = _active;
    final entries = includeVideo ? _playableEntries : _audioEntries;
    if (source == null || entries.isEmpty) {
      await showTvAlert(context, '当前目录没有可播放的音频文件');
      return;
    }
    if (!await _ensureProxy()) return;
    final songs = entries.map(_songOf).toList();
    await _dispatch(songs, 0);
  }

  Future<void> _addAllToQueue() async {
    final source = _active;
    if (source == null || _audioEntries.isEmpty) {
      await showTvAlert(context, '当前目录没有可加入队列的音频文件');
      return;
    }
    if (!await _ensureProxy()) return;
    final songs = _audioEntries.map(_songOf).toList();
    await context.read<PlaylistContentNotifier>().addSongsToPlayingQueue(songs);
  }

  Future<void> _dispatch(List<Song> songs, int index) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (_enqueueMode) {
      await notifier.addSongsToPlayingQueue(songs);
    } else {
      await notifier.playFromDynamicList(songs, index);
    }
  }

  Future<void> _openMore() async {
    final choice = await showTvMenu<String>(
      context: context,
      title: '更多',
      items: <TvMenuItem<String>>[
        const TvMenuItem<String>(
          value: 'refresh',
          label: '刷新当前目录',
          icon: Icons.refresh,
        ),
        const TvMenuItem<String>(
          value: 'playAudio',
          label: '播放全部音频',
          icon: Icons.play_arrow,
        ),
        const TvMenuItem<String>(
          value: 'playMedia',
          label: '播放全部媒体',
          valueText: '含视频仅音频',
          icon: Icons.play_circle_outline,
        ),
        const TvMenuItem<String>(
          value: 'queue',
          label: '全部加入队列',
          icon: Icons.playlist_add,
        ),
        const TvMenuItem<String>(
          value: 'favoriteAll',
          label: '全部加入收藏',
          valueText: '网络硬盘专属',
          icon: Icons.star_border,
        ),
        const TvMenuItem<String>(
          value: 'readTags',
          label: '一键读取本目录标签与封面',
          valueText: '只拉文件头',
          icon: Icons.image_search,
        ),
        TvMenuItem<String>(
          value: 'tagSwitch',
          label: '读取内嵌标签',
          valueText: _readTagsEnabled ? '开' : '关',
          icon: Icons.tune,
        ),
        TvMenuItem<String>(
          value: 'click',
          label: '点击行为',
          valueText: _enqueueMode ? '加入队列' : '立即播放',
          icon: Icons.touch_app_outlined,
        ),
        const TvMenuItem<String>(
          value: 'edit',
          label: '编辑当前源',
          icon: Icons.edit_outlined,
        ),
        const TvMenuItem<String>(
          value: 'delete',
          label: '删除当前源',
          icon: Icons.delete_outline,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'refresh':
        await _loadDirectory();
        break;
      case 'playAudio':
        await _playAll(includeVideo: false);
        break;
      case 'playMedia':
        await _playAll(includeVideo: true);
        break;
      case 'queue':
        await _addAllToQueue();
        break;
      case 'favoriteAll':
        await _addAllToFavorites();
        break;
      case 'readTags':
        await _prefetchCurrentDirectory(manual: true);
        break;
      case 'tagSwitch':
        await _toggleReadTags();
        break;
      case 'click':
        setState(() => _enqueueMode = !_enqueueMode);
        break;
      case 'edit':
        await _editSource();
        break;
      case 'delete':
        await _deleteSource();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    // 进入指定网盘后不再显示左侧配置面板，文件列表占满整个可用区域。
    if (_active != null) return _buildBrowserPane(scheme);
    return _buildSourcePane(scheme);
  }

  Widget _buildSourcePane(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('网络音乐源', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'WebDAV / FTP / Google Drive · 按需拉流，不占用电视本地空间',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SizedBox(
                width: 210,
                child: TvActionButton(
                  label: '添加网络源',
                  icon: Icons.add,
                  onPressed: _addSource,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 230,
                child: TvActionButton(
                  label: '添加 Google Drive',
                  valueText: '只读 · 扫码',
                  icon: Icons.cloud_outlined,
                  onPressed: _addGoogleDriveSource,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _sources.isEmpty
                ? Center(
                    child: Text(
                      '还没有网络源\n按「添加网络源」或「添加 Google Drive」开始',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _sources.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final source = _sources[index];
                      return TvActionButton(
                        label: source.name,
                        value: remoteSourceTypeLabel(source.type),
                        icon: Icons.storage_outlined,
                        selected: _selectedSource?.id == source.id,
                        onPressed: () => _openSource(source),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              SizedBox(
                width: 180,
                child: TvActionButton(
                  label: '编辑选中源',
                  icon: Icons.edit_outlined,
                  enabled: _selectedSource != null,
                  onPressed: _editSource,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: TvActionButton(
                  label: '删除选中源',
                  icon: Icons.delete_outline,
                  enabled: _selectedSource != null,
                  onPressed: _deleteSource,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserPane(ColorScheme scheme) {
    final active = _active!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 172,
                child: TvActionButton(
                  label: '上一步',
                  value: _history.isEmpty ? '返回源列表' : '上级目录',
                  icon: Icons.arrow_upward,
                      onPressed: _goUp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      active.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: TvActionButton(
                  label: '更多',
                  icon: Icons.menu,
                  onPressed: _openMore,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildEntryList(scheme)),
        ],
      ),
    );
  }

  Widget _buildEntryList(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 40, color: scheme.error),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 140,
              child: TvActionButton(
                label: '重试',
                icon: Icons.refresh,
                onPressed: _loadDirectory,
              ),
            ),
          ],
        ),
      );
    }
    final entries = _visibleEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '该目录为空，或只有不支持的文件',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final Song? song = entry.isDirectory ? null : _songOf(entry);
        final favorite =
            song != null && NetworkLibraryStore.instance.isFavorite(song.filePath);
        final main = TvActionButton(
          label: _displayLabel(entry, song),
          value: _displayValue(entry, song),
          icon: entry.isDirectory
              ? Icons.folder_outlined
              : Icons.audio_file_outlined,
          selected: favorite,
          debugLabel: 'net-entry-${entry.path}',
          onPressed: () => _openEntry(entry),
        );
        if (song == null) return main;
        // 星标与主按钮是两个独立可聚焦控件：遥控器按 RIGHT 到星标、OK 收藏，
        // 不需要长按拖拽或鼠标，符合全链路十字键可达。
        return Row(
          children: <Widget>[
            Expanded(child: main),
            const SizedBox(width: 6),
            SizedBox(
              width: 96,
              child: TvActionButton(
                label: favorite ? '已收藏' : '收藏',
                icon: favorite ? Icons.star : Icons.star_border,
                debugLabel: 'net-fav-${entry.path}',
                onPressed: () => _toggleFavorite(entry),
              ),
            ),
          ],
        );
      },
    );
  }
}
