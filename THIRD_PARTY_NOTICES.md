# Third-party notices / 第三方声明

本文件记录 Android 移植版运行时携带或构建时下载的主要第三方组件。公开发布 APK 前，需按 `ANDROID_PORT_README.md` 的清单补齐完整许可证文本与源码获取方式。

## 上游 MyuneMusic

- 来源：`https://github.com/xiaobaimc/myune_music`
- 许可证：Apache License 2.0，全文见 `LICENSE`
- 本仓库改动：Android 平台隔离、移除桌面标题栏、隐藏桌面快捷键设置、cargokit/Flutter Gradle 兼容、Android CI runner 生成与签名配置。改动说明见 `ANDROID_PORT_README.md`。

## MiSans 字体

- 文件：`assets/fonts/MiSansVF.ttf`
- 权利方：小米公司；免费商用，版权不转移
- 许可链接：上游 `README.md` 的「字体版权说明」章节

## mpv_audio_kit（Flutter 插件封装）

- 来源：`https://github.com/xiaobaimc/mpv_audio_kit`，锁定 commit `e87688132c2fc1b0960877a59a7b5a535b64917a`
- 上游项目：`https://github.com/ales-drnz/mpv_audio_kit`
- 插件封装许可证：BSD 3-Clause License
- 版权：Copyright (c) 2026, Alessandro Di Ronza

## libmpv / mpv / FFmpeg（预编译原生库）

- 构建时由 `mpv_audio_kit/android/build.gradle.kts` 从 release `libmpv-r13` 下载 `libmpv.so`，按 ABI 放入 APK。
- mpv 项目：`https://github.com/mpv-player/mpv`；FFmpeg：`https://github.com/FFmpeg/FFmpeg`
- 许可状态：mpv 主体为 GPL v2+（部分构建配置可能为 LGPL v2.1+）；FFmpeg 的实际许可证取决于启用的编解码器与构建参数，可能包含 GPL 组件。
- 分发前必须核实 `libmpv-r13` 所含全部原生依赖、编译参数与对应源码，并在发行物中履行 GPL/LGPL 的许可证文本、版权声明、源码提供或书面要约义务。

## 其他 Dart / Flutter 依赖

`pubspec.yaml` 与 `pubspec.lock` 记录了完整依赖树，包括 `provider`、`shared_preferences`、`path_provider`、`file_picker`、`http`、`window_manager`、`hotkey_manager`、`flutter_rust_bridge` 等。每个包的许可证以各自 pub.dev / Git 仓库声明为准；公开发布时可基于 `flutter pub deps` 和 `pubspec.lock` 生成完整 SBOM。
