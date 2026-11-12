// 网络媒体内嵌标签读取器。
//
// 反哺自 XYkadicloud/myune_music v0.9.5-network.1（feat/webdav-ftp-network-drive）：
// 网盘上的音频没有本地路径，为了读标题 / 歌手 / 封面 / 内嵌歌词，按需用
// HTTP Range 只拉文件头，用纯 Dart 解析 FLAC / ID3v2 标签块，结果落盘缓存。
// 与桌面版相比这里去掉了 Rust lofty 兜底与 Drive 依赖，改为完全纯 Dart，
// 更适合 Android TV / 盒子：不写临时音频文件、不依赖平台插件实现。
//
// 三级缓存：内存 -> 磁盘（.json 元数据 + .cover 封面二进制）-> 网络 Range。
// 关键点（fork 修过的坑）：JSON 刻意不序列化封面，所以启动 initialize()
// 必须把同名 .cover 补回内存索引，否则重启后 cached() 永远没有封面。

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../page/playlist/playlist_models.dart';
import 'network_header_tags.dart';
import 'remote_media_registry.dart';

/// 从一个网络音频文件里读到的内嵌标签。
class NetworkTagInfo {
  const NetworkTagInfo({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.trackNumber,
    this.cover,
    this.lyrics,
    this.partial = false,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? durationMs;
  final int? trackNumber;
  final Uint8List? cover;
  final String? lyrics;

  /// 标签来自文件头，时长等字段可能是估算值。
  final bool partial;

  bool get hasCover => cover != null && cover!.isNotEmpty;
  bool get hasLyrics => lyrics != null && lyrics!.trim().isNotEmpty;
  bool get hasTitle => title != null && title!.trim().isNotEmpty;
  bool get hasAny => hasTitle || hasCover || hasLyrics;

  NetworkTagInfo withCover(Uint8List? cover) => NetworkTagInfo(
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    durationMs: durationMs,
    trackNumber: trackNumber,
    cover: cover ?? this.cover,
    lyrics: lyrics,
    partial: partial,
  );

  /// 封面单独写二进制文件，不进 JSON（避免几百 KB 图片撑爆索引文件）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    if (title != null) 'title': title,
    if (artist != null) 'artist': artist,
    if (album != null) 'album': album,
    if (genre != null) 'genre': genre,
    if (durationMs != null && durationMs! > 0) 'durationMs': durationMs,
    if (trackNumber != null) 'trackNumber': trackNumber,
    if (lyrics != null) 'lyrics': lyrics,
    if (partial) 'partial': true,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };

  static NetworkTagInfo? fromJson(Map<String, dynamic> json) {
    int? asInt(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString().trim() ?? '');
    }

    String? asText(Object? value) {
      final text = value?.toString().trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    final info = NetworkTagInfo(
      title: asText(json['title']),
      artist: asText(json['artist']),
      album: asText(json['album']),
      genre: asText(json['genre']),
      durationMs: asInt(json['durationMs']),
      trackNumber: asInt(json['trackNumber']),
      lyrics: asText(json['lyrics']),
      partial: json['partial'] == true,
    );
    return info.hasAny ? info : null;
  }
}

class NetworkTagReader {
  NetworkTagReader._();

  /// 设置里可关闭：关掉后只读文件名，不产生额外流量。
  static bool enabled = true;

  static const int _headBytes = 2 * 1024 * 1024;
  static const int _maxEntries = 1200;
  static const int _maxDiskEntries = 2500;
  static const int _maxDiskBytes = 256 * 1024 * 1024;
  static const int _maxHydratedCoverBytes = 96 * 1024 * 1024;
  static const String _diskDirName = 'tag_cache';
  static const String _jsonSuffix = '.json';
  static const String _coverSuffix = '.cover';

  static final Map<String, NetworkTagInfo> _cache = <String, NetworkTagInfo>{};
  static final Map<String, Future<NetworkTagInfo?>> _inflight =
      <String, Future<NetworkTagInfo?>>{};
  static final Map<String, NetworkTagInfo> _diskIndex =
      <String, NetworkTagInfo>{};
  static Directory? _diskDir;
  static bool _diskReady = false;

  static void _log(String message) =>
      developer.log(message, name: 'NetworkTagReader');

  /// 启动时重建磁盘索引，并把 .cover 二进制补回内存。
  /// 纯本地 IO，不产生任何网络请求；分批并发 + 体积上限控制启动开销。
  static Future<void> initialize() async {
    if (_diskReady) return;
    _diskReady = true;
    final dir = await _diskDirectory();
    if (dir == null) return;
    var loaded = 0;
    var hydrated = 0;
    var hydratedBytes = 0;
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(_jsonSuffix)) {
          files.add(entity);
        }
      }
      const int batchSize = 8;
      for (var i = 0; i < files.length; i += batchSize) {
        final batch = files.skip(i).take(batchSize).toList(growable: false);
        final results = await Future.wait(
          batch.map<Future<MapEntry<String, NetworkTagInfo>?>>(
            (file) => _loadDiskEntry(
              file,
              hydratedBytes < _maxHydratedCoverBytes,
            ),
          ),
        );
        for (final entry in results) {
          if (entry == null) continue;
          _diskIndex[entry.key] = entry.value;
          loaded++;
          final cover = entry.value.cover;
          if (cover != null && cover.isNotEmpty) {
            hydrated++;
            hydratedBytes += cover.length;
          }
        }
      }
      _log('tag cache loaded $loaded, covers hydrated $hydrated');
      unawaited(_trimDisk(dir));
    } catch (error) {
      _log('tag cache load failed: $error');
    }
  }

  static Future<MapEntry<String, NetworkTagInfo>?> _loadDiskEntry(
    File file,
    bool hydrateCover,
  ) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final hash = p.basenameWithoutExtension(file.path);
      var info = NetworkTagInfo.fromJson(Map<String, dynamic>.from(decoded));
      if (hydrateCover) {
        final cover = await _readCoverByHash(hash);
        if (cover != null && cover.isNotEmpty) {
          // 只有封面、没有其它字段时 fromJson 返回 null，仍要保留封面。
          info = (info ?? const NetworkTagInfo()).withCover(cover);
        }
      }
      if (info == null) return null;
      return MapEntry(hash, info);
    } catch (_) {
      return null;
    }
  }

  /// 已读到的标签（同步）。内存未命中时查磁盘索引 —— 重启不重读的关键。
  static NetworkTagInfo? cached(String url) {
    final hit = _cache[url];
    if (hit != null) return hit;
    final key = _stableKey(url);
    if (key == null) return null;
    final disk = _diskIndex[_hash(key)];
    if (disk == null) return null;
    _cache[url] = disk;
    return disk;
  }

  /// 读取指定网络媒体的内嵌标签；读不到返回 null，不抛异常。
  static Future<NetworkTagInfo?> read(String url) {
    if (!enabled || !RemoteMediaRegistry.isNetwork(url)) {
      return Future<NetworkTagInfo?>.value();
    }
    final hit = _cache[url];
    if (hit != null) {
      if (hit.hasCover) return Future<NetworkTagInfo?>.value(hit);
      final pendingCover = _inflight[url];
      if (pendingCover != null) return pendingCover;
      final future = _hydrateCover(url, hit)
          .whenComplete(() => _inflight.remove(url));
      _inflight[url] = future;
      return future;
    }
    final pending = _inflight[url];
    if (pending != null) return pending;
    final future =
        _readUncached(url).whenComplete(() => _inflight.remove(url));
    _inflight[url] = future;
    return future;
  }

  /// 预热：不等待结果，只把请求排进队列。
  static void prefetch(String url) {
    if (!enabled || _cache.containsKey(url) || _inflight.containsKey(url)) {
      return;
    }
    unawaited(read(url));
  }

  /// 批量读取（「一键读取本目录」用），默认 2 并发，返回真正读到的条数。
  static Future<int> prefetchAll(
    List<String> urls, {
    int concurrency = 2,
    void Function(int done, int total)? onProgress,
  }) async {
    final pending = urls
        .where((u) => u.isNotEmpty && RemoteMediaRegistry.isNetwork(u))
        .toList(growable: false);
    if (pending.isEmpty) return 0;
    var cursor = 0;
    var done = 0;
    var found = 0;

    Future<void> worker() async {
      while (cursor < pending.length) {
        final index = cursor++;
        final info = await read(pending[index]);
        if (info != null && info.hasAny) found++;
        done++;
        onProgress?.call(done, pending.length);
      }
    }

    await Future.wait(
      List.generate(
        concurrency.clamp(1, pending.length),
        (_) => worker(),
      ),
    );
    return found;
  }

  static void clear() {
    _cache.clear();
    _diskIndex.clear();
    _inflight.clear();
  }

  /// 把已缓存的标签合并进 Song，并回填注册表（列表 / 播放页 / 收藏都受益）。
  static Song applyToSong(String url, Song song) {
    final info = cached(url);
    if (info == null || !info.hasAny) return song;
    String pick(String? preferred, String fallback) =>
        (preferred != null && preferred.trim().isNotEmpty)
            ? preferred.trim()
            : fallback;
    final merged = Song(
      title: pick(info.title, song.title),
      artist: pick(info.artist, song.artist),
      album: pick(info.album, song.album),
      filePath: song.filePath,
      albumArt: info.hasCover ? info.cover : song.albumArt,
      duration: (info.durationMs != null && info.durationMs! > 0)
          ? Duration(milliseconds: info.durationMs!)
          : song.duration,
      trackNumber: info.trackNumber ?? song.trackNumber,
    );
    RemoteMediaRegistry.register(url, merged);
    if (info.hasCover) {
      RemoteMediaRegistry.registerArtwork(url, info.cover!);
    }
    return merged;
  }

  /// 内嵌歌词（若有），供 LyricsHandler 作为兜底来源之一。
  static String? embeddedLyrics(String url) {
    final info = cached(url);
    return info?.hasLyrics == true ? info!.lyrics : null;
  }

  static Future<NetworkTagInfo?> _readUncached(String url) async {
    // 磁盘索引命中但内存没有：先补封面，避免重复联网。
    final disk = cached(url);
    if (disk != null) {
      if (disk.hasCover) return disk;
      final hydrated = await _hydrateCover(url, disk);
      if (hydrated?.hasCover == true) return hydrated;
    }
    final head = await _fetchHead(url);
    if (head == null || head.isEmpty) return null;
    NetworkHeaderTags? parsed;
    try {
      parsed = NetworkHeaderTagParser.parse(head);
    } catch (error) {
      _log('tag parse failed: $error');
      return null;
    }
    if (parsed == null) return null;
    final info = NetworkTagInfo(
      title: _clean(parsed.title),
      artist: _clean(parsed.artist),
      album: _clean(parsed.album),
      genre: _clean(parsed.genre),
      durationMs: parsed.durationMs,
      trackNumber: parsed.trackNumber,
      cover: parsed.cover,
      lyrics: _clean(parsed.lyrics),
      partial: true,
    );
    // 读不到任何有用信息时不落缓存：一次上游 502 不能把结果记死。
    if (!info.hasAny) return null;
    return _remember(url, info);
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static NetworkTagInfo _remember(String url, NetworkTagInfo info) {
    if (_cache.length >= _maxEntries) _cache.clear();
    _cache[url] = info;
    unawaited(_saveToDisk(url, info));
    return info;
  }

  /// 稳定 key：网络源 id + 媒体 id（取不到时用远端路径）。
  /// 不能用代理 URL：端口会在 18765-18774 间漂移，用它做 key 每次换端口全失效。
  static String? _stableKey(String url) {
    final target = RemoteMediaRegistry.decodeTarget(url);
    if (target == null) return null;
    final source = (target['s'] ?? '').toString().trim();
    final mediaId = (target['id'] ?? '').toString().trim();
    final path = (target['p'] ?? '').toString().trim();
    final identity = mediaId.isNotEmpty ? mediaId : path;
    if (identity.isEmpty) return null;
    return '${source.isEmpty ? '-' : source}|$identity';
  }

  static String _hash(String key) =>
      crypto.sha1.convert(utf8.encode(key)).toString();

  static Future<Directory?> _diskDirectory() async {
    if (_diskDir != null) return _diskDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'starnote', _diskDirName));
      if (!await dir.exists()) await dir.create(recursive: true);
      _diskDir = dir;
      return dir;
    } catch (error) {
      _log('tag cache dir failed: $error');
      return null;
    }
  }

  static Future<void> _saveToDisk(String url, NetworkTagInfo info) async {
    final key = _stableKey(url);
    if (key == null) return;
    final dir = await _diskDirectory();
    if (dir == null) return;
    final hash = _hash(key);
    try {
      await File(p.join(dir.path, '$hash$_jsonSuffix'))
          .writeAsString(jsonEncode(info.toJson()), flush: true);
      if (info.hasCover) {
        await File(p.join(dir.path, '$hash$_coverSuffix'))
            .writeAsBytes(info.cover!, flush: true);
      }
      _diskIndex[hash] = info;
      unawaited(_trimDisk(dir));
    } catch (error) {
      _log('tag cache save failed: $error');
    }
  }

  static Future<Uint8List?> _readCoverByHash(String hash) async {
    final dir = await _diskDirectory();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, '$hash$_coverSuffix'));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<NetworkTagInfo?> _hydrateCover(
    String url,
    NetworkTagInfo base,
  ) async {
    try {
      final key = _stableKey(url);
      if (key == null) return base;
      final cover = await _readCoverByHash(_hash(key));
      if (cover == null) return base;
      final merged = base.withCover(cover);
      _cache[url] = merged;
      return merged;
    } catch (_) {
      return base;
    }
  }

  /// 超过条目数或体积上限时按修改时间删最旧的。
  static Future<void> _trimDisk(Directory dir) async {
    try {
      final files = <File>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          files.add(entity);
          total += await entity.length();
        }
      }
      if (files.length <= _maxDiskEntries && total <= _maxDiskBytes) return;
      files.sort(
        (a, b) => a
            .statSync()
            .modified
            .compareTo(b.statSync().modified),
      );
      var remaining = files.length;
      for (final file in files) {
        if (remaining <= _maxDiskEntries && total <= _maxDiskBytes) break;
        final length = await file.length();
        try {
          await file.delete();
          total -= length;
          remaining--;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 只拉文件头（最多 2 MB），不会为了读封面把几十 MB 无损文件整个下载。
  static Future<Uint8List?> _fetchHead(String url) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Range'] = 'bytes=0-${_headBytes - 1}';
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        return null;
      }
      final buffer = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.stream) {
        if (received + chunk.length > _headBytes) {
          buffer.add(chunk.sublist(0, _headBytes - received));
          received = _headBytes;
          break;
        }
        received += chunk.length;
        buffer.add(chunk);
      }
      return received == 0 ? null : buffer.takeBytes();
    } catch (error) {
      _log('tag head failed: $error');
      return null;
    } finally {
      client.close();
    }
  }
}
