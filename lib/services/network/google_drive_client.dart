import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'google_drive_auth.dart';
import 'remote_entry.dart';
import 'remote_source.dart';
import 'remote_stream.dart';

/// Google Drive 只读客户端（Drive API v3）。
///
/// 与 WebDAV / FTP 并列为第三种网络源：用 refresh_token 换 access_token，
/// `files.list` 列目录、`files.get?alt=media` 拉流。Drive API 原生支持
/// HTTP Range（206 + Content-Range），拖动进度可用。
///
/// **只读**：不实现上传 / 新建文件夹 / 重命名 / 删除。scope 固定为
/// `https://www.googleapis.com/auth/drive.readonly`，由配对时提交的凭据决定。
class GoogleDriveClient {
  GoogleDriveClient(this.source);

  final RemoteSource source;

  static const String _api = 'https://www.googleapis.com/drive/v3';
  static const String _folderMime = 'application/vnd.google-apps.folder';
  static const Duration _timeout = Duration(seconds: 45);

  static const String scope = 'https://www.googleapis.com/auth/drive.readonly';

  /// 用户配置的根文件夹 ID；空表示「我的云端硬盘」根。
  static String rootOf(RemoteSource source) {
    final root = source.rootFolderId.trim();
    return root.isEmpty ? 'root' : root;
  }

  /// 列目录。folderId 是 Drive 的 file id（本改版把 RemoteEntry.path 直接当 id 用）。
  Future<List<RemoteEntry>> list(String folderId) async {
    final headers = await GoogleDriveAuth.headers(source);
    final out = <RemoteEntry>[];
    String? pageToken;
    do {
      final query = <String, String>{
        'q': "'${_escape(folderId)}' in parents and trashed = false",
        'spaces': 'drive',
        'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime)',
        'pageSize': '1000',
        'orderBy': 'folder,name_natural',
        if (pageToken != null) 'pageToken': pageToken,
      };
      final uri = Uri.parse('$_api/files').replace(queryParameters: query);
      late http.Response response;
      try {
        response = await http.get(uri, headers: headers).timeout(_timeout);
      } catch (error) {
        throw StateError('读取 Google Drive 目录失败：$error');
      }
      if (response.statusCode == 401) {
        GoogleDriveAuth.invalidate(source.id);
        throw StateError('Google Drive 授权已失效，请重新扫码配对');
      }
      if (response.statusCode != 200) {
        throw StateError(
          'Google Drive 目录读取失败（HTTP ${response.statusCode}）',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw StateError('Google Drive 返回格式异常');
      final files = decoded['files'];
      if (files is List) {
        for (final item in files) {
          if (item is! Map) continue;
          final id = (item['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final name = (item['name'] ?? id).toString();
          final isDir = (item['mimeType'] ?? '').toString() == _folderMime;
          final size = int.tryParse((item['size'] ?? '').toString());
          final modified = DateTime.tryParse(
            (item['modifiedTime'] ?? '').toString(),
          );
          out.add(
            RemoteEntry(
              name: name,
              path: id,
              isDirectory: isDir,
              size: size,
              modified: modified,
            ),
          );
        }
      }
      final next = decoded['nextPageToken'];
      pageToken = next == null ? null : next.toString();
    } while (pageToken != null && pageToken.isNotEmpty);
    return out;
  }

  /// 打开一个文件（支持 Range），交给本机流代理转发给播放器。
  Future<RemoteStreamResult> open(
    String fileId, {
    int? start,
    int? end,
  }) async {
    final headers = await GoogleDriveAuth.headers(source);
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$_api/files/${Uri.encodeComponent(fileId)}?alt=media'),
      )..headers.addAll(headers);
      final range = formatRangeHeader(start, end);
      if (range.isNotEmpty) request.headers['Range'] = range;
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode == 401) {
        GoogleDriveAuth.invalidate(source.id);
        await response.stream.drain<void>();
        throw StateError('Google Drive 授权已失效，请重新扫码配对');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw StateError(
          'Google Drive 读取失败（HTTP ${response.statusCode}）',
        );
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
        contentType:
            response.headers['content-type'] ?? 'application/octet-stream',
        close: () async => client.close(),
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  /// Drive 查询串里单引号与反斜杠要转义，避免文件夹 id 含特殊字符时查询出错。
  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'");
}
