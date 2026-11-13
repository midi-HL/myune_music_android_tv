/// 星音 StarNote（Myune Music Android TV 改版）的项目元信息。
///
/// 「设置 → 常规 → 应用信息与说明 → 关于信息」与「检查更新」共用这一份数据，
/// 保证应用内展示、更新源都指向**本 TV 改版开源仓库**，而不是上游 PC 桌面版。
/// 修改开源信息时只需改这里，避免两处链接再次分叉。
class TvAppInfo {
  TvAppInfo._();

  /// 应用显示名（与 CI 注入的 android:label / TV banner 一致）。
  static const String appName = '星音 StarNote';
  static const String appNameEn = 'StarNote (Myune Music TV Edition)';

  /// 本 TV 改版的版本号。
  /// 与上游桌面版 `appVersion`（0.9.5）分开计数：检查更新比较的是这个值，
  /// 对应本仓库 Release 的 tag 格式 `vX.Y.Z`（例如 v1.0.0）。
  static const String version = '1.6.1';

  /// 本 TV 改版开源仓库：关于页、Issue、检查更新全部指向这里。
  static const String repoOwner = 'midi-HL';
  static const String repoName = 'myune_music_android_tv';
  static const String repoUrl = 'https://github.com/$repoOwner/$repoName';
  static const String issuesUrl = '$repoUrl/issues';
  static const String releasesUrl = '$repoUrl/releases';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const String thirdPartyNoticesUrl =
      '$repoUrl/blob/main/THIRD_PARTY_NOTICES.md';

  /// 上游桌面版仓库（本改版基于它，功能基本一致）。
  static const String upstreamOwner = 'xiaobaimc';
  static const String upstreamRepo = 'myune_music';
  static const String upstreamUrl = 'https://github.com/$upstreamOwner/$upstreamRepo';

  /// 本改版的开发者 / 维护者。
  static const String developer = '辰星 | Edwin 3J | HLmidi';
  static const String developerGithub = 'midi-HL';
  static const String developerGithubUrl = 'https://github.com/$developerGithub';
  static const String developerContact = 'https://t.me/Edwin_hlcx';

  /// 开源协议（与上游一致）。
  static const String license = 'Apache License 2.0';
  static const String licenseUrl = 'https://www.apache.org/licenses/LICENSE-2.0';

  /// 上游原作者的版权年份，用于 applicationLegalese。
  static const String copyrightYear = '2025';
  static const String copyrightYearTv = '2026';
}
