# 🎵 星音 StarNote · Myune Music Android TV 改版

**[English](README.en.md) · 简体中文**

> 一个基于 [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) 移植改版的
> **Android / Android TV 本地音乐播放器**。纯遥控器、纯键盘、纯手柄都能完整操作；
> 音乐播放功能与上游桌面版基本一致。

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47.5-blue?logo=flutter" alt="Flutter 3.47.5" />
  <img src="https://img.shields.io/badge/Android%20TV-Leanback-brightgreen" alt="Android TV" />
  <img src="https://img.shields.io/badge/ABI-arm64%20%7C%20armv7%20%7C%20x86__64-orange" alt="ABI" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey" alt="Apache 2.0" /></a>
</p>

---

## 目录

1. [这是什么](#1-这是什么)
2. [基于什么源仓库](#2-基于什么源仓库)
3. [与上游基本一致的说明](#3-与上游基本一致的说明)
4. [开发者与维护者](#4-开发者与维护者)
5. [电视 / 遥控器 / 键盘 / 手柄操作](#5-电视--遥控器--键盘--手柄操作)
6. [做了哪些适配](#6-做了哪些适配)
7. [下载与 ABI](#7-下载与-abi)
8. [检查更新](#8-检查更新)
9. [从源码构建](#9-从源码构建)
10. [开源协议](#10-开源协议)
11. [反馈与贡献](#11-反馈与贡献)
12. [回滚](#12-回滚)
13. [致谢](#13-致谢)

---

## 1. 这是什么

**星音 StarNote**（英文 *StarNote / Myune Music TV Edition*）是上游桌面音乐播放器
[Myune Music](https://github.com/xiaobaimc/myune_music) 的 **Android / Android TV 移植改版**，
由本仓库独立开源维护。应用显示名「星音 StarNote」由 CI 注入 `android:label`，手机桌面与
Android TV 启动器共用；TV 桌面另有 320×180 横幅。

**同一个 APK 自动识别电视**：设备被判定为 TV 时才启用电视输入与焦点逻辑；在普通手机 /
平板上，这些新增代码路径全部不生效，手机端的沉浸式、缩放、SAF 行为保持原样。

> 本改版不是上游官方版本，与上游作者无隶属关系。上游版权与 Apache-2.0 声明完整保留。

## 2. 基于什么源仓库

| 项目 | 内容 |
| --- | --- |
| 上游源仓库 | [github.com/xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) |
| 上游作者 | `xiaobaimc` |
| 上游定位 | Flutter 3.47.5 / Dart 3.10 编写的 **Windows / Linux 桌面**本地音乐播放器（原本没有 `android/` 目录） |
| 上游基线版本 | `0.9.5` |
| 上游协议 | **Apache License 2.0** |
| 上游原文说明 | [UPSTREAM_README.md](UPSTREAM_README.md)（原样保留） |
| **本改版开源仓库** | [github.com/midi-HL/myune_music_android_tv](https://github.com/midi-HL/myune_music_android_tv) |
| 本改版协议 | **Apache License 2.0**（与上游一致） |
| 本改版版本 | `1.0.0`（见 `lib/tv/tv_app_info.dart`） |

本仓库**保留了上游完整提交历史**（未 squash、未改写），所有改版内容以新增提交与 tag 形式记录，
可随时回滚。改动清单见 [NOTICE](NOTICE) 与 [ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md)。

## 3. 与上游基本一致的说明

本改版的目标是「把桌面版搬到 Android TV」，**不是重写播放器**。以下核心功能沿用上游代码，
与桌面版基本一致：

- 歌曲管理：文件夹歌单、手动歌单，自动按歌手 / 专辑分类
- 歌词：内嵌歌词、外置 `lrc / yrc / qrc / krc`、逐字歌词、网络歌词源、翻译与罗马音多行显示、歌词显示设置
- 播放：`mpv_audio_kit` + libmpv、音效 / 均衡器、ReplayGain、播放模式、进度与跳转
- 播放页：逐字歌词、动态 `MeshGradient` 背景、封面高斯模糊、播放列表抽屉
- 外观：Material 3、主题配色、自定义字体与背景、页面可见性设置
- 元数据：Rust + `flutter_rust_bridge` / `cargokit` 读取封面、时长、内嵌元数据
- 其它：模糊 / 拼音 / 首拼搜索、本地播放统计、音频分析页
- **桌面版 Windows / Linux 的构建与功能不受本改版影响**

**本改版新增 / 差异仅在平台适配层与输入层**（详见第 6 节）：Android 平台隔离、SAF 文件访问、
TV 桌面入口与品牌、遥控器 / 键盘 / 手柄输入、焦点导航、TV 控件可达性，以及指向本仓库的
关于信息与检查更新。上游的功能逻辑没有被替换。

## 4. 开发者与维护者

| 项目 | 内容 |
| --- | --- |
| 本改版开发者 / 维护者 | **辰星 \| Edwin 3J \| HLmidi** |
| GitHub | [github.com/midi-HL](https://github.com/midi-HL) |
| 联系方式 | [t.me/Edwin_hlcx](https://t.me/Edwin_hlcx) |
| 上游原作者 | `xiaobaimc`（原仓库版权与许可归其所有） |

应用内「设置 → 常规 → 应用信息与说明 → 关于信息」展示的也是这份信息，取自
`lib/tv/tv_app_info.dart`，不再显示 PC 原版的应用信息。

## 5. 电视 / 遥控器 / 键盘 / 手柄操作

设计原则：**不接鼠标、不用触屏，纯遥控器即可完成导入音乐、点歌、播放控制、歌词设置、
音效、播放列表与全部设置项**。

| 输入 | 行为 |
| --- | --- |
| 方向键 ↑ ↓ ← → | 按**视觉方向**把焦点移到对应半平面里最近的可聚焦控件；不会反直觉地跳到另一侧 |
| OK / 回车 / 空格 | 激活当前焦点控件 |
| 返回键 / Esc / 手柄 B（○） | 逐级关闭浮层 → 抽屉 → 播放页 → 回到电视桌面；「正在播放」抽屉的返回等同 ✕ 关闭 |
| 媒体键（播放/暂停、上一首/下一首、快进/快退） | 直接控制播放；没有媒体键的遥控器用焦点控件同样能完成 |
| Xbox / PlayStation 手柄 | 按**物理位置**统一映射 A/✕ 确认、B/○ 返回、肩键 / 扳机控制切歌与快进快退 |
| 设置 → 电视与输入 → 手柄图标 | 切换显示「自动识别 / Xbox / PlayStation」，仅影响图标，不影响功能 |
| 设置 → 电视与输入 → 按键学习 | 记录厂商私有 keyCode 并逐项绑定到逻辑动作，兼容非标准遥控器 |
| 音量 | 音量图标展开**竖向**音量条，↑/↓ 调节、返回键关闭；不显示文字提示 |
| 进度条 | 不参与方向键焦点链（避免 Slider 吞掉四向键），可用鼠标 / 触控拖动，或用媒体键 / 手柄扳机快进快退 |
| 音效 / 均衡器滑块 | 横向滑块 ←/→ 调值、↑/↓ 离开；竖向频段滑块 ↑/↓ 调值、←/→ 离开 |
| 焦点高亮 | 原生式半透明主色背景，**不画描边框、不叠加双重亮框** |

## 6. 做了哪些适配

1. **Android 平台隔离**：`window_manager` / `tray_manager` / `hotkey_manager` /
   `flutter_single_instance` 仅在桌面初始化；去窗口标题栏、隐藏桌面快捷键设置、沉浸式全屏、
   应用内缩放、横屏双栏；保留 `MpvAudioKit` 与 Rust 初始化。
2. **文件访问 SAF**：原生 `ci/MainActivity.kt` 提供 `ACTION_OPEN_DOCUMENT_TREE`、持久化 URI
   权限、递归音频枚举与字节读取；Dart 侧 `android_content_resolver.dart` 把 `content://`
   转成可播放的 `fd://` 与可解析的私有缓存文件。
3. **TV 桌面入口**：幂等注入 `LEANBACK_LAUNCHER`、`android.software.leanback` /
   touchscreen / gamepad（均 `required="false"`）、`android:banner`，生成 320×180 横幅与
   5 个密度品牌图标；应用名「星音 StarNote」。
4. **输入层**：`ci/MainActivity.kt` 用 `dispatchKeyEvent()` + `EventChannel` 广播原始按键且
   **不吞键**；`lib/tv/` 下实现 TV 判定、键值归一化、逻辑动作、返回与抽屉、设置页、手柄图标、
   输入分发与持久化。
5. **焦点导航**：冷启动 / 路由切换 / 抽屉打开后自动建立焦点；基于 `RenderBox` 全局
   `Rect.center` 的严格几何方向查找，允许主界面跨 FocusScope 按视觉方向移动；模态浮层内锁焦；
   焦点落到被裁切选项时用 `Scrollable.ensureVisible()` 自动滚动露出；
   `FocusHighlightStrategy.alwaysTraditional` 让原生焦点态正常显示。
6. **控件可达性**：进度条 `TvPointerOnlySlider`、设置项 `TvAdjustableSlider`、音量竖条、
   自建可聚焦 TV 侧边栏、播放页控制排补回「歌词显示设置」按钮、抽屉返回键等同 ✕。
7. **应用信息**：关于页与检查更新指向本改版仓库；`TvAppInfo` 统一维护项目元信息。
8. **CI**：GitHub Actions 生成 Android runner、注入 TV Manifest 与品牌资源，
   分别构建 3 个单 ABI release APK（arm64-v8a / armeabi-v7a / x86_64）。

完整的逐轮修复记录与回滚锚点见 [ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md)。

## 7. 下载与 ABI

| ABI | 适用设备 | 产物 |
| --- | --- | --- |
| `arm64-v8a` | 绝大多数现代 Android TV、电视盒子、手机 | `myune-music-arm64-v8a-release.apk` |
| `armeabi-v7a` | 老款 32 位 ARM 设备 | `myune-music-armeabi-v7a-release.apk` |
| `x86_64`（AMD64 / 64 位 x86） | x86 64 位电视盒子、Android 模拟器 | `myune-music-x86_64-release.apk` |

📦 下载：[GitHub Releases](https://github.com/midi-HL/myune_music_android_tv/releases)

> **为什么不提供 x86（32 位）APK**：上游 `libmpv-r13` 只发布 `arm64-v8a` / `armeabi-v7a` /
> `x86_64` 三种预编译 `libmpv.so`，`mpv_audio_kit` 的 `abiFilters` 也不包含 `x86`。
> 强行构建的 x86 32 位包会缺少播放用的原生库，安装后无法出声，因此本改版**不产出**该架构，
> 也不交付明知不可用的包。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

安装：用文件管理器或 `adb install` 安装对应 ABI 的 APK。当前为 **debug 签名**，覆盖安装若提示
签名不匹配，请先卸载旧版；不同 ABI 的 debug 证书也不相同。

## 8. 检查更新

应用内「设置 → 常规 → 检查更新」与启动静默检查都请求：

```
https://api.github.com/repos/midi-HL/myune_music_android_tv/releases/latest
```

**不会再检查上游 PC 桌面版** `xiaobaimc/myune_music`。Release tag 约定为 `vX.Y.Z`
（例如 `v1.0.0`），与 `lib/tv/tv_app_info.dart` 中 `TvAppInfo.version` 对应；关于页里的
仓库 / Issue / Releases 链接也指向本仓库。

## 9. 从源码构建

本机**不需要** Flutter / Rust / NDK：编译与 APK 校验全部由
[`.github/workflows/build_android.yml`](.github/workflows/build_android.yml) 在 GitHub Actions 完成。

工具链：Flutter `3.47.5` / Dart 3.10、Rust stable、JDK 21、Android SDK 36、
NDK `28.2.13676358`、CMake `3.22.1`。

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64   # 或 android-arm / android-x64
```

上游没有 `android/` 目录，CI 会用 `flutter create --platforms=android` 生成 runner，
再注入 `ci/MainActivity.kt`、TV Manifest 补丁与 `ci/branding/` 品牌资源。三个 ABI 各由
独立 job 构建，避免 Rust/cargokit 与 libmpv 下载任务互相覆盖产物。

## 10. 开源协议

- **主体代码：Apache License 2.0**，全文见 [LICENSE](LICENSE)（与上游一致）
- 本改版对上游的改动标注：[NOTICE](NOTICE)、[ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md)
- 上游原文说明：[UPSTREAM_README.md](UPSTREAM_README.md)
- 第三方组件与原生库：[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- 字体：MiSans 由小米公司提供，免费商用，版权仍归小米公司所有

> ⚠️ **关于原生库的 GPL / LGPL 义务**：APK 内含 `mpv_audio_kit` 构建时下载的
> `libmpv.so`（mpv / FFmpeg 生态，可能包含 GPL 组件）。本仓库以 Apache-2.0 开源的是
> Dart / Kotlin / Rust **源码**；分发二进制时仍需按 GPL / LGPL 履行许可证文本、版权声明、
> NOTICE 与源码提供（或书面要约）义务。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
> 以及 mpv / FFmpeg 官方许可。使用本仓库构建并对外分发 APK 前，请先自行完成合规核对。

## 11. 反馈与贡献

- 问题反馈：[GitHub Issues](https://github.com/midi-HL/myune_music_android_tv/issues)
- 代码贡献：[Pull Requests](https://github.com/midi-HL/myune_music_android_tv/pulls)
- 上游桌面版（Windows / Linux）的问题请提到[上游仓库](https://github.com/xiaobaimc/myune_music/issues)，
  本改版只处理 Android / Android TV 相关问题。

## 12. 回滚

本仓库保留完整历史与锚点 tag，可随时回退：

| Tag | 含义 |
| --- | --- |
| `baseline-558a71f-0713` | 早期 Android 移植基线 |
| `baseline-4168e51-pre-tv` | TV 适配开始前的完整状态 |
| `tv-v2-focus-fix` / `tv-v3-focus-fix` / `tv-v4-focus-fix` | 各轮 TV 焦点修复版本 |
| `v1.0.0` | 本开源化版本（关于页 / 检查更新 / 三 ABI） |

```bash
git checkout tv-v4-focus-fix      # 回到某个锚点
git revert <commit>               # 保留审计轨迹地撤销某次改动
```

## 13. 致谢

- [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) — 上游桌面版及其 Apache-2.0 开源代码
- [mpv_audio_kit](https://github.com/ales-drnz/mpv_audio_kit)（BSD-3-Clause）与 mpv / FFmpeg 社区
- [lyricGeter](https://github.com/WisteriaZy/lyricGeter) — 歌词获取与解析逻辑参考
- 小米 MiSans 字体、Flutter / Rust / Dart 开源社区
