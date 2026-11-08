import 'dart:async';

/// 代理转发一段远端字节流时的描述信息。
///
/// [totalLength] 是整个资源的长度（未知时为 null），[servedStart] /
/// [servedEnd] 是本次实际返回的区间（闭区间，servedEnd 为 null 表示到文件尾）。
/// 本机代理据此生成 200/206、Content-Length 与 Content-Range，mpv/FFmpeg
/// 才能对网络流做拖动进度。
class RemoteStreamResult {
  const RemoteStreamResult({
    required this.bytes,
    this.totalLength,
    this.servedStart = 0,
    this.servedEnd,
    this.contentType,
    this.close,
  });

  final Stream<List<int>> bytes;
  final int? totalLength;
  final int servedStart;
  final int? servedEnd;
  final String? contentType;
  final Future<void> Function()? close;
}

typedef RemoteStreamOpener =
    Future<RemoteStreamResult> Function(int? start, int? end);

/// 把上游字节流截断到最多 [limit] 字节。用于 FTP：FTP 没有「只取前 N 字节」
/// 的语义，REST + RETR 会一直发到文件尾，需要本地限速后才能正确响应
/// `Range: bytes=a-b`。达到上限后 `break` 会取消订阅，由调用方关闭套接字。
Stream<List<int>> limitByteStream(Stream<List<int>> source, int? limit) async* {
  if (limit == null) {
    yield* source;
    return;
  }
  var remaining = limit;
  await for (final chunk in source) {
    if (remaining <= 0) break;
    if (chunk.length <= remaining) {
      yield chunk;
      remaining -= chunk.length;
    } else {
      yield chunk.sublist(0, remaining);
      remaining = 0;
    }
  }
}

/// HTTP 上游响应的 Range 描述，供 WebDAV / B 站 CDN 两条链路共用，
/// 避免 200/206、Content-Length、Content-Range 的推导出现分叉。
class RemoteRangeInfo {
  const RemoteRangeInfo({
    required this.totalLength,
    required this.servedStart,
    required this.servedEnd,
    required this.limit,
  });

  final int? totalLength;
  final int servedStart;
  final int? servedEnd;
  final int? limit;
}

RemoteRangeInfo describeHttpRange({
  required String? contentRange,
  required int? contentLength,
  required int? requestedStart,
  required int? requestedEnd,
}) {
  var servedStart = requestedStart ?? 0;
  int? servedEnd = requestedEnd;
  int? total;
  final match = contentRange == null
      ? null
      : RegExp(
          r'bytes\s+(\d+)-(\d+)/(\d+|\*)',
          caseSensitive: false,
        ).firstMatch(contentRange);
  if (match != null) {
    servedStart = int.tryParse(match.group(1)!) ?? servedStart;
    servedEnd = int.tryParse(match.group(2)!);
    final totalText = match.group(3)!;
    total = totalText == '*' ? null : int.tryParse(totalText);
  } else {
    // 上游忽略了 Range，退回 200：从 0 开始，按请求终点截断。
    total = (contentLength != null && contentLength >= 0) ? contentLength : null;
    servedStart = 0;
    servedEnd = requestedEnd ?? (total != null && total > 0 ? total - 1 : null);
  }

  int? limit;
  if (servedEnd != null) {
    final count = servedEnd - servedStart + 1;
    limit = count > 0 ? count : 0;
  } else if (total != null) {
    limit = total - servedStart;
  }
  return RemoteRangeInfo(
    totalLength: total,
    servedStart: servedStart,
    servedEnd: servedEnd,
    limit: limit,
  );
}

/// 把代理侧解析出的 Range 请求写成 `bytes=a-b` 形式。
String formatRangeHeader(int? start, int? end) {
  if (start == null && end == null) return '';
  return 'bytes=${start ?? 0}-${end ?? ''}';
}

/// 按文件名推断 Content-Type。mpv 主要靠内容嗅探，这里只给一个合理默认值，
/// 让 FFmpeg 在探测阶段少走弯路。
String guessContentType(String name) {
  final lower = name.toLowerCase();
  String? type;
  if (lower.endsWith('.mp3')) type = 'audio/mpeg';
  if (lower.endsWith('.flac')) type = 'audio/flac';
  if (lower.endsWith('.wav')) type = 'audio/wav';
  if (lower.endsWith('.m4a') || lower.endsWith('.m4b')) type = 'audio/mp4';
  if (lower.endsWith('.aac')) type = 'audio/aac';
  if (lower.endsWith('.ogg') || lower.endsWith('.oga')) type = 'audio/ogg';
  if (lower.endsWith('.opus')) type = 'audio/ogg';
  if (lower.endsWith('.wma')) type = 'audio/x-ms-wma';
  if (lower.endsWith('.ape')) type = 'audio/x-ape';
  if (lower.endsWith('.aiff') || lower.endsWith('.aif')) type = 'audio/aiff';
  if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) type = 'video/mp4';
  if (lower.endsWith('.flv')) type = 'video/x-flv';
  return type ?? 'application/octet-stream';
}

/// 极简 XML 文本反转义，只覆盖 WebDAV PROPFIND 的 href / displayname 会用到的实体。
String xmlUnescape(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 解码 PROPFIND 的 href，得到用于显示的文件名。
String remoteEntryName(String href, {required bool isDirectory}) {
  var decoded = href.trim();
  try {
    decoded = Uri.decodeComponent(decoded);
  } catch (_) {
    // href 里出现非法百分号编码时保留原值。
  }
  decoded = xmlUnescape(decoded);
  final trimmed = decoded.replaceAll(RegExp(r'/+$'), '');
  final slash = trimmed.lastIndexOf('/');
  final name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  if (name.isNotEmpty) return name;
  return isDirectory ? '目录' : '文件';
}
