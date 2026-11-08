import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_entry.dart';
import 'remote_source.dart';
import 'remote_stream.dart';

/// 极简 WebDAV 客户端：PROPFIND 列目录 + GET（支持 Range）读文件。
///
/// 只依赖已有的 `http` 包，不引入 xml/webdav 依赖；PROPFIND 响应用带命名空间
/// 通配的正则解析，兼容 `d:` / `D:` / 默认命名空间以及各厂商 NAS 的实现。
class WebDavClient {
  WebDavClient(this.source);

  final RemoteSource source;

  static final RegExp _responseRe = RegExp(
    r'<(?:[\w.\-]+:)?response\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?response>',
    caseSensitive: false,
  );
  static final RegExp _hrefRe = RegExp(
    r'<(?:[\w.\-]+:)?href\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?href>',
    caseSensitive: false,
  );
  static final RegExp _collectionRe = RegExp(
    r'<(?:[\w.\-]+:)?collection\s*/>',
    caseSensitive: false,
  );
  static final RegExp _lengthRe = RegExp(
    r'<(?:[\w.\-]+:)?getcontentlength\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?getcontentlength>',
    caseSensitive: false,
  );
  static final RegExp _modifiedRe = RegExp(
    r'<(?:[\w.\-]+:)?getlastmodified\b[^>]*>([\s\S]*?)</(?:[\w.\-]+:)?getlastmodified>',
    caseSensitive: false,
  );

  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop><d:resourcetype/><d:getcontentlength/>'
      '<d:getlastmodified/><d:displayname/></d:prop></d:propfind>';

  Map<String, String> get _authHeaders {
    final headers = <String, String>{
      'User-Agent': 'StarNote/1.0 (Android TV)',
      'Accept': '*/*',
    };
    if (source.username.trim().isNotEmpty) {
      final token = base64Encode(
        utf8.encode('${source.username}:${source.password}'),
      );
      headers['Authorization'] = 'Basic $token';
    }
    return headers;
  }

  Uri uriFor(String href) {
    final base = source.webdavBaseUri;
    final candidate = href.trim();
    if (candidate.isEmpty) return base;
    Uri? parsed;
    try {
      parsed = Uri.parse(candidate);
    } catch (_) {
      parsed = null;
    }
    if (parsed != null && parsed.hasScheme && parsed.hasAuthority) {
      return parsed;
    }
    return base.resolve(candidate);
  }

  /// 列出 [href] 目录的直属子项。首次进入时传空字符串表示配置里的根目录。
  Future<List<RemoteEntry>> list(String href) async {
    final client = http.Client();
    try {
      final target = uriFor(href);
      final request = http.Request('PROPFIND', target)
        ..headers.addAll(_authHeaders)
        ..headers['Depth'] = '1'
        ..headers['Content-Type'] = 'application/xml; charset=utf-8'
        ..body = _propfindBody;
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
          );
      final body = await response.stream.bytesToString().timeout(
            const Duration(seconds: 30),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'WebDAV PROPFIND 失败（HTTP ${response.statusCode}）：'
          '${_shortError(body)}',
        );
      }
      return _parsePropfind(body, target);
    } finally {
      client.close();
    }
  }

  /// 打开一个远端文件。start/end 是闭区间，null 表示从头 / 到尾。
  Future<RemoteStreamResult> open(
    String href, {
    int? start,
    int? end,
  }) async {
    final client = http.Client();
    try {
      final target = uriFor(href);
      final request = http.Request('GET', target)
        ..headers.addAll(_authHeaders);
      final range = formatRangeHeader(start, end);
      if (range.isNotEmpty) request.headers['Range'] = range;
      final response = await client.send(request).timeout(
            const Duration(seconds: 25),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw Exception('WebDAV GET 失败（HTTP ${response.statusCode}）');
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
            guessContentType(remoteEntryName(href, isDirectory: false)),
        close: () async {
          client.close();
        },
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  List<RemoteEntry> _parsePropfind(String body, Uri requestedDir) {
    final entries = <RemoteEntry>[];
    final seen = <String>{};
    final requestedPath = requestedDir.path;

    for (final match in _responseRe.allMatches(body)) {
      final block = match.group(1) ?? '';
      final hrefMatch = _hrefRe.firstMatch(block);
      if (hrefMatch == null) continue;
      final rawHref = xmlUnescape(hrefMatch.group(1) ?? '').trim();
      if (rawHref.isEmpty) continue;

      final isDirectory = _collectionRe.hasMatch(block);

      // PROPFIND Depth:1 会把自己也返回，跳过目录自身。
      var candidatePath = rawHref;
      try {
        final parsed = Uri.parse(rawHref);
        if (parsed.hasScheme) candidatePath = parsed.path;
      } catch (_) {
        candidatePath = rawHref;
      }
      final normalizedSelf = candidatePath.replaceAll(RegExp(r'/+$'), '');
      final normalizedRequested = requestedPath.replaceAll(RegExp(r'/+$'), '');
      if (normalizedSelf == normalizedRequested) continue;

      if (!seen.add(rawHref)) continue;

      final lengthMatch = _lengthRe.firstMatch(block);
      final modifiedMatch = _modifiedRe.firstMatch(block);
      int? size;
      if (lengthMatch != null) {
        size = int.tryParse((lengthMatch.group(1) ?? '').trim());
      }
      DateTime? modified;
      if (modifiedMatch != null) {
        modified = DateTime.tryParse((modifiedMatch.group(1) ?? '').trim());
      }

      entries.add(
        RemoteEntry(
          name: remoteEntryName(rawHref, isDirectory: isDirectory),
          path: rawHref,
          isDirectory: isDirectory,
          size: isDirectory ? null : size,
          modified: modified,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  String _shortError(String body) {
    final plain = body.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
    if (plain.isEmpty) return '服务端未返回正文';
    return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
  }
}
