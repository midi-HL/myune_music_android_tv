import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../page/playlist/playlist_content_notifier.dart';
import '../../page/playlist/playlist_models.dart';
import '../../services/network/bili_library.dart';
import '../../services/network/bilibili_client.dart';
import '../../services/network/network_media_service.dart';
import '../../services/network/remote_media_registry.dart';
import 'tv_network_widgets.dart';

/// 「哔哩哔哩」主体分区。顶部只有一行工具条，主体按分区展示内容。
/// - [favorites]：本机星标收藏（推荐/搜索结果里按星标加入，离线可用）。
/// - [cloudFavorites]：B 站账号的收藏夹（先列收藏夹再进内容，需扫码登录）。
/// 两者并存、分两个入口，互不覆盖。
/// - [history] 恒为本机播放记录，不读取 B 站服务端观看历史。
enum _BiliSection {
  recommend,
  search,
  history,
  favorites,
  cloudFavorites,
}

extension _BiliSectionLabel on _BiliSection {
  String get label => switch (this) {
        _BiliSection.recommend => '推荐',
        _BiliSection.search => '搜索结果',
        _BiliSection.history => '历史播放',
        _BiliSection.favorites => '本地收藏',
        _BiliSection.cloudFavorites => 'B站收藏夹',
      };

  IconData get icon => switch (this) {
        _BiliSection.recommend => Icons.auto_awesome_outlined,
        _BiliSection.search => Icons.search,
        _BiliSection.history => Icons.history,
        _BiliSection.favorites => Icons.star_border,
        _BiliSection.cloudFavorites => Icons.folder_special_outlined,
      };
}

/// 「哔哩哔哩」标签页。
///
/// 顶部固定区域压缩为「一行工具条 + 一行分区选项栏」：
///   * 工具条只保留 搜索 / 打开 BV 号 / 更多 与紧凑的 上一页 / 下一页；
///   * 主体默认展示推荐；分区选项栏提供 推荐 / 搜索结果 / 历史播放 / 收藏；
///   * 次要功能（搜索历史、账号与登录、流类型、清空历史）收进「更多」，
///     扫码登录再往下一层，避免功能平铺占掉内容区。
class BilibiliView extends StatefulWidget {
  const BilibiliView({super.key});

  @override
  State<BilibiliView> createState() => BilibiliViewState();
}

class BilibiliViewState extends State<BilibiliView>
    with AutomaticKeepAliveClientMixin {
  static const String _historyKey = 'starnote.bilibili.search.history.v1';

  _BiliSection _section = _BiliSection.recommend;
  String _keyword = '';
  int _page = 1;
  List<BiliVideo> _recommend = <BiliVideo>[];
  List<BiliVideo> _results = <BiliVideo>[];
  bool _loading = false;
  String? _error;
  BiliVideo? _selected;
  BiliVideoDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;
  BiliStreamMode _mode = BiliStreamMode.audio;
  bool _loggedIn = false;
  List<String> _searchHistory = <String>[];
  List<Song> _favorites = <Song>[];
  List<Song> _history = <Song>[];

  // B 站账号收藏夹：两层浏览（收藏夹列表 -> 收藏夹内视频）。
  List<BiliFavFolder> _favFolders = <BiliFavFolder>[];
  BiliFavFolder? _activeFolder;
  List<BiliVideo> _favMedias = <BiliVideo>[];
  int _favPage = 1;
  bool _favHasMore = false;
  bool _favLoading = false;
  String? _favError;

  // 详情页「播放全部」按钮的焦点节点：视频详情加载完成后把焦点落到这里，
  // 而不是停留在原位置（用户按 OK 打开详情时焦点仍在列表项上）。
  final FocusNode _playAllFocusNode = FocusNode(debugLabel: 'bili-play-all');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loggedIn = BiliAuthStore.instance.isLoggedIn;
    _loadSearchHistory();
    _loadLibrary();
    _loadRecommend();
  }

  @override
  void dispose() {
    _playAllFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? const <String>[];
    if (mounted) setState(() => _searchHistory = list);
  }

  Future<void> _remember(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final next = <String>[trimmed]
      ..addAll(_searchHistory.where((h) => h != trimmed).take(7));
    if (mounted) setState(() => _searchHistory = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
  }

  Future<void> _loadLibrary() async {
    await BiliLibraryStore.instance.load();
    if (!mounted) return;
    setState(() {
      _favorites = BiliLibraryStore.instance.favorites;
      _history = BiliLibraryStore.instance.history;
    });
  }

  bool get _canPage =>
      _section == _BiliSection.recommend || _section == _BiliSection.search;

  // ===== 顶部工具条 =====

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
      _section = _BiliSection.search;
      _selected = null;
      _detail = null;
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

  Future<void> _openMore() async {
    final choice = await showTvMenu<String>(
      context: context,
      title: '更多',
      items: <TvMenuItem<String>>[
        TvMenuItem<String>(
          value: 'searchHistory',
          label: '搜索历史',
          valueText: '${_searchHistory.length} 条',
          icon: Icons.history,
        ),
        TvMenuItem<String>(
          value: 'account',
          label: '账号与登录',
          valueText: _loggedIn ? '已登录' : '未登录',
          icon: Icons.person_outline,
        ),
        TvMenuItem<String>(
          value: 'mode',
          label: '流类型',
          valueText: _mode == BiliStreamMode.audio ? '音频流' : '视频流',
          icon: Icons.audiotrack_outlined,
        ),
        TvMenuItem<String>(
          value: 'clearHistory',
          label: '清空历史播放',
          icon: Icons.delete_sweep_outlined,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'searchHistory':
        await _showSearchHistory();
        break;
      case 'account':
        await _openAccount();
        break;
      case 'mode':
        await _chooseMode();
        break;
      case 'clearHistory':
        await BiliLibraryStore.instance.clearHistory();
        await _loadLibrary();
        await showTvAlert(context, '已清空历史播放');
        break;
    }
  }

  /// 扫码登录放在「更多 → 账号与登录 → 扫码登录」这一更深层，
  /// 登录状态在「更多」与账号页都显式显示。
  Future<void> _openAccount() async {
    final choice = await showTvMenu<String>(
      context: context,
      title: '账号与登录',
      items: <TvMenuItem<String>>[
        TvMenuItem<String>(
          value: 'status',
          label: '登录状态',
          valueText: _loggedIn ? '已登录' : '未登录',
          icon: Icons.info_outline,
          enabled: false,
        ),
        const TvMenuItem<String>(
          value: 'qr',
          label: '扫码登录',
          icon: Icons.qr_code_2,
        ),
        if (_loggedIn)
          const TvMenuItem<String>(
            value: 'logout',
            label: '退出登录',
            icon: Icons.logout,
          ),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'qr') {
      final changed = await showTvQrLogin(context: context);
      if (mounted) {
        setState(() {
          _loggedIn = BiliAuthStore.instance.isLoggedIn || changed;
        });
        // 若是从「B站收藏夹」的未登录提示跳来，登录成功后直接刷新列表。
        if (_section == _BiliSection.cloudFavorites) {
          await _loadFavFolders();
        }
      }
    } else if (choice == 'logout') {
      await BiliAuthStore.instance.clear();
      if (mounted) setState(() => _loggedIn = false);
      await showTvAlert(context, '已退出哔哩哔哩登录');
      if (_section == _BiliSection.cloudFavorites) {
        await _loadFavFolders();
      }
    }
  }

  Future<void> _chooseMode() async {
    final picked = await showTvMenu<BiliStreamMode>(
      context: context,
      title: '流类型',
      items: <TvMenuItem<BiliStreamMode>>[
        const TvMenuItem<BiliStreamMode>(
          value: BiliStreamMode.audio,
          label: '音频流',
          valueText: '更省流量，推荐',
          icon: Icons.audiotrack_outlined,
        ),
        const TvMenuItem<BiliStreamMode>(
          value: BiliStreamMode.video,
          label: '视频流',
          valueText: '仅音频播放',
          icon: Icons.smart_display_outlined,
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _mode = picked);
  }

  Future<void> _showSearchHistory() async {
    if (_searchHistory.isEmpty) {
      await showTvAlert(context, '还没有搜索历史');
      return;
    }
    final picked = await showTvMenu<String>(
      context: context,
      title: '搜索历史',
      items: _searchHistory
          .map(
            (h) => TvMenuItem<String>(value: h, label: h, icon: Icons.history),
          )
          .toList(growable: false),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _keyword = picked;
      _page = 1;
      _section = _BiliSection.search;
      _selected = null;
      _detail = null;
    });
    await _search();
  }

  Future<void> _changePage(int delta) async {
    if (!_canPage) return;
    final next = _page + delta;
    if (next < 1) return;
    setState(() {
      _page = next;
      _selected = null;
      _detail = null;
    });
    if (_section == _BiliSection.recommend) {
      await _loadRecommend();
    } else {
      await _search();
    }
  }

  // ===== 数据加载 =====

  Future<void> _loadRecommend() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await BiliClient.instance.recommend(page: _page);
      if (!mounted) return;
      setState(() {
        _recommend = list;
        _loading = false;
        if (list.isEmpty) _error = '暂时没有拿到推荐内容，按「重新加载」或改用搜索';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recommend = <BiliVideo>[];
        _loading = false;
        _error = '$error';
      });
    }
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
        _section = _BiliSection.search;
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

  Future<void> _switchSection(_BiliSection section) async {
    setState(() {
      _section = section;
      _selected = null;
      _detail = null;
      _error = null;
      // 离开 B 站收藏夹分区时清空层级，下次进入重新拉，避免使用过期列表。
      if (section != _BiliSection.cloudFavorites) {
        _activeFolder = null;
        _favMedias = <BiliVideo>[];
      }
    });
    if (section == _BiliSection.recommend && _recommend.isEmpty) {
      await _loadRecommend();
    } else if (section == _BiliSection.history ||
        section == _BiliSection.favorites) {
      await _loadLibrary();
    } else if (section == _BiliSection.cloudFavorites) {
      await _loadFavFolders();
    }
  }

  /// 进入「B站收藏夹」：拉取账号收藏夹列表。
  Future<void> _loadFavFolders() async {
    if (mounted) {
      setState(() {
        _favLoading = true;
        _favError = null;
        _activeFolder = null;
        _favMedias = <BiliVideo>[];
      });
    }
    try {
      final folders = await BiliClient.instance.favFolders();
      if (!mounted) return;
      setState(() {
        _favFolders = folders;
        _favLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _favError = '$error';
        _favLoading = false;
      });
    }
  }

  /// 选中某个收藏夹，读取第一页内容。
  Future<void> _openFolder(BiliFavFolder folder) async {
    setState(() {
      _activeFolder = folder;
      _favMedias = <BiliVideo>[];
      _favPage = 1;
      _favHasMore = false;
      _favLoading = true;
      _favError = null;
    });
    try {
      final pageResult = await BiliClient.instance.favFolderMedias(
        folder.mediaId,
        pn: 1,
      );
      if (!mounted) return;
      setState(() {
        _favMedias = pageResult.videos;
        _favHasMore = pageResult.hasMore;
        _favLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _favError = '$error';
        _favLoading = false;
      });
    }
  }

  /// 「加载更多」：按 has_more 翻页，追加到当前列表。
  Future<void> _loadMoreFavMedias() async {
    final folder = _activeFolder;
    if (folder == null || _favLoading || !_favHasMore) return;
    setState(() => _favLoading = true);
    try {
      final next = _favPage + 1;
      final pageResult = await BiliClient.instance.favFolderMedias(
        folder.mediaId,
        pn: next,
      );
      if (!mounted) return;
      setState(() {
        _favPage = next;
        _favMedias = <BiliVideo>[..._favMedias, ...pageResult.videos];
        _favHasMore = pageResult.hasMore;
        _favLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _favError = '$error';
        _favLoading = false;
      });
    }
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
      // 详情面板就绪后把焦点落到「播放全部」：从这里按向下直接进入下方
      // 分 P 选择区，不必绕到旁侧视频列表或收藏区。
      if (detail.pages.isNotEmpty) {
        // 详情面板与 ExcludeFocus 有重建过程，等两帧再落焦，
        // 保证外部 FocusNode 已经 attach 完成（与 TvFocusController 一致）。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _playAllFocusNode.canRequestFocus) {
              _playAllFocusNode.requestFocus();
            }
          });
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailError = '$error';
        _detailLoading = false;
      });
    }
  }

  // ===== 播放与收藏 =====

  Future<bool> _ensureProxy() async {
    if (await NetworkMediaService.ensureProxy()) return true;
    await showTvAlert(
      context,
      '本机流代理未启动（端口 18765-18774 可能被占用），请重启应用后再试',
    );
    return false;
  }

  List<Song> _songsOf(
    BiliVideoDetail detail,
    List<BiliPage> pages, {
    String? coverUrl,
  }) {
    final art = (coverUrl != null && coverUrl.isNotEmpty)
        ? coverUrl
        : (_selected?.cover ?? '');
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
        artworkUrl: art,
        mediaId: 'bilibili:${detail.bvid}:${page.cid}:${_mode.name}',
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
      // 只有真正开始播放才记入历史播放，加入队列不算。
      await _recordPlay(songs[index]);
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

  Future<void> _playSong(Song song) async {
    if (!await _ensureProxy()) return;
    await context.read<PlaylistContentNotifier>().playFromDynamicList(
      <Song>[song],
      0,
    );
    await _recordPlay(song);
  }

  Future<void> _recordPlay(Song song) async {
    await BiliLibraryStore.instance.recordPlay(song);
    await _loadLibrary();
  }

  bool _isVideoFavorited(BiliVideo video) {
    for (final song in _favorites) {
      final id = RemoteMediaRegistry.mediaIdOf(song.filePath) ?? '';
      if (id.startsWith('bilibili:${video.bvid}:')) return true;
    }
    return false;
  }

  Future<void> _toggleFavoriteVideo(BiliVideo video) async {
    if (!await _ensureProxy()) return;
    try {
      final detail = await BiliClient.instance.view(video.bvid);
      if (!mounted) return;
      final cover = detail.cover.isNotEmpty ? detail.cover : video.cover;
      final songs = _songsOf(detail, detail.pages, coverUrl: cover);
      await BiliLibraryStore.instance.load();
      final anyFavorited = songs.any(
        (s) => BiliLibraryStore.instance.isFavorite(s.filePath),
      );
      if (anyFavorited) {
        for (final song in songs) {
          await BiliLibraryStore.instance.removeFavorite(song.filePath);
        }
        await showTvAlert(context, '已取消收藏「${video.title}」');
      } else {
        await BiliLibraryStore.instance.addFavorites(songs);
        await showTvAlert(context, '已收藏「${video.title}」共 ${songs.length} 首');
      }
      await _loadLibrary();
    } catch (error) {
      await showTvAlert(context, '收藏失败：$error');
    }
  }

  Future<void> _toggleFavoriteDetail() async {
    final video = _selected;
    if (video == null) return;
    await _toggleFavoriteVideo(video);
  }

  static String _fmt(Duration? duration) {
    if (duration == null) return '--:--';
    final total = duration.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 一行工具条：只保留 搜索 / 打开 BV 号 / 更多 与紧凑翻页。
          Row(
            children: <Widget>[
              SizedBox(
                width: 118,
                child: TvActionButton(
                  label: '搜索',
                  icon: Icons.search,
                  onPressed: _promptSearch,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 152,
                child: TvActionButton(
                  label: '打开 BV 号',
                  icon: Icons.link,
                  onPressed: _promptBvid,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 108,
                child: TvActionButton(
                  label: '更多',
                  icon: Icons.menu,
                  onPressed: _openMore,
                ),
              ),
              const Spacer(),
              TvIconButton(
                icon: Icons.chevron_left,
                semanticLabel: '上一页',
                enabled: _canPage && _page > 1,
                onPressed: () => _changePage(-1),
              ),
              const SizedBox(width: 6),
              TvIconButton(
                icon: Icons.chevron_right,
                semanticLabel: '下一页',
                enabled: _canPage,
                onPressed: () => _changePage(1),
              ),
              const SizedBox(width: 10),
              Text(
                '第 $_page 页',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 独立分区选项栏。
          SizedBox(
            height: 46,
            child: Row(
              children: <Widget>[
                for (final section in _BiliSection.values) ...<Widget>[
                  SizedBox(
                    width: 126,
                    child: TvActionButton(
                      label: section.label,
                      icon: section.icon,
                      selected: _section == section,
                      onPressed: () => _switchSection(section),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                Text(
                  _section == _BiliSection.search && _keyword.isNotEmpty
                      ? '关键词：$_keyword'
                      : '',
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
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _buildMainList(scheme)),
                if (_selected != null) ...<Widget>[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 300, child: _buildDetail(scheme)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainList(ColorScheme scheme) {
    // 收藏夹用自己的 _favLoading / _favError，避免推荐/搜索的全局状态
    // （例如切走时仍在加载）把新分区整个盖成进度条。
    if (_loading && _section != _BiliSection.cloudFavorites) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _section != _BiliSection.cloudFavorites) {
      return _buildMessage(
        scheme,
        icon: Icons.error_outline,
        message: _error!,
        actionLabel: '重新加载',
        onAction: () {
          if (_section == _BiliSection.recommend) {
            _loadRecommend();
          } else if (_section == _BiliSection.search) {
            _search();
          } else {
            _loadLibrary();
          }
        },
      );
    }
    switch (_section) {
      case _BiliSection.recommend:
      case _BiliSection.search:
        final videos = _section == _BiliSection.recommend
            ? _recommend
            : _results;
        if (videos.isEmpty) {
          return _buildMessage(
            scheme,
            icon: _section == _BiliSection.recommend
                ? Icons.auto_awesome_outlined
                : Icons.search,
            message: _section == _BiliSection.recommend
                ? '按「重新加载」获取推荐，或用「搜索」找内容'
                : '没有搜索结果，换个关键词或翻页试试',
            actionLabel: _section == _BiliSection.recommend
                ? '重新加载'
                : '搜索',
            onAction: _section == _BiliSection.recommend
                ? _loadRecommend
                : _promptSearch,
          );
        }
        return _buildVideoList(videos);
      case _BiliSection.history:
        if (_history.isEmpty) {
          return _buildMessage(
            scheme,
            icon: Icons.history,
            message: '还没有历史播放，播放过的哔哩哔哩歌曲会出现在这里',
            actionLabel: '去推荐',
            onAction: () => _switchSection(_BiliSection.recommend),
          );
        }
        return _buildSongList(_history);
      case _BiliSection.favorites:
        if (_favorites.isEmpty) {
          return _buildMessage(
            scheme,
            icon: Icons.star_border,
            message: '还没有本地收藏，在推荐 / 搜索结果里按星标即可收藏',
            actionLabel: '去推荐',
            onAction: () => _switchSection(_BiliSection.recommend),
          );
        }
        return _buildSongList(_favorites);
      case _BiliSection.cloudFavorites:
        if (_favLoading && _favFolders.isEmpty && _favMedias.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_favError != null) {
          final needLogin =
              _favError!.contains('登录') || _favError!.contains('权限');
          return _buildMessage(
            scheme,
            icon: Icons.cloud_off_outlined,
            message: _favError!,
            actionLabel: needLogin ? '去登录' : '重试',
            onAction: () {
              if (needLogin) {
                _openAccount();
                return;
              }
              final folder = _activeFolder;
              if (folder == null) {
                _loadFavFolders();
              } else {
                _openFolder(folder);
              }
            },
          );
        }
        if (_activeFolder == null) {
          if (_favFolders.isEmpty) {
            return _buildMessage(
              scheme,
              icon: Icons.folder_special_outlined,
              message: '账号下还没有收藏夹，可在 B 站 App / 网页里收藏视频后重试',
              actionLabel: '重新加载',
              onAction: _loadFavFolders,
            );
          }
          return _buildFavFolderList();
        }
        return _buildFavMediaList();
    }
  }

  /// 第一层：账号的收藏夹列表。
  Widget _buildFavFolderList() {
    return ListView.separated(
      itemCount: _favFolders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final folder = _favFolders[index];
        return TvActionButton(
          label: folder.isDefault ? '${folder.title}（默认）' : folder.title,
          value: '${folder.mediaCount} 个内容',
          icon: folder.isDefault
              ? Icons.favorite_border
              : Icons.folder_open_outlined,
          onPressed: () => _openFolder(folder),
        );
      },
    );
  }

  /// 第二层：某个收藏夹内的视频列表（顶部可返回、底部可翻页）。
  Widget _buildFavMediaList() {
    final folder = _activeFolder!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 190,
              child: TvActionButton(
                label: '返回收藏夹',
                icon: Icons.arrow_back,
                onPressed: _loadFavFolders,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${folder.title} · ${_favMedias.length} 项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _favMedias.isEmpty
              ? Center(
                  child: Text(
                    _favLoading ? '正在加载…' : '该收藏夹暂无可播放的视频',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : _buildVideoList(_favMedias, showFavoriteButton: false),
        ),
        if (_favHasMore)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              height: 44,
              child: TvActionButton(
                label: _favLoading ? '正在加载…' : '加载更多',
                icon: Icons.expand_more,
                onPressed: _favLoading ? () {} : _loadMoreFavMedias,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessage(
    ColorScheme scheme, {
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 44, color: scheme.outline),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 150,
            child: TvActionButton(
              label: actionLabel,
              icon: Icons.refresh,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList(
    List<BiliVideo> videos, {
    bool showFavoriteButton = true,
  }) {
    return ListView.separated(
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final video = videos[index];
        final favorited = _isVideoFavorited(video);
        return Row(
          children: <Widget>[
            Expanded(
              child: TvActionButton(
                label: video.title,
                value: '${video.author} · ${video.durationLabel}',
                icon: Icons.smart_display_outlined,
                selected: _selected?.bvid == video.bvid,
                onPressed: () => _openDetail(video),
              ),
            ),
            // B 站收藏夹视图不显示本机星标按钮，避免与账号收藏混淆。
            if (showFavoriteButton) ...<Widget>[
              const SizedBox(width: 8),
              TvIconButton(
                icon: favorited ? Icons.star : Icons.star_border,
                semanticLabel: favorited ? '取消收藏' : '收藏',
                size: 34,
                onPressed: () => _toggleFavoriteVideo(video),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 收藏 / 历史播放按普通歌单歌曲处理：点击即播，直接显示元数据与封面，
  /// 列表内不提供任何额外的「更多」菜单。
  Widget _buildSongList(List<Song> songs) {
    return ListView.separated(
      itemCount: songs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final song = songs[index];
        return Row(
          children: <Widget>[
            RemoteArtwork(mediaUrl: song.filePath, size: 46),
            const SizedBox(width: 10),
            Expanded(
              child: TvActionButton(
                label: song.title,
                value: '${song.artist} · ${_fmt(song.duration)}',
                onPressed: () => _playSong(song),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetail(ColorScheme scheme) {
    final video = _selected;
    if (video == null) return const SizedBox.shrink();
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
                onPressed: () => _openDetail(video),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (detail.cover.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    detail.cover,
                    headers: BiliClient.instance.imageHeaders,
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.smart_display_outlined,
                      size: 48,
                      color: scheme.outline,
                    ),
                  ),
                ),
              if (detail.cover.isNotEmpty) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${detail.author} · 共 ${detail.pages.length} 个分 P',
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
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TvActionButton(
                  label: '播放全部',
                  icon: Icons.play_arrow,
                  focusNode: _playAllFocusNode,
                  onPressed: () => _playAllPages(enqueue: false),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TvActionButton(
                  label: _isVideoFavorited(video) ? '取消收藏' : '收藏',
                  icon: _isVideoFavorited(video)
                      ? Icons.star
                      : Icons.star_border,
                  onPressed: _toggleFavoriteDetail,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TvActionButton(
                  label: '加入队列',
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
                  onPressed: () => _playPages(index, enqueue: false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
