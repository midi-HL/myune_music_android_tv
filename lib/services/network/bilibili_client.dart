import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// B 站流类型。参考 BiliMusic-Desktop：默认只播放 DASH 音频轨（更省流量、
/// 更适合纯音频播放器），也可切换为渐进式视频流（mp4/flv，mpv 无视频输出时
/// 只出声，等价于静音视频）。
enum BiliStreamMode { audio, video }

/// 一条 B 站官方 CC 字幕（自带字幕）的时间轴文本。
/// 独立于歌词模型，避免 services 层反向依赖 page 层。
class BiliSubtitleLine {
  const BiliSubtitleLine(this.start, this.text);

  final Duration start;
  final String text;
}

class BiliVideo {
  const BiliVideo({
    required this.bvid,
    required this.title,
    required this.author,
    required this.cover,
    required this.description,
    required this.durationSeconds,
  });

  final String bvid;
  final String title;
  final String author;
  final String cover;
  final String description;
  final int durationSeconds;

  String get durationLabel => _formatDuration(durationSeconds);
}

class BiliPage {
  const BiliPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.durationSeconds,
  });

  final int cid;
  final int page;
  final String part;
  final int durationSeconds;

  String get durationLabel => _formatDuration(durationSeconds);
}

class BiliVideoDetail {
  const BiliVideoDetail({
    required this.bvid,
    required this.title,
    required this.author,
    required this.cover,
    required this.pages,
  });

  final String bvid;
  final String title;
  final String author;
  final String cover;
  final List<BiliPage> pages;
}

class BiliQrCode {
  const BiliQrCode({required this.url, required this.qrcodeKey});

  /// 需要被编码成二维码展示给手机扫码的内容
  final String url;
  final String qrcodeKey;
}

enum BiliQrState { waiting, scanned, success, expired, error }

class BiliQrPollResult {
  const BiliQrPollResult({required this.state, this.message, this.cookie});

  final BiliQrState state;
  final String? message;
  final String? cookie;
}

/// 登录态持久化。登录只保存 Cookie 字符串，不保存任何账号密码。
class BiliAuthStore {
  BiliAuthStore._();

  static final BiliAuthStore instance = BiliAuthStore._();

  static const String _key = 'starnote.bilibili.cookie.v1';

  String? _cookie;

  String? get cookie => _cookie;
  bool get isLoggedIn => _cookie != null && _cookie!.contains('SESSDATA=');

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    _cookie = (value == null || value.isEmpty) ? null : value;
  }

  Future<void> save(String cookie) async {
    _cookie = cookie;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, cookie);
  }

  Future<void> clear() async {
    _cookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// B 站公开 Web API 客户端。
///
/// 参考 BiliMusic-Desktop 的功能范围：关键词搜索、分页、分 P 展开、单独播放 /
/// 整组加入队列、流式播放、扫码登录、本机代理（代理在 LocalStreamProxy 里）。
/// 身份模型沿用 `bilibili:{bvid}:{cid}`。
class BiliClient {
  BiliClient._();

  static final BiliClient instance = BiliClient._();

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const String _referer = 'https://www.bilibili.com/';

  static const List<int> _mixinKeyEncTab = <int>[
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, //
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52, //
  ];

  final http.Client _client = http.Client();

  String? _buvid3;
  String? _buvid4;
  String? _mixinKey;
  DateTime? _wbiFetchedAt;

  /// 供 CDN 直链请求使用（mpv 访问 B 站 CDN 必须带 Referer / UA / Cookie）。
  Map<String, String> get cdnHeaders => <String, String>{
        'User-Agent': _userAgent,
        'Referer': _referer,
        'Origin': 'https://www.bilibili.com',
        'Cookie': _cookieHeader(),
      };

  /// 供封面图片下载使用（图片 CDN 不带 Cookie，但要带 UA / Referer）。
  Map<String, String> get imageHeaders => <String, String>{
        'User-Agent': _userAgent,
        'Referer': _referer,
      };

  Map<String, String> _apiHeaders() => <String, String>{
        'User-Agent': _userAgent,
        'Referer': _referer,
        'Accept': 'application/json, text/plain, */*',
        'Cookie': _cookieHeader(),
      };

  String _cookieHeader() {
    final parts = <String>[];
    if (_buvid3 != null && _buvid3!.isNotEmpty) parts.add('buvid3=$_buvid3');
    if (_buvid4 != null && _buvid4!.isNotEmpty) parts.add('buvid4=$_buvid4');
    final auth = BiliAuthStore.instance.cookie;
    if (auth != null && auth.isNotEmpty) parts.add(auth);
    return parts.join('; ');
  }

  Future<void> _ensureIdentity() async {
    if (_buvid3 != null && _buvid3!.isNotEmpty) return;
    try {
      final response = await _client
          .get(
            Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
            headers: _apiHeaders(),
          )
          .timeout(const Duration(seconds: 10));
      final data = _decode(response.body)['data'];
      if (data is Map) {
        _buvid3 = data['b_3']?.toString();
        _buvid4 = data['b_4']?.toString();
      }
    } catch (_) {
      // 接口不可达时用一个本机生成的稳定标识兜底。
    }
    _buvid3 ??= 'StarNote${DateTime.now().millisecondsSinceEpoch}infoc';
    _buvid4 ??= '';
  }

  Future<void> _ensureWbi() async {
    final at = _wbiFetchedAt;
    if (_mixinKey != null &&
        at != null &&
        DateTime.now().difference(at).inHours < 6) {
      return;
    }
    await _ensureIdentity();
    final response = await _client
        .get(
          Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
          headers: _apiHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    final data = _decode(response.body)['data'];
    final wbi = data is Map ? data['wbi_img'] : null;
    if (wbi is! Map) {
      throw Exception('无法获取 B 站 WBI 签名密钥，请检查网络');
    }
    final imgKey = _wbiKey(wbi['img_url']?.toString());
    final subKey = _wbiKey(wbi['sub_url']?.toString());
    if (imgKey == null || subKey == null) {
      throw Exception('B 站 WBI 密钥格式异常');
    }
    final raw = imgKey + subKey;
    final buffer = StringBuffer();
    for (final index in _mixinKeyEncTab) {
      if (index < raw.length) buffer.write(raw[index]);
    }
    final key = buffer.toString();
    if (key.length < 32) {
      throw Exception('B 站 WBI 密钥长度异常');
    }
    _mixinKey = key.substring(0, 32);
    _wbiFetchedAt = DateTime.now();
  }

  String? _wbiKey(String? url) {
    if (url == null || url.isEmpty) return null;
    final name = url.split('/').last.split('?').first;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Map<String, String> _sign(Map<String, String> params) {
    final key = _mixinKey ?? '';
    final signed = <String, String>{
      ...params,
      'wts': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    };
    final keys = signed.keys.toList()..sort();
    final query = keys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}='
              '${Uri.encodeQueryComponent(_wbiFilter(signed[k]!))}',
        )
        .join('&');
    return <String, String>{
      ...signed,
      'w_rid': crypto.md5.convert(utf8.encode(query + key)).toString(),
    };
  }

  String _wbiFilter(String value) =>
      value.replaceAll(RegExp(r"['!()*]"), '');

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final response = await _client
        .get(uri, headers: _apiHeaders())
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('B 站接口 HTTP ${response.statusCode}');
    }
    return _decode(response.body);
  }

  /// B 站「音乐」主分区 rid。推荐固定只取该分区，不再使用全站 rcmd / 全站热门，
  /// 否则会出现选举、数码、美食等与音乐无关的内容。
  static const String _musicRid = '3';

  /// 音乐主分区 (3) 及其所有子分区 tid。用于二次兜底过滤，
  /// 防止个别接口返回的列表里混入其它分区稿件。
  static const Set<int> _musicTids = <int>{
    3, // 音乐（主分区）
    15, // MV
    28, // 原创音乐
    29, // 音乐现场
    30, // VOCALOID·UTAU
    31, // 翻唱
    59, // 演奏
    130, // 音乐综合
    193, // 音乐教学
    194, // 乐评盘点
    195, // 音乐资讯
  };

  /// 「推荐」只取音乐区。主用音乐区最新投稿（可分页），按序回退到音乐区
  /// 排行榜与音乐区动态，三层都在音乐分区内，不会退化为全站内容。
  Future<List<BiliVideo>> recommend({int page = 1}) async {
    await _ensureIdentity();
    // 1) 音乐区最新投稿：最贴合「推荐」语义，且支持翻页。
    try {
      final result = await _getJson(
        Uri.https(
          'api.bilibili.com',
          '/x/web-interface/newlist',
          <String, String>{
            'rid': _musicRid,
            'pn': page.toString(),
            'ps': '20',
          },
        ),
      );
      if (result['code'] == 0) {
        final data = result['data'];
        final videos = _parseVideoList(data is Map ? data['archives'] : null);
        if (videos.isNotEmpty) return videos;
      }
    } catch (_) {
      // 继续回退。
    }
    // 2) 音乐区排行榜（无分页概念，作为稳定兜底）。
    try {
      final result = await _getJson(
        Uri.https(
          'api.bilibili.com',
          '/x/web-interface/ranking/v2',
          <String, String>{'rid': _musicRid, 'type': 'all'},
        ),
      );
      if (result['code'] == 0) {
        final data = result['data'];
        final videos = _parseVideoList(data is Map ? data['list'] : null);
        if (videos.isNotEmpty) return videos;
      }
    } catch (_) {
      // 继续回退。
    }
    // 3) 音乐区动态（WBI 签名端点）。
    try {
      await _ensureWbi();
      final params = <String, String>{
        'rid': _musicRid,
        'pn': page.toString(),
        'ps': '20',
      };
      final result = await _getJson(
        Uri.https(
          'api.bilibili.com',
          '/x/web-interface/wbi/dynamic/region',
          _sign(params),
        ),
      );
      if (result['code'] == 0) {
        final data = result['data'];
        final videos = _parseVideoList(data is Map ? data['archives'] : null);
        if (videos.isNotEmpty) return videos;
      }
    } catch (_) {
      // 全部端点失败时返回空列表，由 UI 显示可重试的提示。
    }
    return <BiliVideo>[];
  }

  /// 把推荐 / 排行榜 / 分区动态的 JSON 列表统一成 [BiliVideo]。
  /// 带 tid 的条目必须是音乐分区，否则丢弃；不带 tid 的（排行榜）保留。
  List<BiliVideo> _parseVideoList(Object? raw) {
    if (raw is! List) return <BiliVideo>[];
    final videos = <BiliVideo>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final tidRaw = item['tid'];
      if (tidRaw != null) {
        final tid = tidRaw is num
            ? tidRaw.toInt()
            : int.tryParse(tidRaw.toString().trim());
        if (tid != null && !_musicTids.contains(tid)) continue;
      }
      final bvid = (item['bvid'] ?? '').toString();
      if (bvid.isEmpty) continue;
      final owner = item['owner'];
      final author = owner is Map
          ? _cleanHtml((owner['name'] ?? '').toString())
          : _cleanHtml((item['author'] ?? '').toString());
      final coverRaw = (item['pic'] ?? item['cover'] ?? '').toString();
      videos.add(
        BiliVideo(
          bvid: bvid,
          title: _cleanHtml((item['title'] ?? '').toString()),
          author: author,
          cover: _normalizeCover(coverRaw),
          description: _cleanHtml((item['desc'] ?? item['description'] ?? '')
              .toString()),
          durationSeconds: _parseDuration(
            item['duration'] ?? item['durationSeconds'],
          ),
        ),
      );
    }
    return videos;
  }

  /// 关键词搜索视频。WBI 端点失败时自动回退到旧端点。
  Future<List<BiliVideo>> search(String keyword, {int page = 1}) async {
    await _ensureIdentity();
    final params = <String, String>{
      'search_type': 'video',
      'keyword': keyword,
      'page': page.toString(),
      'page_size': '20',
    };
    Map<String, dynamic> result;
    try {
      await _ensureWbi();
      result = await _getJson(
        Uri.https(
          'api.bilibili.com',
          '/x/web-interface/wbi/search/type',
          _sign(params),
        ),
      );
      if (result['code'] != 0) throw Exception('WBI 搜索被拒绝');
    } catch (_) {
      result = await _getJson(
        Uri.https('api.bilibili.com', '/x/web-interface/search/type', params),
      );
    }
    if (result['code'] != 0) {
      throw Exception(
        'B 站搜索失败（${result['code']}）：${result['message'] ?? '未知错误'}',
      );
    }
    final data = result['data'];
    final list = data is Map ? data['result'] : null;
    if (list is! List) return <BiliVideo>[];
    return list.whereType<Map<String, dynamic>>().map((item) {
      final bvid = (item['bvid'] ?? '').toString();
      final cover = _normalizeCover((item['pic'] ?? '').toString());
      return BiliVideo(
        bvid: bvid,
        title: _cleanHtml((item['title'] ?? '').toString()),
        author: _cleanHtml((item['author'] ?? '').toString()),
        cover: cover,
        description: _cleanHtml((item['description'] ?? '').toString()),
        durationSeconds: _parseDuration(item['duration']),
      );
    }).where((v) => v.bvid.isNotEmpty).toList();
  }

  /// 把 BV 号 / av 号转换成 B 站接口认识的参数。
  /// `av123` 必须走 aid=123，直接当 bvid 传会让接口返回 -404。
  Map<String, String> _videoParams(String bvid) {
    if (RegExp(r'^av\d+$', caseSensitive: false).hasMatch(bvid.trim())) {
      return <String, String>{'aid': bvid.trim().substring(2)};
    }
    return <String, String>{'bvid': bvid};
  }

  /// 取视频详情与全部分 P。
  Future<BiliVideoDetail> view(String bvid) async {
    await _ensureIdentity();
    final result = await _getJson(
      Uri.https(
        'api.bilibili.com',
        '/x/web-interface/view',
        _videoParams(bvid),
      ),
    );
    if (result['code'] != 0) {
      throw Exception(
        '读取视频信息失败（${result['code']}）：${result['message'] ?? ''}',
      );
    }
    final data = result['data'];
    if (data is! Map) throw Exception('视频信息为空');
    final rawPages = data['pages'];
    final pages = <BiliPage>[];
    if (rawPages is List) {
      for (final item in rawPages) {
        if (item is! Map) continue;
        pages.add(
          BiliPage(
            cid: (item['cid'] as num?)?.toInt() ?? 0,
            page: (item['page'] as num?)?.toInt() ?? pages.length + 1,
            part: _cleanHtml((item['part'] ?? '').toString()),
            durationSeconds: (item['duration'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    if (pages.isEmpty) {
      pages.add(
        BiliPage(
          cid: (data['cid'] as num?)?.toInt() ?? 0,
          page: 1,
          part: _cleanHtml((data['title'] ?? '视频').toString()),
          durationSeconds: (data['duration'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return BiliVideoDetail(
      bvid: bvid,
      title: _cleanHtml((data['title'] ?? bvid).toString()),
      author: data['owner'] is Map
          ? _cleanHtml((data['owner']['name'] ?? '').toString())
          : '',
      cover: _normalizeCover((data['pic'] ?? '').toString()),
      pages: pages.where((p) => p.cid > 0).toList(),
    );
  }

  /// 从用户输入里解析 BV 号：支持完整链接、裸 BV 号与 av 号（av 号经 view 接口
  /// 也能识别，但这里统一转成 bvid 参数交给 B 站接口处理）。
  static String? extractBvid(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final bv = RegExp(r'(BV[0-9A-Za-z]{10})').firstMatch(text);
    if (bv != null) return bv.group(1);
    final av = RegExp(r'\bav(\d+)\b', caseSensitive: false).firstMatch(text);
    if (av != null) return 'av${av.group(1)}';
    if (RegExp(r'^BV[0-9A-Za-z]+$').hasMatch(text)) return text;
    return null;
  }

  /// 解析可直接交给 mpv 的 CDN 直链。返回的 URL 由本机代理转发，
  /// 代理会补上 Referer / UA / Cookie 并透传 Range。
  Future<String> streamUrl({
    required String bvid,
    required int cid,
    required BiliStreamMode mode,
  }) async {
    await _ensureIdentity();
    final params = <String, String>{
      ..._videoParams(bvid),
      'cid': cid.toString(),
      'qn': mode == BiliStreamMode.audio ? '16' : '64',
      'fnval': mode == BiliStreamMode.audio ? '16' : '0',
      'fnver': '0',
      'fourk': '0',
    };
    Map<String, dynamic> result;
    try {
      await _ensureWbi();
      result = await _getJson(
        Uri.https(
          'api.bilibili.com',
          '/x/player/wbi/playurl',
          _sign(params),
        ),
      );
      if (result['code'] != 0) throw Exception('WBI playurl 被拒绝');
    } catch (_) {
      result = await _getJson(
        Uri.https('api.bilibili.com', '/x/player/playurl', params),
      );
    }
    if (result['code'] != 0) {
      throw Exception(
        '获取播放地址失败（${result['code']}）：${result['message'] ?? ''}',
      );
    }
    final data = result['data'];
    if (data is! Map) throw Exception('播放地址为空');

    if (mode == BiliStreamMode.audio) {
      final dash = data['dash'];
      final audio = dash is Map ? dash['audio'] : null;
      if (audio is List && audio.isNotEmpty && audio.first is Map) {
        final url = _pickUrl(audio.first as Map);
        if (url != null) return url;
      }
    }
    final durl = data['durl'];
    if (durl is List && durl.isNotEmpty && durl.first is Map) {
      final url = _pickUrl(durl.first as Map);
      if (url != null) return url;
    }
    throw Exception('B 站未返回可播放的流地址（可能需要登录或该视频受限）');
  }

  String? _pickUrl(Map item) {
    final primary = (item['url'] ?? item['baseUrl'] ?? item['base_url'] ?? '')
        .toString();
    if (primary.isNotEmpty) return primary;
    final backups =
        item['backup_url'] ?? item['backupUrl'] ?? item['backupUrlList'];
    if (backups is List && backups.isNotEmpty) {
      final first = backups.first.toString();
      if (first.isNotEmpty) return first;
    }
    return null;
  }

  // ===== B 站官方 CC 字幕（自带字幕 / 歌词） =====

  /// 读取视频的官方字幕轨，优先中文字幕（含 AI 中文字幕）。
  ///
  /// `/x/player/v2` 返回 `data.subtitle.subtitles[]`，其中 `subtitle_url`
  /// 指向一份 JSON：`{"body":[{"from":0.0,"to":2.0,"content":"..."}]}`。
  /// 播放器是纯音频链路，无法解码视频内嵌字幕；把字幕按时间轴转成歌词行，
  /// 就能在「歌词数据区域」自然显示带字幕视频的文本。
  Future<List<BiliSubtitleLine>> fetchSubtitles({
    required String bvid,
    required int cid,
  }) async {
    await _ensureIdentity();
    final params = <String, String>{
      ..._videoParams(bvid),
      'cid': cid.toString(),
    };
    Map<String, dynamic> result;
    try {
      result = await _getJson(
        Uri.https('api.bilibili.com', '/x/player/v2', params),
      );
    } catch (_) {
      return <BiliSubtitleLine>[];
    }
    if (result['code'] != 0) return <BiliSubtitleLine>[];
    final data = result['data'];
    final subtitle = data is Map ? data['subtitle'] : null;
    final list = subtitle is Map ? subtitle['subtitles'] : null;
    if (list is! List || list.isEmpty) return <BiliSubtitleLine>[];

    Map<dynamic, dynamic>? picked;
    for (final item in list) {
      if (item is! Map) continue;
      final lan = (item['lan'] ?? '').toString().toLowerCase();
      if (lan.contains('zh') || lan.contains('cn') || lan.contains('ai-zh')) {
        picked = item;
        break;
      }
    }
    if (picked == null) {
      for (final item in list) {
        if (item is Map) {
          picked = item;
          break;
        }
      }
    }
    if (picked == null) return <BiliSubtitleLine>[];
    var url = (picked['subtitle_url'] ?? '').toString().trim();
    if (url.isEmpty) return <BiliSubtitleLine>[];
    if (url.startsWith('//')) url = 'https:$url';

    try {
      final response = await _client
          .get(Uri.parse(url), headers: _apiHeaders())
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return <BiliSubtitleLine>[];
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final body = decoded is Map ? decoded['body'] : null;
      if (body is! List) return <BiliSubtitleLine>[];
      final lines = <BiliSubtitleLine>[];
      for (final cue in body) {
        if (cue is! Map) continue;
        final text = (cue['content'] ?? '')
            .toString()
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (text.isEmpty) continue;
        final from = cue['from'];
        final seconds = from is num
            ? from.toDouble()
            : (double.tryParse(from?.toString().trim() ?? '') ?? 0.0);
        lines.add(
          BiliSubtitleLine(
            Duration(milliseconds: (seconds * 1000).round()),
            text,
          ),
        );
      }
      lines.sort((a, b) => a.start.compareTo(b.start));
      return lines;
    } catch (_) {
      return <BiliSubtitleLine>[];
    }
  }

  // ===== 二维码扫码登录 =====

  Future<BiliQrCode> generateQrCode() async {
    await _ensureIdentity();
    final result = await _getJson(
      Uri.https(
        'passport.bilibili.com',
        '/x/passport-login/web/qrcode/generate',
        <String, String>{'source': 'main-fe-header'},
      ),
    );
    if (result['code'] != 0) {
      throw Exception('生成登录二维码失败：${result['message'] ?? ''}');
    }
    final data = result['data'];
    if (data is! Map) throw Exception('二维码数据为空');
    final url = (data['url'] ?? '').toString();
    final key = (data['qrcode_key'] ?? '').toString();
    if (url.isEmpty || key.isEmpty) throw Exception('二维码数据不完整');
    return BiliQrCode(url: url, qrcodeKey: key);
  }

  Future<BiliQrPollResult> pollQrCode(String qrcodeKey) async {
    final response = await _client
        .get(
          Uri.https(
            'passport.bilibili.com',
            '/x/passport-login/web/qrcode/poll',
            <String, String>{'qrcode_key': qrcodeKey},
          ),
          headers: _apiHeaders(),
        )
        .timeout(const Duration(seconds: 12));
    final result = _decode(response.body);
    if (result['code'] != 0) {
      return BiliQrPollResult(
        state: BiliQrState.error,
        message: result['message']?.toString(),
      );
    }
    final data = result['data'];
    final status = data is Map
        ? (data['code'] as num?)?.toInt() ?? -1
        : -1;
    switch (status) {
      case 0:
        final cookie = _extractCookie(data is Map ? data : null, response);
        if (cookie == null) {
          return const BiliQrPollResult(
            state: BiliQrState.error,
            message: '登录成功但未能读取 Cookie，请重试',
          );
        }
        await BiliAuthStore.instance.save(cookie);
        return BiliQrPollResult(state: BiliQrState.success, cookie: cookie);
      case 86038:
        return const BiliQrPollResult(
          state: BiliQrState.expired,
          message: '二维码已过期',
        );
      case 86090:
        return const BiliQrPollResult(
          state: BiliQrState.scanned,
          message: '已扫码，请在手机上确认登录',
        );
      case 86101:
        return const BiliQrPollResult(
          state: BiliQrState.waiting,
          message: '等待扫码…',
        );
      default:
        return BiliQrPollResult(
          state: BiliQrState.error,
          message: data is Map ? data['message']?.toString() : null,
        );
    }
  }

  String? _extractCookie(Map<dynamic, dynamic>? data, http.Response response) {
    final parts = <String>[];
    final seen = <String>{};
    void add(String key, String value) {
      if (key.isEmpty || value.isEmpty || !seen.add(key)) return;
      parts.add('$key=$value');
    }

    // Web 扫码登录成功后，data.url 会带上登录态参数。
    if (data != null) {
      final url = (data['url'] ?? '').toString();
      if (url.isNotEmpty) {
        final query = Uri.tryParse(url)?.queryParameters;
        if (query != null) {
          for (final key in const <String>[
            'SESSDATA',
            'bili_jct',
            'DedeUserID',
            'DedeUserID__ckMd5',
            'sid',
          ]) {
            final value = query[key];
            if (value != null) add(key, value);
          }
        }
      }
    }

    // 兜底：从 set-cookie 响应头提取。
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      for (final match in RegExp(
        r'(SESSDATA|bili_jct|DedeUserID|DedeUserID__ckMd5|sid)=([^;,\s]+)',
      ).allMatches(setCookie)) {
        add(match.group(1)!, match.group(2)!);
      }
    }
    if (parts.isEmpty || !parts.any((p) => p.startsWith('SESSDATA='))) {
      return null;
    }
    return parts.join('; ');
  }

  String _normalizeCover(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http')) return url;
    return 'https://$url';
  }

  String _cleanHtml(String value) {
    var text = value.replaceAll(RegExp(r'<[^>]*>'), '');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    return text.trim();
  }

  int _parseDuration(Object? value) {
    if (value is num) return value.toInt();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0;
    if (!text.contains(':')) return int.tryParse(text) ?? 0;
    final parts = text.split(':');
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + (int.tryParse(part.trim()) ?? 0);
    }
    return seconds;
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '--:--';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(secs)}'
      : '${two(minutes)}:${two(secs)}';
}
