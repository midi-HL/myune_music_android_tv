import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../page/playlist/playlist_content_notifier.dart';
import '../../services/network/network_media_service.dart';
import '../../services/network/remote_entry.dart';
import '../../services/network/remote_source.dart';
import 'tv_network_widgets.dart';

/// 「网络硬盘 / 共享网盘」标签页。
///
/// 左侧是连接配置（WebDAV / FTP），右侧是目录浏览。所有按钮、列表项均
/// 用 TvActionButton 包裹，遥控器方向键可逐项到达，OK 激活；鼠标/触控同路径。
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

  void _refreshSources() {
    setState(() {
      _sources = RemoteSourceStore.instance.sources;
      if (_active != null &&
          !_sources.any((s) => s.id == _active!.id)) {
        _active = null;
        _entries = <RemoteEntry>[];
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
      await showTvAlert(context, '已保存「${source.name}」，按「连接」开始浏览');
    }
  }

  Future<void> _editSource() async {
    final active = _active;
    if (active == null) {
      await showTvAlert(context, '请先在左侧选择一个网络源');
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
    final active = _active;
    if (active == null) {
      await showTvAlert(context, '请先在左侧选择一个网络源');
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
      _entries = <RemoteEntry>[];
      _error = null;
      _history.clear();
    });
    _refreshSources();
  }

  Future<void> _openSource(RemoteSource source) async {
    setState(() {
      _active = source;
      _history.clear();
      _currentPath = NetworkMediaService.rootOf(source);
    });
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
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = <RemoteEntry>[];
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _goUp() async {
    if (_history.isEmpty) {
      await showTvAlert(context, '已经在根目录了');
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
    } else if (entry.isAudio) {
      _playAudioAt(entry);
    } else {
      showTvAlert(context, '「${entry.name}」不是支持的音频格式');
    }
  }

  List<RemoteEntry> get _audioEntries =>
      _entries.where((e) => e.isAudio).toList();

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
    final audio = _audioEntries;
    final index = audio.indexWhere((e) => e.path == entry.path);
    if (index < 0) return;
    final songs = audio
        .map(
          (e) => NetworkMediaService.nasSong(source: source, entry: e),
        )
        .toList();
    final notifier = context.read<PlaylistContentNotifier>();
    if (_enqueueMode) {
      await notifier.addSongsToPlayingQueue(songs);
    } else {
      await notifier.playFromDynamicList(songs, index);
    }
  }

  Future<void> _playAll() async {
    final source = _active;
    if (source == null || _audioEntries.isEmpty) {
      await showTvAlert(context, '当前目录没有可播放的音频文件');
      return;
    }
    if (!await _ensureProxy()) return;
    final songs = _audioEntries
        .map(
          (e) => NetworkMediaService.nasSong(source: source, entry: e),
        )
        .toList();
    final notifier = context.read<PlaylistContentNotifier>();
    if (_enqueueMode) {
      await notifier.addSongsToPlayingQueue(songs);
    } else {
      await notifier.playFromDynamicList(songs, 0);
    }
  }

  Future<void> _addAllToQueue() async {
    final source = _active;
    if (source == null || _audioEntries.isEmpty) {
      await showTvAlert(context, '当前目录没有可加入队列的音频文件');
      return;
    }
    if (!await _ensureProxy()) return;
    final songs = _audioEntries
        .map(
          (e) => NetworkMediaService.nasSong(source: source, entry: e),
        )
        .toList();
    await context.read<PlaylistContentNotifier>().addSongsToPlayingQueue(songs);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 300, child: _buildSourcePane(scheme)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildBrowserPane(scheme)),
      ],
    );
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
          TvActionButton(
            label: '添加网络源',
            icon: Icons.add,
            onPressed: _addSource,
          ),
          const SizedBox(height: 10),
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
                        selected: _active?.id == source.id,
                        onPressed: () => _openSource(source),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          TvActionButton(
            label: '编辑当前源',
            icon: Icons.edit_outlined,
            enabled: _active != null,
            onPressed: _editSource,
          ),
          const SizedBox(height: 6),
          TvActionButton(
            label: '删除当前源',
            icon: Icons.delete_outline,
            enabled: _active != null,
            onPressed: _deleteSource,
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserPane(ColorScheme scheme) {
    final active = _active;
    if (active == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_outlined, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              '选择左侧的网络源并浏览音乐',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            active.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            active.displaySubtitle,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              SizedBox(
                width: 132,
                child: TvActionButton(
                  label: '返回上级',
                  icon: Icons.arrow_upward,
                  onPressed: _goUp,
                ),
              ),
              SizedBox(
                width: 112,
                child: TvActionButton(
                  label: '刷新',
                  icon: Icons.refresh,
                  onPressed: _loadDirectory,
                ),
              ),
              SizedBox(
                width: 152,
                child: TvActionButton(
                  label: '播放全部音频',
                  icon: Icons.play_arrow,
                  onPressed: _playAll,
                ),
              ),
              SizedBox(
                width: 152,
                child: TvActionButton(
                  label: '全部加入队列',
                  icon: Icons.playlist_add,
                  onPressed: _addAllToQueue,
                ),
              ),
              SizedBox(
                width: 196,
                child: TvActionButton(
                  label: '点击行为',
                  value: _enqueueMode ? '加入队列' : '立即播放',
                  icon: Icons.touch_app_outlined,
                  selected: _enqueueMode,
                  onPressed: () =>
                      setState(() => _enqueueMode = !_enqueueMode),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
                autofocus: true,
                onPressed: _loadDirectory,
              ),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          '该目录为空，或没有可识别的条目',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return TvActionButton(
          label: entry.name,
          value: entry.isDirectory ? '目录' : entry.sizeLabel,
          icon: entry.isDirectory
              ? Icons.folder_outlined
              : (entry.isAudio
                  ? Icons.audio_file_outlined
                  : Icons.insert_drive_file_outlined),
          onPressed: () => _openEntry(entry),
        );
      },
    );
  }
}
