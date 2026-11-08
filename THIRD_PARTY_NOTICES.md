# Third-party notices / 第三方声明

本文件记录**星音 StarNote（Myune Music Android TV 改版）**运行时携带或构建时下载的主要
第三方组件。本仓库已按 Apache-2.0 公开发行源码；**分发编译后的 APK 之前**，仍须按下述
清单履行许可证文本、版权声明与源码提供义务。

## 上游 MyuneMusic

- 来源：`https://github.com/xiaobaimc/myune_music`，基线版本 `0.9.5`
- 许可证：Apache License 2.0，全文见 `LICENSE`
- 版权：Copyright 2025 xiaobaimc
- 本仓库改动：Android 平台隔离、SAF/content:// 访问、Android TV Leanback 入口与品牌、
  遥控器 / 键盘 / 手柄输入与焦点导航、应用信息与检查更新指向本改版仓库、三 ABI CI 与
  固定 release 签名、网络媒体（WebDAV / FTP / 哔哩哔哩流式播放）、二维码扫码登录、
  电视端软键盘输入。
  改动标注见 `NOTICE`，逐轮记录见 `ANDROID_PORT_HANDOFF.md` / `ANDROID_PORT_README.md`，
  上游原文说明见 `UPSTREAM_README.md`。

## MiSans 字体

- 文件：`assets/fonts/MiSansVF.ttf`
- 权利方：小米公司；免费商用，版权不转移
- 许可链接：见 `UPSTREAM_README.md` 的「字体版权说明」章节

## mpv_audio_kit（Flutter 插件封装）

- 来源：`https://github.com/xiaobaimc/mpv_audio_kit`，锁定 commit `e87688132c2fc1b0960877a59a7b5a535b64917a`
- 上游项目：`https://github.com/ales-drnz/mpv_audio_kit`
- 插件封装许可证：BSD 3-Clause License
- 版权：Copyright (c) 2026, Alessandro Di Ronza

## libmpv / mpv / FFmpeg（预编译原生库）

- 构建时由 `mpv_audio_kit/android/build.gradle.kts` 从 release `libmpv-r13` 下载
  `libmpv.so`，按 ABI 放入 APK。
- mpv 项目：`https://github.com/mpv-player/mpv`；FFmpeg：`https://github.com/FFmpeg/FFmpeg`
- 许可状态：mpv 主体为 GPL v2+（部分构建配置可能为 LGPL v2.1+）；FFmpeg 的实际许可证
  取决于启用的编解码器与构建参数，可能包含 GPL 组件。
- **ABI 限制**：`libmpv-r13` 只发布 `arm64-v8a` / `armeabi-v7a` / `x86_64` 三种预编译库，
  `mpv_audio_kit` 的 `abiFilters` 同样不含 `x86`。本改版因此**不产出 x86（32 位）APK**：
  该架构的包会缺少播放用的原生库，安装后无法出声。
- 分发前必须核实 `libmpv-r13` 所含全部原生依赖、编译参数与对应源码，并在发行物中履行
  GPL/LGPL 的许可证文本、版权声明、源码提供或书面要约义务。若 FFmpeg 启用了 GPL
  编解码器，按 GPL 而非 LGPL 处理整个分发链路。

## qr_flutter / qr（B 站扫码登录二维码）

- `qr_flutter` 4.1.0：来源 `https://github.com/theyakka/qr.flutter`，
  许可证 **BSD 3-Clause License**，版权 `Copyright (c) 2020, Luke Freeman.`
- 传递依赖 `qr`（^3.0.1，解析为支持 Dart 3 的 3.0.x）：来源
  `https://github.com/kevmoo/qr.dart`，许可证 **BSD 3-Clause License**，
  版权 `Copyright 2014, the Dart QR project authors.`
- 用途：在电视端渲染哔哩哔哩登录二维码；纯 Dart 绘制，无平台通道。
- 两个包的完整许可证文本随 pub 缓存分发，二进制发行物中应一并保留其版权声明与许可文本。

## 其他 Dart / Flutter 依赖

`pubspec.yaml` 与 `pubspec.lock` 记录了完整依赖树，包括 `provider`、`shared_preferences`、
`path_provider`、`file_picker`、`http`、`crypto`、`qr_flutter`、`window_manager`、
`hotkey_manager`、`flutter_rust_bridge`、`mesh_gradient` 等。每个包的许可证以各自
pub.dev / Git 仓库声明为准；对外分发时可基于 `flutter pub deps` 和 `pubspec.lock`
生成完整 SBOM。

## 本项目自研的网络媒体实现

WebDAV 客户端、FTP 客户端、本机 HTTP 流代理、哔哩哔哩 Web API 客户端与网络媒体页面
均为本改版自行实现的 Dart 源码（Apache-2.0），仅复用项目已有的 `http`、`crypto`、
`shared_preferences`、`path` 依赖，没有引入额外的第三方网络协议库。播放时访问哔哩哔哩、
WebDAV / FTP 服务器由用户自行配置，本改版不内置任何第三方服务凭据。
