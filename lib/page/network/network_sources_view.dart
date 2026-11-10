import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../tv/tv_focus_nav.dart';
import '../../page/playlist/playlist_content_notifier.dart';
import '../../page/playlist/playlist_models.dart';
import '../../services/network/network_media_service.dart';
import '../../services/network/remote_entry.dart';
import '../../services/network/remote_source.dart';
import '../../services/network/remote_stream.dart';
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sources = RemoteSourceStore.instance.sources;
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
        _artworkUrl = NetworkMediaService.directoryArtworkUrl(source, entries);
        _loading = false;
      });
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
    return NetworkMediaService.nasSong(
      source: _active!,
      entry: entry,
      album: _albumLabel,
      artworkUrl: _artworkUrl,
    );
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
            'WebDAV / FTP · 按需拉流，不占用电视本地空间',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: TvActionButton(
              label: '添加网络源',
              icon: Icons.add,
              onPressed: _addSource,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _sources.isEmpty
                ? Center(
                    child: Text(
                      '还没有网络源\n按「添加网络源」开始',
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
        return TvActionButton(
          label: entry.name,
          value: entry.isDirectory ? '目录' : entry.sizeLabel,
          icon: entry.isDirectory
              ? Icons.folder_outlined
              : Icons.audio_file_outlined,
          onPressed: () => _openEntry(entry),
        );
      },
    );
  }
}
