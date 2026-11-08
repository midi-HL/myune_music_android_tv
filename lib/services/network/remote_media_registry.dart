import 'dart:convert';

import '../../page/playlist/playlist_models.dart';
import 'local_stream_proxy.dart';

/// 远端流的元数据注册表。
///
/// 网络音乐的 `Song.filePath` 是本机代理 URL，不是本地文件。原有
/// `_parseSongMetadata()` 会对本地文件做 `File.exists()` 与标签读取，
/// 对 URL 会误报「文件不存在 (解析失败)」。这里按 URL 保存浏览页构造好的
/// 标题 / 歌手 / 专辑 / 时长，播放链路只需在解析函数开头查一次表即可，
/// 完全不需要改动 `AudioService` / `Media()` / 播放队列。
///
/// 元数据同时编码在代理 URL 里（见 [LocalStreamProxy.urlForNas] /
/// [LocalStreamProxy.urlForBili]），因此应用重启后，恢复的播放队列里
/// 即使注册表为空也能从 URL 还原出正确的歌曲信息。
class RemoteMediaRegistry {
  RemoteMediaRegistry._();

  static final Map<String, Song> _entries = <String, Song>{};

  static void register(String url, Song song) {
    if (url.isEmpty) return;
    // 队列可能反复播放同一地址，控制内存占用上限，超出时淘汰最早项。
    if (_entries.length > 512) {
      _entries.remove(_entries.keys.first);
    }
    _entries[url] = song;
  }

  static Song? lookup(String url) {
    final direct = _entries[url];
    if (direct != null) return direct;
    if (!LocalStreamProxy.isProxyUrl(url)) return null;
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.length < 2 || segments[0] != LocalStreamProxy.token) {
        return null;
      }
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      if (decoded is! Map<String, dynamic>) return null;
      final title = decoded['t']?.toString();
      if (title == null || title.isEmpty) return null;
      final artist = decoded['r']?.toString();
      final album = decoded['l']?.toString();
      final duration = (decoded['d'] as num?)?.toInt();
      final song = Song(
        title: title,
        artist: (artist == null || artist.isEmpty) ? '未知歌手' : artist,
        album: (album == null || album.isEmpty) ? '网络媒体' : album,
        filePath: url,
        duration: (duration != null && duration > 0)
            ? Duration(seconds: duration)
            : null,
      );
      register(url, song);
      return song;
    } catch (_) {
      return null;
    }
  }

  static void clear() => _entries.clear();

  static int get length => _entries.length;

  /// 是否为本机流代理 URL。播放链路里凡是要走文件系统 / 本地标签读取的地方
  /// 都需要先判断这个，避免把 http:// 当成缺失文件。
  static bool isNetwork(String url) => LocalStreamProxy.isProxyUrl(url);
}
