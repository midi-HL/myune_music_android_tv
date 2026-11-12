import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../page/playlist/playlist_models.dart';
import 'bili_library.dart';
import 'bilibili_client.dart';
import 'ftp_client.dart';
import 'google_drive_client.dart';
import 'local_stream_proxy.dart';
import 'network_library.dart';
import 'network_tag_reader.dart';
import 'remote_entry.dart';
import 'remote_media_registry.dart';
import 'remote_source.dart';
import 'webdav_client.dart';

/// 网络媒体功能的统一门面：应用启动、目录枚举、把远端条目变成可播放的 Song。
///
/// 页面只依赖这一层，不直接碰协议客户端 / 代理 / 注册表。
class NetworkMediaService {
  NetworkMediaService._();

  /// main() 里调用。代理启动失败不应阻断应用其它功能，因此吞掉异常，
  /// 页面用到代理时再给出可读提示。
  static Future<void> initialize() async {
    await RemoteSourceStore.instance.load();
    await BiliAuthStore.instance.load();
    await BiliLibraryStore.instance.load();
    // 网络硬盘「收藏」与内嵌标签缓存：两者都是纯本地 IO，不联网。
    // 顺序不能反 —— 收藏里的 Song 要先注册进 RemoteMediaRegistry，歌单加载
    // 时 _parseSongMetadata() 才能零网络拿到标题 / 封面 / 时长等元信息。
    await NetworkLibraryStore.instance.load();
    await NetworkTagReader.initialize();
    try {
      await LocalStreamProxy.instance.start();
    } catch (_) {
      // 端口全被占用时，网络媒体页会在生成 URL 时提示重启应用。
    }
  }

  static Future<List<RemoteEntry>> listDirectory(
    RemoteSource source,
    String path,
  ) async {
    final target = path.trim().isEmpty ? _rootOf(source) : path;
    return switch (source.type) {
      RemoteSourceType.googleDrive => GoogleDriveClient(source).list(target),
      RemoteSourceType.webdav => WebDavClient(source).list(target),
      RemoteSourceType.ftp => FtpClient(source).list(target),
    };
  }

  static String rootOf(RemoteSource source) => _rootOf(source);

  static String _rootOf(RemoteSource source) {
    return switch (source.type) {
      RemoteSourceType.googleDrive => GoogleDriveClient.rootOf(source),
      RemoteSourceType.webdav => source.webdavBaseUri.toString(),
      RemoteSourceType.ftp => source.ftpRoot,
    };
  }

  /// 在当前目录里找常见的专辑封面文件，返回一个可通过本机代理读取的 URL。
  ///
  /// 封面同样走「按需拉流、不落盘」：URL 编码的是网盘上的图片路径，
  /// 代理会补上 WebDAV / FTP 鉴权。`RemoteMediaRegistry.artworkFor()` 会在
  /// 需要显示封面时下载它，播放列表与媒体会话都能拿到 artwork。
  static String? directoryArtworkUrl(
    RemoteSource source,
    List<RemoteEntry> entries,
  ) {
    const candidates = <String>[
      'cover.jpg',
      'cover.jpeg',
      'cover.png',
      'folder.jpg',
      'folder.jpeg',
      'folder.png',
      'front.jpg',
      'front.png',
      'albumart.jpg',
      'albumart.png',
      'thumb.jpg',
    ];
    RemoteEntry? cover;
    for (final name in candidates) {
      for (final entry in entries) {
        if (!entry.isDirectory && entry.name.toLowerCase() == name) {
          cover = entry;
          break;
        }
      }
      if (cover != null) break;
    }
    if (cover == null) return null;
    try {
      return LocalStreamProxy.instance.urlForNas(
        source.id,
        cover.path,
        title: cover.name,
        proto: source.type == RemoteSourceType.ftp ? 'ftp' : 'webdav',
      );
    } catch (_) {
      return null;
    }
  }

  /// 常见命名 `歌手 - 标题.mp3` 自动拆出歌手，避免网盘音乐全部显示「未知歌手」。
  /// 返回 `[title, artist]`。
  static List<String> splitTitleArtist(String name) {
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final match = RegExp(r'\s+[-–—~]\s+').firstMatch(base);
    if (match != null) {
      final artist = base.substring(0, match.start).trim();
      final title = base.substring(match.end).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return <String>[title, artist];
      }
    }
    return <String>[base, '未知歌手'];
  }

  /// 把一个网络硬盘音频文件构造成 Song，并登记元数据。
  /// 把一个 Google Drive 音频文件构造成 Song（只读源）。
  ///
  /// 与 nasSong 一样把元数据编码进代理 URL，并合并已读到的内嵌标签，
  /// 这样收藏 / 播放队列 / 播放页都能直接显示真实标题与封面。
  static Song driveSong({
    required RemoteSource source,
    required RemoteEntry entry,
    String? album,
    Uint8List? albumArt,
  }) {
    final parsed = splitTitleArtist(entry.name);
    final title = parsed[0];
    final artist = parsed[1];
    final resolvedAlbum =
        (album == null || album.trim().isEmpty) ? source.name : album.trim();
    final url = LocalStreamProxy.instance.urlForDrive(
      source.id,
      entry.path,
      title: title,
      artist: artist,
      album: resolvedAlbum,
      mediaId: 'gd:${entry.path}',
    );
    final song = Song(
      title: title,
      artist: artist,
      album: resolvedAlbum,
      filePath: url,
      albumArt: albumArt,
    );
    final enriched = NetworkTagReader.applyToSong(url, song);
    RemoteMediaRegistry.register(url, enriched);
    final art = enriched.albumArt;
    if (art != null && art.isNotEmpty) {
      RemoteMediaRegistry.registerArtwork(url, art);
    }
    return enriched;
  }

  static Song nasSong({
    required RemoteSource source,
    required RemoteEntry entry,
    String? artist,
    String? album,
    int? durationSeconds,
    String? artworkUrl,
    Uint8List? albumArt,
  }) {
    final parsed = splitTitleArtist(entry.name);
    final title = parsed[0];
    final resolvedArtist =
        (artist == null || artist.trim().isEmpty) ? parsed[1] : artist.trim();
    final resolvedAlbum =
        (album == null || album.trim().isEmpty) ? source.name : album.trim();
    final url = LocalStreamProxy.instance.urlForNas(
      source.id,
      entry.path,
      title: title,
      artist: resolvedArtist,
      album: resolvedAlbum,
      durationSeconds: durationSeconds,
      artworkUrl: artworkUrl,
      proto: source.type == RemoteSourceType.ftp ? 'ftp' : 'webdav',
      mediaId: 'nas:${source.id}:${entry.path.hashCode}',
    );
    final song = Song(
      title: title,
      artist: resolvedArtist,
      album: resolvedAlbum,
      filePath: url,
      albumArt: albumArt,
      duration: (durationSeconds != null && durationSeconds > 0)
          ? Duration(seconds: durationSeconds)
          : null,
    );
    // 已读到的内嵌标签（标题 / 歌手 / 专辑 / 封面 / 时长）优先于文件名拆分，
    // 让网络硬盘歌曲在网络媒体页、收藏列表、播放页都能显示真实元信息。
    final enriched = NetworkTagReader.applyToSong(url, song);
    RemoteMediaRegistry.register(url, enriched);
    final art = enriched.albumArt;
    if (art != null && art.isNotEmpty) {
      RemoteMediaRegistry.registerArtwork(url, art);
    }
    return enriched;
  }

  /// 把一个 B 站分 P 构造成 Song，并登记元数据（含封面 URL）。
  static Song biliSong({
    required String bvid,
    required int cid,
    required String title,
    required String author,
    required BiliStreamMode mode,
    int? durationSeconds,
    String? artworkUrl,
    String? mediaId,
  }) {
    final url = LocalStreamProxy.instance.urlForBili(
      bvid,
      cid,
      mode,
      title: title,
      artist: author.isEmpty ? '哔哩哔哩' : author,
      album: '哔哩哔哩 · $bvid',
      durationSeconds: durationSeconds,
      artworkUrl: artworkUrl,
      mediaId: mediaId,
    );
    final song = Song(
      title: title,
      artist: author.isEmpty ? '哔哩哔哩' : author,
      album: '哔哩哔哩 · $bvid',
      filePath: url,
      duration: (durationSeconds != null && durationSeconds > 0)
          ? Duration(seconds: durationSeconds)
          : null,
    );
    RemoteMediaRegistry.register(url, song);
    return song;
  }

  /// 网盘音频同目录下的同名外置字幕 / 歌词（.lrc / .srt / .ass / .ssa / .vtt）。
  ///
  /// 网络媒体不落盘，因此不能直接 `File.exists()`；改为按原路径换扩展名，
  /// 经本机流代理按需读取（鉴权与协议由代理补齐）。返回原始字节，
  /// 由 LyricsHandler 按 LRC / SRT 分别解析，避免服务层依赖歌词模型。
  static Future<Uint8List?> sidecarLyricsFor(String mediaUrl) async {
    final target = RemoteMediaRegistry.decodeTarget(mediaUrl);
    if (target == null || target['k'] != 'nas') return null;
    final sourceId = (target['s'] ?? '').toString();
    final path = (target['p'] ?? '').toString();
    if (sourceId.isEmpty || path.isEmpty) return null;
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    if (dot <= slash) return null;
    final base = path.substring(0, dot);
    for (final ext in const <String>['lrc', 'srt', 'ass', 'ssa', 'vtt']) {
      final String url;
      try {
        url = LocalStreamProxy.instance.urlForNas(sourceId, '$base.$ext');
      } catch (_) {
        return null;
      }
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.bodyBytes.isNotEmpty &&
            response.bodyBytes.length <= 512 * 1024) {
          return Uint8List.fromList(response.bodyBytes);
        }
      } catch (_) {
        // 该文件不存在或读取失败，继续尝试下一个扩展名。
      }
    }
    return null;
  }

  static bool get proxyReady => LocalStreamProxy.instance.isRunning;

  /// 应用启动时若端口被占用导致代理没起来，允许页面侧再试一次，
  /// 不必让用户重启整个应用。
  static Future<bool> ensureProxy() async {
    if (LocalStreamProxy.instance.isRunning) return true;
    try {
      await LocalStreamProxy.instance.start();
    } catch (_) {
      // 交给调用方提示用户。
    }
    return LocalStreamProxy.instance.isRunning;
  }
}
