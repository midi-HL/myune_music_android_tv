import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../page/playlist/playlist_models.dart';
import 'remote_media_registry.dart';

/// 网络硬盘（WebDAV / FTP）歌曲的「收藏」仓库。
///
/// 反哺自 XYkadicloud/myune_music v0.9.5-network.1 的「网络媒体收藏」思路，
/// 但按本项目语义落到已有的默认「收藏」歌单：
///  * 这里保存完整 [Song]（标题 / 歌手 / 专辑 / 封面 / 时长），重启后仍可
///    直接预览元信息，不用重新进网络媒体页逐层选目录；
///  * 收藏的同时把 filePath 写进默认「收藏」歌单，列表 / 全部歌曲都能看到；
///  * 启动 load() 时把 Song 与封面回填 [RemoteMediaRegistry]，歌单加载走
///    `_parseSongMetadata()` 就能零网络拿到正确标题与封面。
///
/// **只收网络硬盘**：哔哩哔哩有独立的 BiliLibraryStore（收藏 / 历史播放），
/// 两者互不混用；这里通过 `nas:` 媒体标识硬性过滤。
class NetworkLibraryStore {
  NetworkLibraryStore._();

  static final NetworkLibraryStore instance = NetworkLibraryStore._();

  static const String _favoritesKey = 'starnote.network.favorites.v1';

  final List<Song> _favorites = <Song>[];
  bool _loaded = false;

  List<Song> get favorites => List<Song>.unmodifiable(_favorites);

  /// 只接受网络硬盘媒体（WebDAV / FTP），排除哔哩哔哩与本地文件。
  static bool isNetworkDrive(Song song) {
    final id = RemoteMediaRegistry.mediaIdOf(song.filePath);
    if (id != null) return id.startsWith('nas:');
    final path = song.filePath;
    return path.startsWith('nas:') ||
        (RemoteMediaRegistry.isNetwork(path) &&
            RemoteMediaRegistry.decodeTarget(path)?['id']?.toString().startsWith(
                      'nas:',
                    ) ==
                true);
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _favorites
      ..clear()
      ..addAll(
        _decode(prefs.getStringList(_favoritesKey))
            .map(RemoteMediaRegistry.normalizeSong)
            .where(isNetworkDrive),
      );
    _loaded = true;
    // 回填注册表：歌单 / 播放队列 / 详情页都能直接显示标题、封面、时长。
    for (final song in _favorites) {
      RemoteMediaRegistry.register(song.filePath, song);
      if (song.albumArt != null && song.albumArt!.isNotEmpty) {
        RemoteMediaRegistry.registerArtwork(song.filePath, song.albumArt!);
      }
    }
  }

  List<Song> _decode(List<String>? raw) {
    if (raw == null) return <Song>[];
    final songs = <Song>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          songs.add(Song.fromJson(decoded));
        }
      } catch (_) {
        // 跳过损坏条目。
      }
    }
    return songs;
  }

  List<String> _encode() =>
      _favorites.map((s) => jsonEncode(s.toJson())).toList();

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _encode());
  }

  bool isFavorite(String filePath) => _favorites.any(
    (s) =>
        RemoteMediaRegistry.normalizePlayablePath(s.filePath) ==
        RemoteMediaRegistry.normalizePlayablePath(filePath),
  );

  /// 收藏 / 取消收藏。返回 true 表示「现在是已收藏」。
  Future<bool> toggle(Song song) async {
    await load();
    if (!isNetworkDrive(song)) return false;
    final normalized = RemoteMediaRegistry.normalizeSong(song);
    final key = RemoteMediaRegistry.normalizePlayablePath(normalized.filePath);
    final index = _favorites.indexWhere(
      (s) =>
          RemoteMediaRegistry.normalizePlayablePath(s.filePath) == key,
    );
    final added = index < 0;
    if (added) {
      _favorites.add(normalized);
      RemoteMediaRegistry.register(normalized.filePath, normalized);
      if (normalized.albumArt != null && normalized.albumArt!.isNotEmpty) {
        RemoteMediaRegistry.registerArtwork(
          normalized.filePath,
          normalized.albumArt!,
        );
      }
    } else {
      _favorites.removeAt(index);
    }
    await _persist();
    return added;
  }

  /// 批量加入（「全部加入收藏」用），返回实际新增数量。
  Future<int> addAll(Iterable<Song> songs) async {
    await load();
    var added = 0;
    for (final raw in songs) {
      if (!isNetworkDrive(raw)) continue;
      final song = RemoteMediaRegistry.normalizeSong(raw);
      final key = RemoteMediaRegistry.normalizePlayablePath(song.filePath);
      if (_favorites.any(
        (s) =>
            RemoteMediaRegistry.normalizePlayablePath(s.filePath) == key,
      )) {
        continue;
      }
      _favorites.add(song);
      RemoteMediaRegistry.register(song.filePath, song);
      if (song.albumArt != null && song.albumArt!.isNotEmpty) {
        RemoteMediaRegistry.registerArtwork(song.filePath, song.albumArt!);
      }
      added++;
    }
    if (added > 0) await _persist();
    return added;
  }

  Future<void> remove(String filePath) async {
    await load();
    final key = RemoteMediaRegistry.normalizePlayablePath(filePath);
    final before = _favorites.length;
    _favorites.removeWhere(
      (s) =>
          RemoteMediaRegistry.normalizePlayablePath(s.filePath) == key,
    );
    if (_favorites.length != before) await _persist();
  }
}
