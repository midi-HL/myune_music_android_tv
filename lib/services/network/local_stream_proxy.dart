import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import 'bilibili_client.dart';
import 'ftp_client.dart';
import 'google_drive_client.dart';
import 'remote_source.dart';
import 'remote_stream.dart';
import 'webdav_client.dart';

/// 本机流代理：把 WebDAV / FTP / Google Drive / 哔哩哔哩 CDN 统一包装成
/// `http://127.0.0.1:<port>/starnote/<token>`，交给 mpv 播放。
///
/// 这样 `AudioService.playSong()` 里原有的 `Media(filePath)` 一个字都不用改，
/// 同时解决了三件事：
///   1. mpv 不认识 FTP / WebDAV 协议，也不带 B 站 CDN 必需的 Referer/Cookie；
///   2. 代理支持 HTTP Range，网络流可以拖动进度；
///   3. 只按需拉流、不落盘，电视本地容量有限也能听整个网盘。
///
/// 端口取固定的一小段（18765-18774），token 固定，因此重启应用后
/// 已保存队列里的 URL 仍然有效，不需要重新解析。
class LocalStreamProxy {
  LocalStreamProxy._();

  static final LocalStreamProxy instance = LocalStreamProxy._();

  static const String token = 'starnote';
  static const List<int> _ports = <int>[
    18765,
    18766,
    18767,
    18768,
    18769,
    18770,
    18771,
    18772,
    18773,
    18774,
  ];

  HttpServer? _server;
  int? _port;
  Future<void>? _starting;

  int? get port => _port;
  bool get isRunning => _server != null;

  /// 在 main() 里调用一次。失败不抛给上层，页面会在用到时报出可读错误。
  Future<void> start() async {
    if (_server != null) return;
    final pending = _starting;
    if (pending != null) return pending;
    final future = _startInternal();
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _startInternal() async {
    HttpServer? bound;
    for (final candidate in _ports) {
      try {
        bound = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidate,
          shared: false,
        );
        _port = candidate;
        break;
      } catch (_) {
        // 端口被占用时顺延到下一个。
      }
    }
    if (bound == null) {
      throw StateError('无法启动本机流代理：端口 18765-18774 均被占用');
    }
    _server = bound;
    bound.listen(
      _handle,
      onError: (Object _, StackTrace __) {
        // 单个请求异常已经在 _handle 内处理，这里只防止 server 流被错误终止。
      },
    );
  }

  static bool isProxyUrl(String url) {
    return url.startsWith('http://127.0.0.1:') && url.contains('/$token/');
  }

  /// 是否为 B 站媒体标识 `bilibili:{bvid}:{cid}[:{mode}]`。
  /// 老队列 / 外部传入的标识不能直接交给 `Media()`，需要先规范化成代理 URL。
  static bool isMediaId(String value) =>
      value.startsWith('bilibili:') || value.startsWith('nas:');

  /// 网络硬盘 / 共享网盘的目标。
  ///
  /// 元数据一起编码进 URL：应用重启后播放队列里保存的仍是这个 URL，
  /// `RemoteMediaRegistry` 可以直接从 URL 还原标题/歌手/封面，不需要重新联网枚举。
  /// [proto] / [mediaId] 显式写入，避免协议与媒体标识在传递中丢失或错位。
  String urlForNas(
    String sourceId,
    String remotePath, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? artworkUrl,
    String? proto,
    String? mediaId,
  }) {
    return urlFor(<String, dynamic>{
      'k': 'nas',
      's': sourceId,
      'p': remotePath,
      if (proto != null && proto.isNotEmpty) 'proto': proto,
      if (mediaId != null && mediaId.isNotEmpty) 'id': mediaId,
      if (title != null && title.isNotEmpty) 't': title,
      if (artist != null && artist.isNotEmpty) 'r': artist,
      if (album != null && album.isNotEmpty) 'l': album,
      if (durationSeconds != null && durationSeconds > 0) 'd': durationSeconds,
      if (artworkUrl != null && artworkUrl.isNotEmpty) 'u': artworkUrl,
    });
  }

  /// B 站流目标，身份沿用 BiliMusic-Desktop 的 `bilibili:{bvid}:{cid}` 语义。
  /// Google Drive 只读文件的流目标。
  /// [fileId] 是 Drive 的 file id；媒体标识用 `gd:<fileId>`，
  /// 让收藏 / 历史 / 标签缓存有稳定 key（不受代理端口漂移影响）。
  String urlForDrive(
    String sourceId,
    String fileId, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? mediaId,
  }) {
    return urlFor(<String, dynamic>{
      'k': 'gd',
      'proto': 'gdrive',
      's': sourceId,
      'p': fileId,
      'id': mediaId ?? 'gd:$fileId',
      if (title != null && title.isNotEmpty) 't': title,
      if (artist != null && artist.isNotEmpty) 'r': artist,
      if (album != null && album.isNotEmpty) 'l': album,
      if (durationSeconds != null && durationSeconds > 0) 'd': durationSeconds,
    });
  }

  String urlForBili(
    String bvid,
    int cid,
    BiliStreamMode mode, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
    String? artworkUrl,
    String? mediaId,
  }) {
    return urlFor(<String, dynamic>{
      'k': 'bili',
      'proto': 'bilibili',
      'id': mediaId ?? 'bilibili:$bvid:$cid',
      'b': bvid,
      'c': cid,
      'm': mode.name,
      if (title != null && title.isNotEmpty) 't': title,
      if (artist != null && artist.isNotEmpty) 'r': artist,
      if (album != null && album.isNotEmpty) 'l': album,
      if (durationSeconds != null && durationSeconds > 0) 'd': durationSeconds,
      if (artworkUrl != null && artworkUrl.isNotEmpty) 'u': artworkUrl,
    });
  }

  String urlFor(Map<String, dynamic> target) {
    final port = _port;
    if (port == null) {
      throw StateError('本机流代理尚未启动，请重启应用');
    }
    final normalized = normalizeTarget(target);
    final payload = base64UrlEncode(utf8.encode(jsonEncode(normalized)))
        .replaceAll('=', '');
    return 'http://127.0.0.1:$port/$token/$payload';
  }

  /// 解码 token 并规范化。同时兼容两类历史 / 外部输入：
  ///   * base64url(JSON)（当前版本生成的代理 URL）；
  ///   * 裸媒体标识 `bilibili:BVxxx:123[:audio]`（旧队列 / 第三方传入）。
  static Map<String, dynamic>? decodeToken(String rawToken) {
    Map<String, dynamic>? decoded;
    try {
      final text = utf8.decode(
        base64Url.decode(base64Url.normalize(rawToken)),
      );
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      decoded = null;
    }
    if (decoded == null && isMediaId(rawToken)) {
      decoded = <String, dynamic>{'id': rawToken};
    }
    if (decoded == null) return null;
    return normalizeTarget(decoded);
  }

  /// 把各种别名 / 旧写法统一成规范 target。
  ///
  /// 这是「媒体标识、协议与 audio/video 类型映射异常」的集中修正点：
  /// 兼容 kind 别名、字段别名、`bilibili:{bvid}:{cid}` 媒体标识、
  /// `proto` 协议字段，以及 audio / video 的多种写法。
  static Map<String, dynamic> normalizeTarget(Map<String, dynamic> raw) {
    final t = <String, dynamic>{...raw};

    void alias(String canonical, List<String> others) {
      if (t.containsKey(canonical) &&
          t[canonical] != null &&
          t[canonical].toString().isNotEmpty) {
        return;
      }
      for (final key in others) {
        final value = t[key];
        if (value != null && value.toString().isNotEmpty) {
          t[canonical] = value;
          return;
        }
      }
    }

    // 1) 流目标类型（kind）
    var kind = (t['k'] ?? t['kind'] ?? t['type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final idRaw = (t['id'] ?? t['mediaId'] ?? t['media'] ?? t['mid'] ?? '')
        .toString()
        .trim();
    if (kind.isEmpty && idRaw.startsWith('bilibili:')) kind = 'bili';
    if (kind.isEmpty && idRaw.startsWith('nas:')) kind = 'nas';
    if (kind.isEmpty && idRaw.startsWith('gd:')) kind = 'gd';
    switch (kind) {
      case 'gd':
      case 'gdrive':
      case 'googledrive':
      case 'drive':
        kind = 'gd';
        break;
      case 'nas':
      case 'webdav':
      case 'dav':
      case 'ftp':
      case 'http':
      case 'https':
      case 'network':
      case 'share':
        if (!t.containsKey('proto') && kind != 'nas') {
          t['proto'] = kind;
        }
        kind = 'nas';
        break;
      case 'bili':
      case 'bilibili':
      case 'b':
      case 'bv':
      case 'b23':
        kind = 'bili';
        break;
    }
    t['k'] = kind;

    // 2) 字段别名
    alias('s', <String>['sourceId', 'src', 'source', 'sid']);
    alias('p', <String>['path', 'href', 'remotePath', 'file', 'url']);
    alias('b', <String>['bvid', 'bv', 'vid']);
    alias('c', <String>['cid', 'pageId', 'page_id']);
    alias('m', <String>['mode', 'stream', 'streamType', 'quality']);
    alias('t', <String>['title', 'name']);
    alias('r', <String>['artist', 'author', 'up', 'singer']);
    alias('l', <String>['album']);
    alias('d', <String>['duration', 'durationSeconds', 'len']);
    alias('u', <String>['cover', 'art', 'artwork', 'pic', 'coverUrl']);
    alias('proto', <String>['scheme', 'protocol', 'pcol']);
    alias('id', <String>['mediaId', 'media', 'mid']);

    // 3) 媒体标识 `bilibili:{bvid}:{cid}[:{mode}]` 补全参数
    final id = (t['id'] ?? '').toString().trim();
    if (id.startsWith('bilibili:')) {
      final parts = id.split(':');
      if (parts.length >= 3) {
        t['k'] = 'bili';
        t.putIfAbsent('b', () => parts[1]);
        final cid = int.tryParse(parts[2]) ?? t['c'];
        if (cid != null) t['c'] = cid;
        if (parts.length >= 4 && !t.containsKey('m')) t['m'] = parts[3];
      }
    }

    // 4) audio / video 类型别名统一成枚举名
    final mode = (t['m'] ?? '').toString().toLowerCase().trim();
    const videoAliases = <String>{
      'video', 'v', '1', 'durl', 'flv', 'mp4', 'progressive', 'true',
    };
    t['m'] = videoAliases.contains(mode) ? 'video' : 'audio';

    // 5) 协议字段规范化（仅作元数据，实际客户端以 RemoteSource.type 为准）
    final proto = (t['proto'] ?? '').toString().toLowerCase().trim();
    if (kind == 'bili') {
      t['proto'] = 'bilibili';
    } else if (kind == 'gd') {
      t['proto'] = 'gdrive';
    } else if (proto == 'ftp' || proto == 'ftps') {
      t['proto'] = 'ftp';
    } else {
      t['proto'] = 'webdav';
    }
    return t;
  }

  RemoteStreamOpener _resolve(Map<String, dynamic> target) {
    final kind = target['k']?.toString();
    if (kind == 'nas') {
      return (int? start, int? end) =>
          _openNas(target, start: start, end: end);
    }
    if (kind == 'bili') {
      return (int? start, int? end) =>
          _openBili(target, start: start, end: end);
    }
    if (kind == 'gd') {
      return (int? start, int? end) =>
          _openDrive(target, start: start, end: end);
    }
    throw StateError('未知的流目标类型：$kind（target=$target）');
  }

  Future<RemoteStreamResult> _openDrive(
    Map<String, dynamic> target, {
    int? start,
    int? end,
  }) async {
    final sourceId = target['s']?.toString() ?? '';
    final source = RemoteSourceStore.instance.byId(sourceId);
    if (source == null) {
      throw StateError('该 Google Drive 源已被删除，请重新添加');
    }
    final fileId = target['p']?.toString() ?? '';
    if (fileId.isEmpty) throw StateError('Google Drive 文件 id 为空');
    return GoogleDriveClient(source).open(fileId, start: start, end: end);
  }

  Future<RemoteStreamResult> _openNas(
    Map<String, dynamic> target, {
    int? start,
    int? end,
  }) async {
    final sourceId = target['s']?.toString() ?? '';
    final source = RemoteSourceStore.instance.byId(sourceId);
    if (source == null) {
      throw StateError('该网络源已被删除，请在「网络媒体」里重新添加');
    }
    final path = target['p']?.toString() ?? '';
    if (path.isEmpty) throw StateError('远程文件路径为空');
    // 以配置里的协议为唯一可信来源；URL 中的 proto 字段只作元数据，
    // 避免别名 / 旧数据把 WebDAV 请求错发到 FTP 端口。
    if (source.type == RemoteSourceType.webdav) {
      // 自建网盘桥首包可能要几十秒；放宽到 45s（仍小于 mpv 的 60s），
      // 避免播放器先放弃导致 loading failed。
      return WebDavClient(source).open(
        path,
        start: start,
        end: end,
        headerTimeout: const Duration(seconds: 45),
      );
    }
    return FtpClient(source).open(path, start: start, end: end);
  }

  Future<RemoteStreamResult> _openBili(
    Map<String, dynamic> target, {
    int? start,
    int? end,
  }) async {
    final bvid = target['b']?.toString() ?? '';
    final cidRaw = target['c'];
    final cid = (cidRaw is num)
        ? cidRaw.toInt()
        : int.tryParse(cidRaw?.toString() ?? '') ?? 0;
    final mode = target['m']?.toString() == 'video'
        ? BiliStreamMode.video
        : BiliStreamMode.audio;
    if (bvid.isEmpty || cid <= 0) {
      throw StateError('B 站流参数不完整，请重新打开该视频');
    }

    final url = await BiliClient.instance.streamUrl(
      bvid: bvid,
      cid: cid,
      mode: mode,
    );
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(BiliClient.instance.cdnHeaders);
      final range = formatRangeHeader(start, end);
      if (range.isNotEmpty) request.headers['Range'] = range;
      // CDNs / 自建反代首包也可能偏慢，统一放宽到 45 秒（< mpv 60 秒）。
      final response = await client.send(request).timeout(
            const Duration(seconds: 45),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw Exception('B 站 CDN 返回 HTTP ${response.statusCode}');
      }
      final info = describeHttpRange(
        contentRange: response.headers['content-range'],
        contentLength: response.contentLength,
        requestedStart: start,
        requestedEnd: end,
        upstreamPartial: response.statusCode == 206,
      );
      return RemoteStreamResult(
        bytes: limitByteStream(response.stream, info.limit),
        totalLength: info.totalLength,
        servedStart: info.servedStart,
        servedEnd: info.servedEnd,
        contentType: response.headers['content-type'] ??
            guessContentType(mode == BiliStreamMode.video
                ? 'stream.mp4'
                : 'stream.m4a'),
        close: () async {
          client.close();
        },
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    RemoteStreamResult? opened;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set('Allow', 'GET, HEAD');
        await response.close();
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments[0] != token) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final target = decodeToken(segments[1]);
      if (target == null || target['k'] == null || target['k'] == '') {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }

      int? start;
      int? end;
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null) {
        final match = RegExp(
          r'bytes=(\d*)-(\d*)',
          caseSensitive: false,
        ).firstMatch(rangeHeader);
        if (match != null) {
          final from = match.group(1) ?? '';
          final to = match.group(2) ?? '';
          if (from.isNotEmpty) start = int.tryParse(from);
          if (to.isNotEmpty) end = int.tryParse(to);
          // 后缀型 Range（bytes=-500）暂不支持，按从头开始处理。
        }
      }

      opened = await _resolve(target)(start, end);
      var result = opened;

      // 上游不给总长度时无法构造合法 Content-Range。关掉这次带 Range 的流，
      // 重新从 0 无 Range 拉；若仍拿不到长度，就退化为不带 Range 语义的
      // 200 顺序流（完整、从 0 开始），避免给 mpv 一个截断的 206。
      bool sequentialFallback = false;
      if (rangeHeader != null && result.totalLength == null) {
        await result.close?.call();
        opened = await _resolve(target)(null, null);
        result = opened;
        if (result.totalLength == null) sequentialFallback = true;
      }

      final int? effectiveStart = sequentialFallback ? null : start;
      final int? effectiveEnd = sequentialFallback ? null : end;
      final total = result.totalLength;

      // 上游忽略了 Range（返回完整文件、起点为 0）而客户端请求了非零起点：
      // 在代理侧真正跳过起点之前的字节，再按终点截断，得到合法 206。
      // 旧实现会把「从 0 开始」的字节谎报成指定区间，mpv 拖动进度后
      // 收到错位数据，报 MpvEndFileError(code:-13, loading failed)。
      if (!sequentialFallback &&
          effectiveStart != null &&
          effectiveStart > 0 &&
          result.servedStart == 0) {
        int? servedEnd = effectiveEnd ??
            (total != null && total > 0 ? total - 1 : null);
        if (total != null && servedEnd != null && servedEnd > total - 1) {
          servedEnd = total - 1;
        }
        Stream<List<int>> stream = skipByteStream(result.bytes, effectiveStart);
        if (servedEnd != null && servedEnd >= effectiveStart) {
          stream = limitByteStream(stream, servedEnd - effectiveStart + 1);
        }
        result = RemoteStreamResult(
          bytes: stream,
          totalLength: total,
          servedStart: effectiveStart,
          servedEnd: servedEnd,
          contentType: result.contentType,
          close: result.close,
        );
      }

      var servedEnd = result.servedEnd;
      if (servedEnd == null && total != null && total > 0) {
        servedEnd = total - 1;
      }
      final isPartial =
          !sequentialFallback && rangeHeader != null && total != null;
      response.statusCode =
          isPartial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.set(
        'Accept-Ranges',
        (isPartial || (total != null && !sequentialFallback))
            ? 'bytes'
            : 'none',
      );
      response.headers.set('Cache-Control', 'no-store');
      if (result.contentType != null) {
        try {
          response.headers.contentType = ContentType.parse(result.contentType!);
        } catch (_) {
          // 非法 Content-Type 交给 mpv 自己嗅探。
        }
      }
      if (total != null && servedEnd != null) {
        final length = servedEnd - result.servedStart + 1;
        if (length >= 0) response.headers.contentLength = length;
        if (isPartial) {
          response.headers.set(
            'Content-Range',
            'bytes ${result.servedStart}-$servedEnd/$total',
          );
        }
      } else if (total != null) {
        response.headers.contentLength = total - result.servedStart;
      }

      if (request.method == 'HEAD') {
        await response.close();
        await result.close?.call();
        opened = null;
        return;
      }

      try {
        await response.addStream(result.bytes);
      } finally {
        await response.close();
        await result.close?.call();
        opened = null;
      }
    } catch (error, stack) {
      // 这里过去会静默返回 502 空正文，mpv 只会报 loading failed，
      // 无法定位是鉴权、协议、媒体标识还是 CDN 的问题。写出诊断日志。
      developer.log(
        '流代理请求失败：${request.method} ${request.uri} -> $error',
        name: 'StarNoteProxy',
        error: error,
        stackTrace: stack,
      );
      try {
        await opened?.close?.call();
      } catch (_) {}
      // 若响应头已经发出，statusCode 赋值会抛 HttpException，忽略即可。
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
