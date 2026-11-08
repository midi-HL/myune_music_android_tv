import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../page/playlist/playlist_content_notifier.dart';
import '../../page/playlist/playlist_models.dart';
import '../../services/network/bilibili_client.dart';
import '../../services/network/network_media_service.dart';
import 'tv_network_widgets.dart';

/// 「哔哩哔哩」标签页。
///
/// 参考 BiliMusic-Desktop 的功能范围与交互：关键词搜索 + 分页、BV 号/链接解析、
/// 分 P 展开、单独播放与整组加入队列、重启后仍可播放的队列（URL 自带元数据）、
/// 流式播放（本机代理 + Range）、扫码登录、搜索历史、音频/视频流切换。
/// 身份模型沿用 `bilibili:{bvid}:{cid}`。
class BilibiliView extends StatefulWidget {
  const BilibiliView({super.key});

  @override
  State<BilibiliView> createState() => BilibiliViewState();
}

class BilibiliViewState extends State<BilibiliView>
    with AutomaticKeepAliveClientMixin {
  static const String _historyKey = 'starnote.bilibili.search.history.v1';

  String _keyword = '';
  int _page = 1;
  List<BiliVideo> _results = <BiliVideo>[];
  bool _loading = false;
  String? _error;
  BiliVideo? _selected;
  BiliVideoDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;
  BiliStreamMode _mode = BiliStreamMode.audio;
  bool _enqueueMode = false;
  bool _loggedIn = false;
  List<String> _history = <String>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loggedIn = BiliAuthStore.instance.isLoggedIn;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? const <String>[];
    if (mounted) setState(() => _history = list);
  }

  Future<void> _remember(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final next = <String>[trimmed]
      ..addAll(_history.where((h) => h != trimmed).take(7));
    setState(() => _history = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
  }

  Future<void> _promptSearch() async {
    final value = await showTvTextInput(
      context: context,
      title: '搜索哔哩哔哩',
      hint: '输入歌曲 / 视频关键词',
      initialValue: _keyword,
      confirmLabel: '搜索',
    );
    if (value == null) return;
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    await _remember(keyword);
    setState(() {
      _keyword = keyword;
      _page = 1;
    });
    await _search();
  }

  Future<void> _promptBvid() async {
    final value = await showTvTextInput(
      context: context,
      title: '打开 BV 号 / 链接',
      hint: '粘贴 BV 号、av 号或 B 站视频链接',
      confirmLabel: '打开',
    );
    if (value == null) return;
    final bvid = BiliClient.extractBvid(value);
    if (bvid == null) {
      await showTvAlert(context, '没有识别到 BV 号，请检查输入内容');
      return;
    }
    await _openDetail(
      BiliVideo(
        bvid: bvid,
        title: bvid,
        author: '',
        cover: '',
        description: '',
        durationSeconds: 0,
      ),
    );
  }

  Future<void> _search() async {
    if (_keyword.trim().isEmpty) {
      await _promptSearch();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await BiliClient.instance.search(
        _keyword.trim(),
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _results = <BiliVideo>[];
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 1) return;
    setState(() {
      _page = next;
      _detail = null;
      _selected = null;
    });
    await _search();
  }

  Future<void> _openDetail(BiliVideo video) async {
    setState(() {
      _selected = video;
      _detail = null;
      _detailError = null;
      _detailLoading = true;
    });
    try {
      final detail = await BiliClient.instance.view(video.bvid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailError = '$error';
        _detailLoading = false;
      });
    }
  }

  Future<bool> _ensureProxy() async {
    if (await NetworkMediaService.ensureProxy()) return true;
    await showTvAlert(
      context,
      '本机流代理未启动（端口 18765-18774 可能被占用），请重启应用后再试',
    );
    return false;
  }

  List<Song> _songsOf(BiliVideoDetail detail, List<BiliPage> pages) {
    return pages.map((page) {
      final title = pages.length > 1
          ? '${detail.title} · P${page.page} ${page.part}'
          : '${detail.title} · ${page.part}';
      return NetworkMediaService.biliSong(
        bvid: detail.bvid,
        cid: page.cid,
        title: title,
        author: detail.author,
        mode: _mode,
        durationSeconds: page.durationSeconds,
      );
    }).toList();
  }

  Future<void> _playPages(int index, {required bool enqueue}) async {
    final detail = _detail;
    if (detail == null || detail.pages.isEmpty || index < 0) return;
    if (!await _ensureProxy()) return;
    final songs = _songsOf(detail, detail.pages);
    final notifier = context.read<PlaylistContentNotifier>();
    if (enqueue) {
      await notifier.addSongsToPlayingQueue(songs);
    } else {
      await notifier.playFromDynamicList(songs, index);
    }
  }

  Future<void> _playAllPages({required bool enqueue}) async {
    final detail = _detail;
    if (detail == null || detail.pages.isEmpty) {
      await showTvAlert(context, '当前视频没有可播放的分 P');
      return;
    }
    await _playPages(0, enqueue: enqueue);
  }

  Future<void> _openLogin() async {
    final changed = await showTvQrLogin(context: context);
    if (mounted) {
      setState(() => _loggedIn = BiliAuthStore.instance.isLoggedIn || changed);
    }
  }

  Future<void> _showHistory() async {
    if (_history.isEmpty) {
      await showTvAlert(context, '还没有搜索历史');
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('搜索历史', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < _history.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TvActionButton(
                      label: _history[i],
                      icon: Icons.history,
                      autofocus: i == 0,
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(_history[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TvActionButton(
            label: '关闭',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _keyword = picked;
      _page = 1;
    });
    await _search();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('哔哩哔哩', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '搜索 / BV 号 / 分 P / 队列 · 流式播放，不占用电视本地空间',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              SizedBox(
                width: 196,
                child: TvActionButton(
                  label: '搜索关键词',
                  value: _keyword.isEmpty ? '未设置' : _keyword,
                  icon: Icons.search,
                  onPressed: _promptSearch,
                ),
              ),
              SizedBox(
                width: 176,
                child: TvActionButton(
                  label: '打开 BV 号 / 链接',
                  icon: Icons.link,
                  onPressed: _promptBvid,
                ),
              ),
              SizedBox(
                width: 148,
                child: TvActionButton(
                  label: '搜索历史',
                  icon: Icons.history,
                  onPressed: _showHistory,
                ),
              ),
              SizedBox(
                width: 168,
                child: TvActionButton(
                  label: '扫码登录',
                  value: _loggedIn ? '已登录' : '未登录',
                  icon: Icons.qr_code_2,
                  selected: _loggedIn,
                  onPressed: _openLogin,
                ),
              ),
              SizedBox(
                width: 188,
                child: TvActionButton(
                  label: '流类型',
                  value: _mode == BiliStreamMode.audio
                      ? '音频流（推荐）'
                      : '视频流',
                  icon: Icons.audiotrack_outlined,
                  onPressed: () => setState(() {
                    _mode = _mode == BiliStreamMode.audio
                        ? BiliStreamMode.video
                        : BiliStreamMode.audio;
                  }),
                ),
              ),
              SizedBox(
                width: 188,
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
          Row(
            children: <Widget>[
              SizedBox(
                width: 108,
                child: TvActionButton(
                  label: '上一页',
                  icon: Icons.chevron_left,
                  enabled: _page > 1,
                  onPressed: () => _changePage(-1),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 108,
                child: TvActionButton(
                  label: '下一页',
                  icon: Icons.chevron_right,
                  onPressed: () => _changePage(1),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '第 $_page 页 · 关键词「$_keyword」',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: _buildResults(scheme)),
                const VerticalDivider(width: 1),
                SizedBox(width: 330, child: _buildDetail(scheme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ColorScheme scheme) {
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                label: '重新搜索',
                icon: Icons.refresh,
                autofocus: true,
                onPressed: _search,
              ),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search, size: 48, color: scheme.outline),
            const SizedBox(height: 10),
            Text(
              '按「搜索关键词」或「打开 BV 号 / 链接」开始',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final video = _results[index];
        return TvActionButton(
          label: video.title,
          value: '${video.author} · ${video.durationLabel}',
          icon: Icons.smart_display_outlined,
          selected: _selected?.bvid == video.bvid,
          onPressed: () => _openDetail(video),
        );
      },
    );
  }

  Widget _buildDetail(ColorScheme scheme) {
    if (_selected == null) {
      return Center(
        child: Text(
          '选中左侧视频后\n在这里展开全部分 P',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    if (_detailLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_detailError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 36, color: scheme.error),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _detailError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              child: TvActionButton(
                label: '重试',
                autofocus: true,
                onPressed: () => _openDetail(_selected!),
              ),
            ),
          ],
        ),
      );
    }
    final detail = _detail;
    if (detail == null || detail.pages.isEmpty) {
      return Center(
        child: Text(
          '没有可播放的分 P',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            detail.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            '${detail.author} · 共 ${detail.pages.length} 个分 P',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              SizedBox(
                width: 148,
                child: TvActionButton(
                  label: '播放全部分 P',
                  icon: Icons.play_arrow,
                  onPressed: () => _playAllPages(enqueue: false),
                ),
              ),
              SizedBox(
                width: 148,
                child: TvActionButton(
                  label: '全部加入队列',
                  icon: Icons.playlist_add,
                  onPressed: () => _playAllPages(enqueue: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: detail.pages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                final page = detail.pages[index];
                return TvActionButton(
                  label: 'P${page.page} ${page.part}',
                  value: page.durationLabel,
                  icon: Icons.play_circle_outline,
                  onPressed: () => _playPages(
                    index,
                    enqueue: _enqueueMode,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
