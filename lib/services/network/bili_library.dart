import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../page/playlist/playlist_models.dart';
import 'remote_media_registry.dart';

/// 哔哩哔哩的「收藏」与「历史播放」本地仓库。
///
/// 两者都以普通 [Song] 为单位持久化（而不是视频 / 分 P 对象），所以列表里
/// 每一项点一下就能直接播放，元数据与封面也随 Song 一起保存，不需要
/// 额外的「更多」菜单或二次解析。
class BiliLibraryStore {
  BiliLibraryStore._();

  static final BiliLibraryStore instance = BiliLibraryStore._();

  static const String _favoritesKey = 'starnote.bilibili.favorites.v1';
  static const String _historyKey = 'starnote.bilibili.history.v1';
  static const int _maxHistory = 100;

  final List<Song> _favorites = <Song>[];
  final List<Song> _history = <Song>[];
  bool _loaded = false;

  List<Song> get favorites => List<Song>.unmodifiable(_favorites);
  List<Song> get history => List<Song>.unmodifiable(_history);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    // 恢复时统一规范化：兼容旧版保存的裸媒体标识，并修正应用重启后
    // 本机流代理端口漂移，保证「收藏 / 历史播放」点一下就能播。
    _favorites
      ..clear()
      ..addAll(
        _decode(prefs.getStringList(_favoritesKey))
            .map(RemoteMediaRegistry.normalizeSong),
      );
    _history
      ..clear()
      ..addAll(
        _decode(prefs.getStringList(_historyKey))
            .map(RemoteMediaRegistry.normalizeSong),
      );
    _loaded = true;
    // 把恢复出来的 Song 连同封面一起回填进注册表，播放与列表显示时
    // 无需重新联网解析元数据 / 下载封面。
    for (final song in <Song>[..._favorites, ..._history]) {
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
        // 跳过损坏的历史条目。
      }
    }
    return songs;
  }

  List<String> _encode(List<Song> songs) =>
      songs.map((s) => jsonEncode(s.toJson())).toList();

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _encode(_favorites));
    await prefs.setStringList(_historyKey, _encode(_history));
  }

  bool isFavorite(String filePath) =>
      _favorites.any((s) => s.filePath == filePath);

  Future<bool> toggleFavorite(Song song) async {
    await load();
    final index = _favorites.indexWhere((s) => s.filePath == song.filePath);
    if (index >= 0) {
      _favorites.removeAt(index);
      await _persist();
      return false;
    }
    _favorites.insert(0, song);
    RemoteMediaRegistry.register(song.filePath, song);
    await _persist();
    return true;
  }

  Future<void> addFavorites(Iterable<Song> songs) async {
    await load();
    var changed = false;
    for (final song in songs) {
      if (song.filePath.isEmpty) continue;
      if (_favorites.any((s) => s.filePath == song.filePath)) continue;
      _favorites.insert(0, song);
      RemoteMediaRegistry.register(song.filePath, song);
      changed = true;
    }
    if (changed) await _persist();
  }

  Future<void> removeFavorite(String filePath) async {
    await load();
    _favorites.removeWhere((s) => s.filePath == filePath);
    await _persist();
  }

  Future<void> recordPlay(Song song) async {
    await load();
    if (song.filePath.isEmpty) return;
    _history.removeWhere((s) => s.filePath == song.filePath);
    _history.insert(0, song);
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
    RemoteMediaRegistry.register(song.filePath, song);
    await _persist();
  }

  Future<void> clearHistory() async {
    await load();
    _history.clear();
    await _persist();
  }
}
