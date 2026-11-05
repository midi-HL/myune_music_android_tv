import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Android SAF / ContentResolver 的单一适配层。
///
/// 播放端由 mpv_audio_kit 自行把 content:// 转成 fd://；这里负责目录树
/// 选择、持久化权限、递归枚举，以及为只接受文件路径的 Rust 元数据解析器
/// 生成私有缓存副本。
class AndroidContentResolver {
  static const MethodChannel _channel = MethodChannel('myune_music_android/saf');

  static bool isContentUri(String value) => value.startsWith('content://');

  static Future<String?> pickDirectoryTree() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('pickDirectoryTree');
  }

  static Future<List<Map<String, String>>> listAudioFiles(
    String treeUri,
  ) async {
    if (!Platform.isAndroid) return const [];
    final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'listAudioFiles',
      {'treeUri': treeUri},
    );
    return (result ?? const [])
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        )
        .toList();
  }

  static Future<Uint8List?> readBytes(String uri, {int maxBytes = 24 << 20}) async {
    if (!isContentUri(uri)) return null;
    final bytes = await _channel.invokeMethod<Uint8List>('readBytes', {
      'uri': uri,
      'maxBytes': maxBytes,
    });
    return bytes;
  }

  /// 把 content URI 的音频字节缓存到应用私有目录，返回可交给 dart:io / Rust
  /// 的真实文件路径。歌曲 ID 仍保存原始 content URI，保证重启后权限可复用。
  static Future<String> cachePathForRead(String uri) async {
    final cacheDir = Directory(
      p.join((await getTemporaryDirectory()).path, 'content_audio_cache'),
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final hash = uri.hashCode.abs().toRadixString(16);
    final file = File(p.join(cacheDir.path, '$hash.audio'));
    final bytes = await readBytes(uri);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('无法读取 content URI: $uri');
    }
    await file.writeAsBytes(bytes, flush: false);
    return file.path;
  }

  static String displayName(String uri, Map<String, String>? metadata) {
    final name = metadata?['displayName'];
    if (name != null && name.isNotEmpty) return name;
    final last = uri.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => uri);
    final decoded = Uri.tryParse(last)?.pathSegments.lastOrNull ?? last;
    return decoded;
  }
}
