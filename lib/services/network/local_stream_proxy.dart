import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'bilibili_client.dart';
import 'ftp_client.dart';
import 'remote_source.dart';
import 'remote_stream.dart';
import 'webdav_client.dart';

/// 本机流代理：把 WebDAV / FTP / 哔哩哔哩 CDN 统一包装成
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
    return url.startsWith('http://127.0.0.1:') &&
        url.contains('/$token/');
  }

  /// 网络硬盘 / 共享网盘的目标。
  ///
  /// 元数据一起编码进 URL：应用重启后播放队列里保存的仍是这个 URL，
  /// `RemoteMediaRegistry` 可以直接从 URL 还原标题/歌手，不需要重新联网枚举。
  String urlForNas(
    String sourceId,
    String remotePath, {
    String? title,
    String? artist,
    String? album,
  }) {
    return urlFor(<String, dynamic>{
      'k': 'nas',
      's': sourceId,
      'p': remotePath,
      if (title != null && title.isNotEmpty) 't': title,
      if (artist != null && artist.isNotEmpty) 'r': artist,
      if (album != null && album.isNotEmpty) 'l': album,
    });
  }

  /// B 站流目标，身份沿用 BiliMusic-Desktop 的 `bilibili:{bvid}:{cid}` 语义。
  String urlForBili(
    String bvid,
    int cid,
    BiliStreamMode mode, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
  }) {
    return urlFor(<String, dynamic>{
      'k': 'bili',
      'b': bvid,
      'c': cid,
      'm': mode.name,
      if (title != null && title.isNotEmpty) 't': title,
      if (artist != null && artist.isNotEmpty) 'r': artist,
      if (album != null && album.isNotEmpty) 'l': album,
      if (durationSeconds != null && durationSeconds > 0) 'd': durationSeconds,
    });
  }

  String urlFor(Map<String, dynamic> target) {
    final port = _port;
    if (port == null) {
      throw StateError('本机流代理尚未启动，请重启应用');
    }
    final payload = base64UrlEncode(utf8.encode(jsonEncode(target)))
        .replaceAll('=', '');
    return 'http://127.0.0.1:$port/$token/$payload';
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
    throw StateError('未知的流目标类型：$kind');
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
    if (source.type == RemoteSourceType.webdav) {
      return WebDavClient(source).open(path, start: start, end: end);
    }
    return FtpClient(source).open(path, start: start, end: end);
  }

  Future<RemoteStreamResult> _openBili(
    Map<String, dynamic> target, {
    int? start,
    int? end,
  }) async {
    final bvid = target['b']?.toString() ?? '';
    final cid = (target['c'] as num?)?.toInt() ??
        int.tryParse(target['c']?.toString() ?? '') ??
        0;
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
      final response = await client.send(request).timeout(
            const Duration(seconds: 25),
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

      Map<String, dynamic> target;
      try {
        final decoded = utf8.decode(
          base64Url.decode(base64Url.normalize(segments[1])),
        );
        final parsed = jsonDecode(decoded);
        if (parsed is! Map<String, dynamic>) throw const FormatException();
        target = parsed;
      } catch (_) {
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

      // 上游若不给总长度（例如 Content-Range: bytes 0-999/*、FTP SIZE 不支持），
      // 就无法构造合法的 Content-Range。此时若仍按 Range 起点返回，会把媒体
      // 截成一小段并错误地用 200 告诉 mpv「文件就这么大」。改为关掉这次带
      // Range 的流、重新从 0 顺序拉，用不带 Content-Length 的 200 流式返回。
      final bool forceFull = rangeHeader != null && result.totalLength == null;
      if (forceFull) {
        await result.close?.call();
        opened = await _resolve(target)(null, null);
        result = opened;
      }

      final total = result.totalLength;
      var servedEnd = result.servedEnd;
      if (servedEnd == null && total != null && total > 0) {
        servedEnd = total - 1;
      }
      // 上游长度未知时无法给出合法的 Content-Range，退回 200 顺序流，
      // 避免给 mpv 一个不完整的 206 响应。
      final isPartial =
          rangeHeader != null && total != null && !forceFull;
      response.statusCode =
          isPartial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.set('Accept-Ranges', 'bytes');
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
    } catch (_) {
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
