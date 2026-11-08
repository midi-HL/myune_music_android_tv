import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

import '../../tv/tv_app_info.dart';
import 'setting_page.dart';

/// 「设置 → 常规 → 应用信息与说明 → 关于信息」。
///
/// 这里展示的是**本 TV 改版开源仓库**的信息，而不是上游 PC 桌面版：
/// 项目名、版本、开发者、协议、仓库 / Issue 链接全部取自 [TvAppInfo]。
/// 所有 URL 都明文写出，保证在纯遥控器 / 键盘的电视上即使无法点击也能读到地址。
class About extends StatelessWidget {
  const About({super.key});

  // 创建可点击的链接文字
  TextSpan linkTextSpan(BuildContext context, String text, String url) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
        fontSize: 14,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
    );
  }

  // 打开链接
  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  TextSpan _plain(String text) =>
      TextSpan(text: text, style: const TextStyle(fontSize: 14));

  /// 一行「标签：内容」，内容可拼接普通文字与可点击链接。
  Widget _infoLine(BuildContext context, String label, List<TextSpan> value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...value,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('应用信息与说明', style: Theme.of(context).textTheme.titleMedium),
          ElevatedButton.icon(
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: '${TvAppInfo.appName}（TV 改版）',
                applicationVersion: 'v${TvAppInfo.version}',
                applicationIcon: Image.asset(
                  'assets/images/icon/logo.png',
                  width: 48,
                  height: 48,
                ),
                applicationLegalese:
                    '© ${TvAppInfo.copyrightYearTv} ${TvAppInfo.developer} · ${TvAppInfo.license}',
                children: [
                  const SizedBox(height: 8),
                  Text(
                    '${TvAppInfo.appNameEn}：基于 Myune Music 桌面版移植的 '
                    'Android / Android TV 本地音乐播放器。',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),

                  _infoLine(context, '本改版版本', [
                    _plain('v${TvAppInfo.version}'),
                  ]),
                  _infoLine(context, '基于上游', [
                    _plain('Myune Music v$appVersion（Windows / Linux 桌面版，${TvAppInfo.upstreamOwner}）'),
                  ]),
                  _infoLine(context, '开发者 / 维护者', [
                    _plain('${TvAppInfo.developer}（GitHub: ${TvAppInfo.developerGithub}）'),
                  ]),
                  _infoLine(context, '联系方式', [
                    linkTextSpan(context, TvAppInfo.developerContact, TvAppInfo.developerContact),
                  ]),
                  _infoLine(context, '开源协议', [
                    linkTextSpan(context, TvAppInfo.licenseUrl, TvAppInfo.licenseUrl),
                    _plain('（${TvAppInfo.license}）'),
                  ]),
                  _infoLine(context, '本改版开源仓库', [
                    linkTextSpan(context, TvAppInfo.repoUrl, TvAppInfo.repoUrl),
                  ]),
                  _infoLine(context, '上游原仓库', [
                    linkTextSpan(context, TvAppInfo.upstreamUrl, TvAppInfo.upstreamUrl),
                  ]),
                  _infoLine(context, '问题反馈 / 检查更新', [
                    linkTextSpan(context, TvAppInfo.issuesUrl, TvAppInfo.issuesUrl),
                    _plain(' · '),
                    linkTextSpan(context, TvAppInfo.releasesUrl, TvAppInfo.releasesUrl),
                  ]),

                  const SizedBox(height: 8),
                  const Text('电视操作', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                    '方向键按视觉方向移动焦点，OK / 回车 / 空格确认，返回键逐级返回、'
                    '关闭抽屉或退回电视桌面；媒体键与 Xbox / PlayStation 手柄控制播放；'
                    '不接鼠标也能完成全部操作。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text('与上游的关系', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                    '歌曲管理、歌单、歌词、音效 / 均衡器、播放页、主题、音频元数据等核心功能'
                    '与上游桌面版基本一致；本改版主要新增 Android 平台适配、SAF 文件访问与'
                    'Android TV 的遥控器 / 键盘 / 手柄输入，不改变原有音乐播放功能。',
                    style: TextStyle(fontSize: 14),
                  ),

                  const SizedBox(height: 12),
                  const Text(
                    '软件在出现问题时，可能会将相关歌曲信息记录到本地 /log 目录，但不会将其上传',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '软件中的所有联网操作都可以在设置中控制是否开启',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '软件使用小米公司提供的 MiSans 字体，该字体已明确允许免费商用；字体版权归小米公司所有',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '相关许可协议请查阅：',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'MiSans 字体知识产权使用许可协议',
                          'https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '本改版主体代码沿用上游 Apache-2.0，并已标注改动；'
                    '构建产物中的 libmpv / FFmpeg 原生库涉及 GPL / LGPL 义务，'
                    '详见仓库根目录的 THIRD_PARTY_NOTICES.md。',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              );
            },
            icon: const Icon(Icons.info_outline, size: 20),
            label: const Text('关于信息'),
          ),
        ],
      ),
    );
  }
}
