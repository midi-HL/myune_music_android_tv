import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class Song {
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String normalizedPath; // 缓存归一化路径，避免热路径上重复调用 p.normalize
  final Uint8List? albumArt;
  final Duration? duration;
  final int? trackNumber;

  Song({
    required this.title,
    required this.artist,
    this.album = '未知专辑',
    required this.filePath,
    this.albumArt,
    this.duration,
    this.trackNumber,
  }) : normalizedPath = p.normalize(filePath);

  /// 封面写入 JSON，让「收藏 / 历史播放」里的网络媒体在应用重启后
  /// 仍能直接显示封面。设置上限避免 shared_preferences 被超大图撑爆。
  static const int _maxPersistedArtworkBytes = 512 * 1024;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'artist': artist,
      'album': album,
      'filePath': filePath,
      if (duration != null) 'durationMs': duration!.inMilliseconds,
      if (trackNumber != null) 'trackNumber': trackNumber,
      if (albumArt != null &&
          albumArt!.isNotEmpty &&
          albumArt!.length <= _maxPersistedArtworkBytes)
        'albumArt': base64Encode(albumArt!),
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    Uint8List? art;
    final rawArt = json['albumArt'];
    if (rawArt is String && rawArt.isNotEmpty) {
      try {
        art = base64Decode(rawArt);
      } catch (_) {
        art = null;
      }
    }
    final ms = json['durationMs'];
    final durationMs = ms is num ? ms.toInt() : int.tryParse('$ms');
    return Song(
      title: (json['title'] ?? '未知歌曲').toString(),
      artist: (json['artist'] ?? '未知歌手').toString(),
      album: (json['album'] ?? '未知专辑').toString(),
      filePath: (json['filePath'] ?? '').toString(),
      albumArt: art,
      duration: (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : null,
      trackNumber: json['trackNumber'] is num
          ? (json['trackNumber'] as num).toInt()
          : null,
    );
  }
}

// 歌单歌曲元数据缓存
class SongMetadataCacheEntry {
  final String title;
  final String artist;
  final String album;
  final int? durationMs;
  final int modifiedMs;

  const SongMetadataCacheEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.modifiedMs,
    this.durationMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'modifiedMs': modifiedMs,
    };
  }

  factory SongMetadataCacheEntry.fromJson(Map<String, dynamic> json) {
    return SongMetadataCacheEntry(
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      durationMs: json['durationMs'],
      modifiedMs: json['modifiedMs'] ?? 0,
    );
  }
}

class Playlist {
  final String id;
  String name;
  final bool isDefault;
  List<String> songFilePaths;
  List<Song>? songs; // 直接在歌单对象中存储已解析的歌曲

  // 保存当前歌单播放歌曲的索引
  int? currentPlayingIndex;

  // 标识是否为文件夹播放列表
  bool isFolderBased;
  // 存储相关文件夹路径
  List<String> folderPaths;

  Playlist({
    String? id,
    required this.name,
    this.isDefault = false,
    List<String>? songFilePaths,
    this.currentPlayingIndex,
    this.songs,
    this.isFolderBased = false,
    List<String>? folderPaths,
  }) : id = id ?? const Uuid().v4(),
       songFilePaths = songFilePaths ?? [],
       folderPaths = folderPaths ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isDefault': isDefault,
      'currentPlayingIndex': currentPlayingIndex,
      'isFolderBased': isFolderBased,
      'folderPaths': folderPaths,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      isDefault: json['isDefault'] ?? false,
      currentPlayingIndex: json['currentPlayingIndex'],
      isFolderBased: json['isFolderBased'] ?? false,
      folderPaths: json['folderPaths'] != null
          ? List<String>.from(json['folderPaths'])
          : [],
    );
  }
}

class LyricLine {
  final Duration timestamp;
  final List<String> texts;

  final List<List<LyricToken>>? tokens;

  // 为 null 时表示无卡拉OK行
  final List<int>? karaokeTextIndices;

  final bool isInterlude;
  final Duration? interludeDuration;

  LyricLine({
    required this.timestamp,
    required this.texts,
    this.tokens,
    this.karaokeTextIndices,
    this.isInterlude = false,
    this.interludeDuration,
  });

  bool get isKaraoke => tokens != null && tokens!.isNotEmpty;
}

class LyricToken {
  final String text;
  final Duration start;
  final Duration end;

  LyricToken({required this.text, required this.start, required this.end});
}

class SongDetails {
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final Uint8List? albumArt;
  final int? bitrate;
  final int? sampleRate;
  final String filePath;
  final DateTime? created;
  final DateTime? modified;
  final int? year;
  final String? genre;
  final String? albumArtist;

  SongDetails({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.albumArt,
    this.bitrate,
    this.sampleRate,
    required this.filePath,
    this.created,
    this.modified,
    this.year,
    this.genre,
    this.albumArtist,
  });
}

class PlaybackState {
  final String? playlistId;
  final int songIndex;

  PlaybackState({this.playlistId, required this.songIndex});

  Map<String, dynamic> toJson() {
    return {'playlistId': playlistId, 'songIndex': songIndex};
  }

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      playlistId: json['playlistId'],
      songIndex: json['songIndex'],
    );
  }
}
