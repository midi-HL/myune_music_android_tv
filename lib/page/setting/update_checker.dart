import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../tv/tv_app_info.dart';

// 定义更新检查结果类型
enum UpdateCheckResultType {
  successUpdateAvailable, // 有可用更新
  successNoUpdate, // 无可用更新
  error, // 检查出错
}

// 更新检查结果
class UpdateCheckResult {
  final UpdateCheckResultType type;
  final UpdateInfo? updateInfo;
  final String? errorMessage;

  UpdateCheckResult.successUpdateAvailable(this.updateInfo)
    : type = UpdateCheckResultType.successUpdateAvailable,
      errorMessage = null;

  UpdateCheckResult.successNoUpdate()
    : type = UpdateCheckResultType.successNoUpdate,
      updateInfo = null,
      errorMessage = null;

  UpdateCheckResult.error(this.errorMessage)
    : type = UpdateCheckResultType.error,
      updateInfo = null;
}

class UpdateChecker {
  /// 检查更新只看**本 TV 改版开源仓库**的 Releases，不看上游 PC 桌面版。
  /// 地址与「关于信息」共用 [TvAppInfo]，避免两处链接分叉。
  static const String _apiUrl = TvAppInfo.releasesApiUrl;

  /// 从 Release tag 中提取可比较的点分版本号。
  /// 约定本仓库 tag 为 `vX.Y.Z`；兼容 `tv-1.0.1` 之类的前缀。
  static String _normalizeVersion(String tag) {
    final match = RegExp(r'\d+(?:\.\d+)+').firstMatch(tag);
    return match?.group(0) ?? tag.trim();
  }

  // 检查是否有新版本
  static Future<UpdateCheckResult> checkForUpdates(
    String currentVersion,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = _normalizeVersion(data['tag_name'].toString());
        final releaseNotes = data['body'] as String? ?? '';
        final htmlUrl = data['html_url'] as String? ?? '';

        // 比较版本号
        if (_isVersionNewer(latestVersion, currentVersion)) {
          final updateInfo = UpdateInfo(
            latestVersion: latestVersion,
            releaseNotes: releaseNotes,
            downloadUrl: htmlUrl,
          );
          return UpdateCheckResult.successUpdateAvailable(updateInfo);
        } else {
          return UpdateCheckResult.successNoUpdate();
        }
      }
      // 如果响应状态码不是200，返回错误
      return UpdateCheckResult.error('服务器响应错误: ${response.statusCode}');
    } catch (e) {
      return UpdateCheckResult.error(e.toString());
    }
  }

  // 比较版本号，判断是否有新版本
  static bool _isVersionNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();

    // 如果解析失败，则认为没有更新
    if (latestParts.any((element) => element == null) ||
        currentParts.any((element) => element == null)) {
      return false;
    }

    // 按照主版本号.次版本号.修订号的顺序比较
    for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
      final latestNum = latestParts[i]!;
      final currentNum = currentParts[i]!;

      if (latestNum > currentNum) {
        return true;
      } else if (latestNum < currentNum) {
        return false;
      }
      // 如果相等，继续比较下一个部分
    }

    // 如果所有部分都相等，或者latest版本号段更少，则认为没有新版本
    return latestParts.length > currentParts.length;
  }
}

class UpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  UpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });
}
