import 'dart:async';

import '../../page/playlist/playlist_models.dart';
import 'bilibili_client.dart';
import 'ftp_client.dart';
import 'local_stream_proxy.dart';
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
    if (source.type == RemoteSourceType.webdav) {
      return WebDavClient(source).list(target);
    }
    return FtpClient(source).list(target);
  }

  static String rootOf(RemoteSource source) => _rootOf(source);

  static String _rootOf(RemoteSource source) {
    return source.type == RemoteSourceType.webdav
        ? source.webdavBaseUri.toString()
        : source.ftpRoot;
  }

  /// 把一个网络硬盘音频文件构造成 Song，并登记元数据。
  static Song nasSong({
    required RemoteSource source,
    required RemoteEntry entry,
  }) {
    final name = entry.name;
    final title = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final url = LocalStreamProxy.instance.urlForNas(
      source.id,
      entry.path,
      title: title,
      album: source.name,
    );
    final song = Song(
      title: title,
      artist: '未知歌手',
      album: source.name,
      filePath: url,
    );
    RemoteMediaRegistry.register(url, song);
    return song;
  }

  /// 把一个 B 站分 P 构造成 Song，并登记元数据。
  static Song biliSong({
    required String bvid,
    required int cid,
    required String title,
    required String author,
    required BiliStreamMode mode,
    int? durationSeconds,
  }) {
    final url = LocalStreamProxy.instance.urlForBili(
      bvid,
      cid,
      mode,
      title: title,
      artist: author.isEmpty ? '哔哩哔哩' : author,
      album: '哔哩哔哩 · $bvid',
      durationSeconds: durationSeconds,
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
