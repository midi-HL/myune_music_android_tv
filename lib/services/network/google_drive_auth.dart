import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_source.dart';

/// Google Drive 只读源的 access_token 管理。
///
/// 认证采用「用户自带 Cloud 凭据 + 一次性 refresh_token」方案，而不是桌面版的
/// loopback 网页登录，也不是设备码流程：
///  * Android TV / 盒子通常没有系统浏览器，`url_launcher` 打不开 OAuth 页；
///  * Google 的「设备码流程」只允许 `drive.file` / `drive.appdata` 等有限 scope，
///    **不支持 `drive.readonly`**，读不到用户已有的整个音乐库；
///  * Google 的 token 端点不允许浏览器直连（CORS），OOB 回调已停用，
///    私网 IP 也不能登记为 redirect_uri，所以纯网页拿不到长期 refresh_token。
///
/// 因此用户在手机 / 电脑上用 `tools/gdrive_auth.py` 完成一次标准 OAuth，
/// 扫码把 client_id / client_secret(可选) / refresh_token 提交给电视本机；
/// 之后电视只用 refresh_token 静默换 access_token，全程只读、凭据不出本机。
class GoogleDriveAuth {
  GoogleDriveAuth._();

  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const Duration _timeout = Duration(seconds: 30);

  static final Map<String, _AccessToken> _cache = <String, _AccessToken>{};
  static final Map<String, Future<String>> _inflight =
      <String, Future<String>>{};

  static void invalidate(String sourceId) {
    _cache.remove(sourceId);
  }

  static Future<Map<String, String>> headers(RemoteSource source) async =>
      <String, String>{
        'Authorization': 'Bearer ${await accessToken(source)}',
        'Accept': 'application/json',
      };

  static Future<String> accessToken(RemoteSource source) async {
    final hit = _cache[source.id];
    if (hit != null && hit.isValid) return hit.value;
    final pending = _inflight[source.id];
    if (pending != null) return pending;
    final future = _refresh(source).whenComplete(
      () => _inflight.remove(source.id),
    );
    _inflight[source.id] = future;
    return future;
  }

  static Future<String> _refresh(RemoteSource source) async {
    final refreshToken = source.refreshToken.trim();
    final clientId = source.clientId.trim();
    if (refreshToken.isEmpty || clientId.isEmpty) {
      throw StateError('Google Drive 凭据不完整，请重新扫码配对');
    }
    final body = <String, String>{
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    };
    final secret = source.clientSecret.trim();
    if (secret.isNotEmpty) body['client_secret'] = secret;

    late http.Response response;
    try {
      response = await http
          .post(Uri.parse(_tokenEndpoint), body: body)
          .timeout(_timeout);
    } catch (error) {
      throw StateError('无法连接 Google 账号服务：$error');
    }
    if (response.statusCode != 200) {
      throw StateError(
        '刷新 Google Drive 授权失败（${response.statusCode}）'
        '${_errorDetail(response.body)}',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw StateError('Google 返回的令牌格式异常');
    final token = (decoded['access_token'] ?? '').toString();
    if (token.isEmpty) throw StateError('Google 未返回 access_token');
    final seconds = decoded['expires_in'] is num
        ? (decoded['expires_in'] as num).toInt()
        : 3600;
    _cache[source.id] = _AccessToken(
      token,
      DateTime.now().add(Duration(seconds: seconds > 120 ? seconds - 60 : 60)),
    );
    return token;
  }

  /// 配对完成后立刻校验一次凭据，并回显当前 Google 账号。
  static Future<String> accountLabel(RemoteSource source) async {
    final token = await accessToken(source);
    final response = await http
        .get(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/about'
            '?fields=user(emailAddress,displayName)',
          ),
          headers: <String, String>{'Authorization': 'Bearer $token'},
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('读取 Google 账号信息失败（${response.statusCode}）');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final user = decoded is Map ? decoded['user'] : null;
    if (user is Map) {
      final email = (user['emailAddress'] ?? '').toString();
      final name = (user['displayName'] ?? '').toString();
      return email.isNotEmpty ? email : name;
    }
    return 'Google 账号';
  }

  static String _errorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = (decoded['error_description'] ?? decoded['error'] ?? '')
            .toString()
            .trim();
        return text.isEmpty ? '' : '：$text';
      }
    } catch (_) {}
    return '';
  }
}

class _AccessToken {
  const _AccessToken(this.value, this.expiresAt);

  final String value;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}
