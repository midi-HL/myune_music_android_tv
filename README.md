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

0. [本次更新与功能总览](#0-本次更新与功能总览)
1. [这是什么](#1-这是什么)
2. [基于什么源仓库](#2-基于什么源仓库)
3. [与上游基本一致的说明](#3-与上游基本一致的说明)
4. [开发者与维护者](#4-开发者与维护者)
5. [电视 / 遥控器 / 键盘 / 手柄操作](#5-电视--遥控器--键盘--手柄操作)
6. [做了哪些适配](#6-做了哪些适配)
7. [网络媒体（WebDAV / FTP / 哔哩哔哩）](#7-网络媒体webdav--ftp--哔哩哔哩)
8. [下载与 ABI](#8-下载与-abi)
9. [检查更新](#9-检查更新)
10. [从源码构建](#10-从源码构建)
11. [开源协议](#11-开源协议)
12. [反馈与贡献](#12-反馈与贡献)
13. [回滚](#13-回滚)
14. [致谢](#14-致谢)

---

## 0. 本次更新与功能总览

### 0.1 本版（v1.6.1）更新了什么

> 采用语义化版本：新增功能升 minor、只修 bug 升 patch，每次发版**新建独立 tag / Release**
> （`v1.0.0` → `v1.1.0` → `v1.1.1` → `v1.1.2` → `v1.2.0` → `v1.3.0` → `v1.4.0` → `v1.5.0` → `v1.5.1` → `v1.6.0` → **`v1.6.1`**）。
> 这样应用内「检查更新」能通过 `/releases/latest` 感知到新版本，也能随时回滚到任一构建。
> 具体**缺陷修复清单**写在对应版本的 Release 发布说明里。

| 类别 | 更新内容 |
| --- | --- |
| 十字方向键 | 全链路几何焦点导航复核；离屏页焦点隔离、同行同列优先、可见性过滤；进度条不吞方向键、设置滑块可左右调值且上下可离开 |
| 播放页 | 按桌面原版还原布局尺寸（修复整体偏小、控件栏过细）；按窗口面积平滑适配任意分辨率；播放时无操作 5 秒自动隐藏控件栏，任意方向键 / 确认键 / 媒体键立即唤醒 |
| 音乐区 / 歌词 | 哔哩哔哩推荐固定音乐区；字幕 / 歌词自动识别；歌词来源优先级对话框补上移 / 下移按钮，遥控器也能调整顺序 |
| 图标 | 仅重做 320×180 TV 横幅；手机方形 / 圆形启动图标保持原样 |
| 网络硬盘（本轮反哺） | 见下表「2026-11-12 反哺」 |
| 手柄 / 遥控器 | 所有新增界面、菜单、星标、开关、对话框均十字键可达并带焦点高亮；软键盘与返回键行为不变 |
| **v1.2.0 播放页焦点修复** | 歌词行退出 D-pad 焦点链（原会抢初始焦点、左右键后整页丢焦点、OK 误触旧页面收藏按钮）；打开播放页主动把焦点落到播放控制栏；焦点落到不可见节点时立即拉回当前页面 |
| **v1.2.0 B 站封面** | 播放页左侧自动下载并显示视频封面（`albumArt` 为空时按代理 URL 里的封面地址异步获取），按封面方形 `BoxFit.cover` 缩放并限制解码尺寸 |
| **v1.2.0 B 站音质** | 不再固定 360P + 取第一条音轨；按 127 → 80 → 16 档清晰度依次请求，在 `dash.audio[]` 里按 Hi-Res / 杜比 / 码率优先级取**可获取的最高音质** |
| **v1.3.0 只读 Google Drive** | 新增第四种网络源；局域网扫码配对（电视零打字）、`drive.readonly` 只读、本地授权脚本 `tools/gdrive_auth.py`、凭据只存电视本机；与 WebDAV / FTP 共用浏览 / 播放 / 收藏 / 元信息链路 |
| **v1.4.0 播放页视觉归一** | 字号 / 行距 / 模糊强度 / 背景模糊半径按 `UiScaleScope.visualScale` 归一，并压制 Android 系统字体缩放，使「歌词显示设置」里 30.0 / 6.0 / 4.0 等设置值在电视端的视觉像素与桌面端一致；**不改动任何设置默认值** |
| **v1.4.0 歌词选择** | 播放页歌词设置下面新增「歌词选择」：网络歌词 / 内嵌歌词 / 外置文件（自动识别所有格式）/ 从网上获取新歌词，选中即实时生效，**不写任何持久化设置**；设置页原有的 6 项来源优先级排序完整保留 |
| **v1.4.0 GDrive 说明** | 补齐 Testing 状态 `refresh_token` 7 天过期、100 测试用户上限、Restricted scope 年度安全评估等限制，并给出一键重授权指引与失效提示 |
| **v1.5.0 字号修复（首要）** | 歌曲名 / 作曲家不再随封面尺寸联动放大，锁到桌面端 20 / 14 视觉像素；1080p 大屏放大系数锁到 1.0；电视端默认歌词设置统一到电脑那套 30.0 / 550 / 6.0 / 4.0 |
| **v1.5.0 性能约束** | 保留 v1.4.0 的一次性静态模糊与质感，**不新增任何实时 / 逐帧高斯模糊**；用户确认之前版本仅打开时卡一下、使用流畅 |
| **v1.5.0 Google Drive 配对助手** | 新增 `gdrive-pair/`（Go + Fyne，参考 Kazumi 的 Material 3 深色 / 圆角卡片 / 侧边导航 + 顶部栏）：设置缺失自动跳转并永久保存、支持直接输入授权码、按现有登录方式与电视配对；手机扫码配页同步改版 |
| **v1.5.1 字号真正修复** | A/B 像素对比发现 v1.5.0 的字号改动与旧 clamp 下限数值相同、画面零变化；本版显式降到 15 / 10.5 视觉像素且不再经过 clamp，并加防复发断言 |
| **v1.5.1 Windows 助手** | 补齐 `gdrive-pair-windows-amd64.exe`，与 Linux amd64 / arm64 一并作为 Release 附件；明确不做手机原生 App（理由见 `gdrive-pair/README.md`） |
| **v1.6.0 B站收藏夹** | 新增「B站收藏夹」分区：先列账号收藏夹（名称/条目数，默认夹置顶），选中后读该收藏夹视频，可加载更多；只读取 B 站账号收藏列表，需扫码登录（现有登录态即可，无需抓包）。与「本地收藏」星标并存、分两个入口 |
| **v1.6.0 历史记录约束** | 「历史播放」继续读本机记录（`BiliLibraryStore`），不接 B 站服务端观看历史 API |
| **v1.6.1 全局 D-pad 焦点修复** | 修四处根因：① 焦点停在 `rootScope` 时 `Shortcuts` 找不到 `Actions`，方向键完全不触发且 guard 只在焦点变化时触发 → 死锁，在全局按键层加方向键兜底落焦；② 容器判定用「宽 >= 85% **或** 高 >= 80%」误杀全宽列表项，改为只排除整页容器 / 细长侧栏；③ 几何评分让 DOWN 跨区跳到侧栏 / 底部播放控制栏，新增 `_NavZone` 上下锁区、左右仍可跨区；④ 页面级 `Shortcuts`/`Actions` 吞掉歌词抽屉方向键，最终统一由全局 `_onHardwareKey` 驱动所有方向键（输入框放行、滑块交给 `handleSliderKey`、其余 `moveFocus(lockZone: true)`）。覆盖歌手 / 统计 / 全部歌曲 / 本地收藏 / 历史播放 / 搜索结果 / 推荐 / B站收藏夹 / 歌词显示设置抽屉等所有主内容区 |

**2026-11-12：反哺 [XYkadicloud/myune_music v0.9.5-network.1](https://github.com/XYkadicloud/myune_music/releases/tag/v0.9.5-network.1)**

该分支基于上游 v0.9.5，修复并优化了网络硬盘（WebDAV / FTP）链路。本改版把其中适用于
Android TV 的部分移植回来（Google Drive 的桌面 OAuth 与文件上传管理未移植）：

- **内嵌标签 / 封面 / 歌词读取**：用 HTTP `Range` 只拉文件头，纯 Dart 解析 FLAC
  `METADATA_BLOCK` 与 MP3 `ID3v2`，得到标题 / 歌手 / 专辑 / 时长 / 封面 / 内嵌歌词；
  结果按「内存 → 磁盘 → 网络」三级缓存，封面与元数据分开落盘，重启自动回填、不重读。
- **网络硬盘歌曲进「收藏」分类**：WebDAV / FTP 歌曲可单曲星标或「全部加入收藏」，
  直接出现在默认「收藏」歌单里，点击即播，并显示真实歌曲名、歌手、时长、封面等元信息；
  **不再需要每次进入「网络媒体 → 网络硬盘」逐层选目录**。
  **哔哩哔哩不参与**：B 站继续用独立的收藏 / 历史播放仓库，两者互不混用。
- **网络硬盘稳定性**：修复网络代理 URL 被 `path.normalize()` 折叠斜杠、导致封面工作线程
  误判为本地文件而永远读不到封面的问题；WebDAV 首包超时放宽到 45 秒（小于 mpv 的 60 秒），
  避免自建网盘桥首包慢造成 `loading failed`。
- **遥控器适配**：新增的「全部加入收藏 / 一键读取本目录标签与封面 / 读取内嵌标签开关」都在
  原有 TV「更多」菜单里，单曲星标是独立可聚焦按钮，全部十字键可达。

### 0.2 对比原版项目新增了哪些功能

基线：[xiaobaimc/myune_music v0.9.5](https://github.com/xiaobaimc/myune_music)（Windows / Linux
桌面本地音乐播放器，Flutter + Rust / mpv）。本改版在保留其播放与界面能力的前提下新增：

| 能力 | 原版桌面版 | 星音 StarNote（本改版） |
| --- | --- | --- |
| 运行平台 | Windows / Linux 桌面 | **Android / Android TV / 普通安卓电视盒子**，同一 APK 自动适配 |
| 输入方式 | 鼠标 / 键盘 | **纯遥控器 / 十字键 / 键盘 / 手柄**均可完整操作，几何方向焦点导航 + 原生式高亮 |
| 文件访问 | 本地磁盘路径 | 新增 **Android SAF**（`ACTION_OPEN_DOCUMENT_TREE` / `content://` → `fd://`），不改系统 DPI 的应用内缩放 |
| 界面缩放 | 固定桌面布局 | 按窗口面积平滑适配任意分辨率；播放页与桌面端视觉尺寸一致 |
| 播放页沉浸 | 无操作自动隐藏控件栏（仅鼠标唤醒） | 保留该行为，并让**遥控器 / 手柄按键也能唤醒** |
| 电视入口 | 无 | Leanback Launcher、TV banner、手柄图标、媒体键、返回键与抽屉逻辑 |
| 网络硬盘 | 无 | **WebDAV / FTP** 客户端 + 本机流代理（HTTP Range / 断点续传），按需拉流不落盘 |
| 网络音频元信息 | 无 | 内嵌标签 / 封面 / 内嵌歌词读取 + 落盘缓存（反哺自 network.1） |
| 网络音频收藏 | 无 | 网络硬盘歌曲直接进「收藏」分类，可预览元信息、点击即播（不含 B 站） |
| 哔哩哔哩 | 无 | 免登录搜索 / 播放、音乐区推荐、二维码登录、分 P、收藏 / 历史播放、官方 CC 字幕 |
| 音频格式 | 常见格式 | 额外兼容 APE / WavPack / TTA / TAK / DSD / AIFF / CAF / WMA / MIDI / AC3 / DTS 等老旧格式，视频容器可仅音频播放 |
| 交付与开源 | 源码 | Apache-2.0、中英 README / NOTICE / 第三方声明、**固定 release 签名**、GitHub Actions 三 ABI（arm64-v8a / armeabi-v7a / x86_64）自动出包 |
| 应用信息 | 指向上游 | 关于页与「检查更新」指向本改版仓库，保留完整 Git 历史可随时回滚 |

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
| 本改版版本 | `1.6.1`（见 `lib/tv/tv_app_info.dart`） |

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

**本改版的差异集中在平台适配层、输入层与新增的网络媒体入口**（详见第 6、7 节）：Android 平台隔离、
SAF 文件访问、TV 桌面入口与品牌、遥控器 / 键盘 / 手柄输入、焦点导航、TV 控件可达性、
指向本仓库的关于信息与检查更新、固定 release 签名，以及「网络媒体」页里新增的 WebDAV / FTP /
哔哩哔哩流式播放。上游已有的本地音乐播放逻辑没有被替换，老功能不受影响。

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
| 鼠标 / 触控 | 所有 TV 控件同时保留点击路径，方便排查焦点问题 |

### 5.1 文本输入与软键盘

电视上没有鼠标，也不该让方向键被困在多个输入框里。因此所有需要打字的地方统一走
「字段按钮 → 弹出单字段输入对话框」：

- 按下「搜索关键词」「服务器地址」「端口」「密码」等**字段按钮**（OK）才弹出输入框；
- 输入框 `autofocus` 并显式调用 `TextInput.show`，遥控器 OK 一定能**唤出软键盘**；
- 方向键在软键盘上选字，OK 确认；按「完成 / 搜索」或弹窗里的「确定」提交；
- 全局 TV 输入层在文本输入获焦时**不劫持任何按键**（含 Esc），避免抢走输入法光标操作；
- 弹窗里的「取消 / 确定 / 关闭」等按钮同样遥控器可达，且始终有一个初始焦点。

### 5.2 哔哩哔哩扫码登录

登录全程**不需要在电视上打字**：弹窗展示 `qr_flutter` 渲染的二维码，用手机哔哩哔哩 App
扫码并在手机上确认；电视端每 2 秒轮询状态，显示「等待扫码 / 已扫码 / 已过期 / 登录成功」，
并提供「刷新二维码 / 退出登录 / 关闭」三个按钮。登录态只保存 Cookie 于本机，不保存账号密码。

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
9. **网络媒体**（详见第 7 节）：新增「网络媒体」导航入口与 WebDAV / FTP 客户端、哔哩哔哩
   Web API 客户端、只监听 `127.0.0.1` 的本机 HTTP 流代理（支持 Range），把远端音频 / 视频流
   包装成 `http://` 交给原有 `Media()` 播放链路；`AudioService` 与播放队列无需改动。
10. **固定 release 签名**：CI 强制使用同一把 keystore 出包，缺失签名 secrets 或检出
    `CN=Android Debug` 证书都直接让构建失败；三个 ABI 共用同一证书，后续版本可直接覆盖安装。

完整的逐轮修复记录与回滚锚点见 [ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md)。

## 7. 网络媒体（WebDAV / FTP / Google Drive / 哔哩哔哩）

解决电视本地容量有限、无法保存全部音乐的问题：**按需拉流、不落盘**，远端文件只在播放时
经本机代理读取，不占用电视存储。入口在主导航「网络媒体」，下分两个标签。

### 7.1 网络硬盘 / 共享网盘

- 协议：**WebDAV**（即名称以 `web` 开头的网络硬盘 / 共享网盘协议，支持 HTTP / HTTPS、
  Basic Auth、PROPFIND 列目录）与 **FTP**（匿名 / 用户名密码、PASV、REST 断点续传）。
- 左侧管理连接配置（添加 / 编辑 / 删除），右侧浏览目录；支持「返回上级 / 刷新 /
  播放全部音频 / 全部加入队列」以及「立即播放 / 加入队列」点击行为切换。
- 识别 `mp3 / flac / wav / m4a / aac / ogg / opus / wma / ape / aiff / dsf / m4b…` 等音频格式。
- **加入收藏（不含哔哩哔哩）**：每个音频行有独立可聚焦的星标按钮，「更多 → 全部加入收藏」
  可整目录加入；加入后直接出现在默认「收藏」歌单，点击即播，无需再逐层进入网盘目录。
  收藏以完整歌曲对象持久化（含标题 / 歌手 / 专辑 / 时长 / 封面），重启后元信息仍在。
- **内嵌元信息预览**：进入目录后按需读取音频文件头里的 FLAC / ID3v2 标签，列表直接显示
  真实「标题 · 歌手」与时长；封面同时回填播放页与收藏列表。「更多 → 一键读取本目录标签与封面」
  可提前缓存整目录；「读取内嵌标签」开关可随时关闭以省流量。缓存只存元数据与封面，
  **不缓存音频文件**；重启自动回填，不重复联网。内嵌歌词会作为歌词来源之一。
- **首包与 URL 稳定性**：WebDAV 首包超时 45 秒（小于 mpv 60 秒），避免自建网盘桥首包慢
  导致 `loading failed`；网络代理 URL 不再被路径规范化破坏，封面加载稳定。
- 密码只保存在本机 `SharedPreferences`，不随仓库提交、不写日志。

### 7.1b 只读 Google Drive（扫码配对）

**只读**：只请求 `drive.readonly`，不提供上传 / 新建 / 重命名 / 删除，绝不改动云端文件。

为什么用「扫码传凭据」而不是电视上登录：

- Android TV / 盒子通常没有系统浏览器，桌面版的 loopback OAuth 打不开授权页；
- Google 的**设备码流程**（TV 显示短码、手机输码）只允许 `drive.file` /
  `drive.appdata` 等有限 scope，**不支持 `drive.readonly`**，读不到已有音乐库；
- Google 的 token 接口不允许浏览器直连（CORS）、OOB 回调已停用、私网 IP 也不能
  登记为 redirect_uri，纯网页拿不到长期 `refresh_token`。

因此采用**局域网配对**：电视显示二维码，手机 / 电脑在同一 WiFi 下打开配页，
凭据直接 POST 到电视本机，**不经过任何第三方服务**；电视上一个字都不用打。
配对服务只在对话框打开期间监听，关闭即停，并用一次性配对码防止误提交。

配置步骤（一次性，约 3 分钟）：

1. 到 [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
   创建 OAuth 客户端，类型选「**桌面应用**」(Desktop app)，记下 `client_id`
   与 `client_secret`。
2. 在 OAuth 同意屏幕启用 Google Drive API，把
   `https://www.googleapis.com/auth/drive.readonly` 加入测试范围，
   并把你自己的 Google 账号加进「**测试用户**」（未做 OAuth 验证的应用要求）。
3. 电视上进入「网络媒体 → 网络硬盘 → **添加 Google Drive**」，会显示二维码、
   局域网地址与 6 位配对码。
4. 在电脑上执行（Python 3 标准库，零依赖）：

   ```bash
   python tools/gdrive_auth.py \
     --client-id "xxxx.apps.googleusercontent.com" \
     --client-secret "GOCSPX-xxxx" \
     --pair-url "http://192.168.1.20:18780/?pair=AB3D7K"
   ```

   浏览器会打开 Google 登录页；同意后脚本自动把 `refresh_token` 推给电视。
   `--pair-url` 就是二维码内容，也可直接扫二维码后把地址贴进来。
5. 电视显示「配对成功 + 账号」，按「完成」即可。之后选中该源浏览云端硬盘，
   与 WebDAV / FTP 一样支持播放、加入队列、星标收藏与内嵌标签 / 封面读取。

> 也可用 [Google OAuth Playground](https://developers.google.com/oauthplayground/)
> 手动生成 `refresh_token`，再在配对页里填写。凭据只存在电视本机
> `SharedPreferences`，不写日志、不随仓库提交。需要设备能访问 Google。

**关于「测试用户」与有效期（重要）**

- 每个用户创建的是**自己的** Cloud 项目、自己是唯一的测试用户，所以**任何人都能
  按上面步骤配置使用**，不存在「只有 100 个测试用户能用」的限制。100 人是单个
  项目测试名单的硬上限，自用场景只有 1 人。
- 但处于 **Testing** 发布状态的应用，Google 签发的 `refresh_token` **7 天后过期**
  （官方规则：只有仅请求 `userinfo.email/profile/openid` 时才豁免；本项目请求
  `drive.readonly`，不豁免）。因此**大约每周要重跑一次** `gdrive_auth.py`：
  在电视上重新打开「添加 Google Drive」拿到新的二维码 / `--pair-url`，脚本原样
  再跑一遍即可，其余参数不用改。授权失效时应用会提示「授权已过期」并给出同样指引。
- 想做成「一个客户端、所有人开箱即用」需把同意屏幕发布为 In production 并通过
  OAuth 验证。而 `drive.readonly` 属于 **Restricted scope**，要求品牌验证
  （自有域名 + 隐私政策）、合规应用类型、端到端演示视频、最小 scope 论证，
  以及**每年一次由 Google 授权评估机构执行的第三方安全评估**（付费）。
  桌面应用的 `client_secret` 官方明文视为非机密，无法靠保密规避；
  「已发布但未验证」状态虽然任何 Google 账号可用，却有 100 用户上限和危险警告 UI。
  对个人 / 开源自用项目，维持「每人自带凭据」是更现实的选择。

### 7.2 哔哩哔哩

参考 [BiliMusic-Desktop](https://github.com/licpp/BiliMusic-Desktop) 的功能范围与交互：

- 关键词搜索、分页、BV 号 / av 号 / 完整链接解析、分 P 展开；
- 单独播放某个分 P、播放全部分 P、整组加入队列；
- 音频流（DASH 音频轨，默认，更省流量）/ 视频流切换；
- 搜索历史、**二维码扫码登录**（不登录也可搜索与播放）；
- WBI 签名、CDN `Referer` / `User-Agent` / `Cookie` 请求头、失败回退旧接口。

### 7.3 实现要点

- 远端流统一编码成 `http://127.0.0.1:<port>/starnote/<base64url JSON>`；端口固定候选
  `18765–18774`、token 固定，因此**应用重启后队列里的 URL 仍然有效**，元数据（标题 / 歌手 /
  专辑 / 时长）也编码在 URL 里，无需重新联网枚举。
- 代理支持 HTTP `Range`，输出正确的 `200` / `206`、`Accept-Ranges`、`Content-Length` 与
  `Content-Range`，网络流可以拖动进度；上游不给总长度时退回 `200` 顺序流，避免截断。
- `RemoteMediaRegistry` 在解析歌曲元数据时拦截代理 URL，避免误走 `File.exists()` /
  本地标签读取而显示「文件不存在」；本地文件路径仍走原来的完整链路。
- CI 注入 `android:usesCleartextTraffic="true"`，保证明文 HTTP WebDAV 与本机代理可用。

## 8. 下载与 ABI

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

安装：用文件管理器或 `adb install` 安装对应 ABI 的 APK。自本版本起所有 APK 使用
**同一把固定 release 签名**（`CN=StarNote TV`），三个 ABI 证书一致，后续版本可直接
**覆盖安装，不再需要卸载重装**。CI 会拒绝任何缺失签名 secrets 或检出 Android Debug 证书的构建，
因此不会再出现「不同 ABI 签名不匹配」。

> 从 `v1.0.0`（debug 签名）首次升级到本版本时，因证书不同仍需卸载一次旧版；此后即可正常覆盖安装。

## 9. 检查更新

应用内「设置 → 常规 → 检查更新」与启动静默检查都请求：

```
https://api.github.com/repos/midi-HL/myune_music_android_tv/releases/latest
```

**不会再检查上游 PC 桌面版** `xiaobaimc/myune_music`。Release tag 约定为 `vX.Y.Z`
（例如 `v1.0.0`），与 `lib/tv/tv_app_info.dart` 中 `TvAppInfo.version` 对应；关于页里的
仓库 / Issue / Releases 链接也指向本仓库。

## 10. 从源码构建

本机**不需要** Flutter / Rust / NDK：编译与 APK 校验全部由
[`.github/workflows/build_android.yml`](.github/workflows/build_android.yml) 在 GitHub Actions 完成。

工具链：Flutter `3.47.5` / Dart 3.10、Rust stable、JDK 21、Android SDK 36、
NDK `28.2.13676358`、CMake `3.22.1`。

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64   # 或 android-arm / android-x64
```

固定 release 签名需要在仓库 `Settings → Secrets and variables → Actions` 配置 4 个 secrets：
`ANDROID_KEYSTORE_BASE64`（JKS 的 base64）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS`。CI 用它们生成 `android/key.properties` 并切换
`signingConfigs.release`；**任一缺失直接构建失败**，绝不回退到模板的 debug 签名。
keystore 与密码不进入仓库。

上游没有 `android/` 目录，CI 会用 `flutter create --platforms=android` 生成 runner，
再注入 `ci/MainActivity.kt`、TV Manifest 补丁与 `ci/branding/` 品牌资源。三个 ABI 各由
独立 job 构建，避免 Rust/cargokit 与 libmpv 下载任务互相覆盖产物。

## 11. 开源协议

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

## 12. 反馈与贡献

- 问题反馈：[GitHub Issues](https://github.com/midi-HL/myune_music_android_tv/issues)
- 代码贡献：[Pull Requests](https://github.com/midi-HL/myune_music_android_tv/pulls)
- 上游桌面版（Windows / Linux）的问题请提到[上游仓库](https://github.com/xiaobaimc/myune_music/issues)，
  本改版只处理 Android / Android TV 相关问题。

## 13. 回滚

本仓库保留完整历史与锚点 tag，可随时回退：

| Tag | 含义 |
| --- | --- |
| `baseline-558a71f-0713` | 早期 Android 移植基线 |
| `baseline-4168e51-pre-tv` | TV 适配开始前的完整状态 |
| `tv-v2-focus-fix` / `tv-v3-focus-fix` / `tv-v4-focus-fix` | 各轮 TV 焦点修复版本 |
| `v1.0.0` | 首个开源化版本（关于页 / 检查更新 / 三 ABI，debug 签名） |
| `v1.1.0` | 网络媒体（WebDAV / FTP / 哔哩哔哩）+ 固定 release 签名版本 |
| `v1.1.1` | 网络媒体播放修复、哔哩哔哩分页重构、历史播放 / 收藏、老旧音频格式兼容 |
| `v1.1.2` | 十字方向键全链路复核、推荐限定音乐区、B 站字幕 / 歌词显示、全新品牌图标 |
| `v1.1.2`（后续累积） | 播放页尺寸还原与自动隐藏控件栏、网络硬盘反哺（内嵌标签 / 收藏分类）、遥控器可达性修复（曾以 `--clobber` 覆盖同名资产） |
| **`v1.2.0`** | **起改用独立 tag 发版；修复播放页 D-pad 焦点（歌词行抢焦点 / 焦点丢失 / 误触旧页面收藏）、B 站视频封面自动显示并方形缩放、B 站音频流取可获取的最高音质** |
| **`v1.3.0`** | **新增只读 Google Drive 源：局域网扫码配对、电视零打字、本地授权脚本；含模型 / 代理 / 服务层 / TV 入口与中英文档** |
| **`v1.4.0`** | **播放页字号 / 模糊视觉归一、播放页歌词设置内新增实时「歌词选择」、Google Drive 测试状态限制与重授权说明** |
| **`v1.5.0`** | **修复歌曲名 / 作曲家字号过大 + 锁大屏放大、保留一次性静态模糊不新增实时模糊、新增 Go/Fyne 图形化 Google Drive 配对助手与手机配页改版** |
| **`v1.5.1`** | **真正修复歌曲名 / 作曲家字号（A/B 实测确认）、新增 Windows 版配对助手、明确手机端沿用扫码配页** |
| **`v1.6.0`** | **新增 B 站账号收藏夹分层浏览（与本地星标收藏并存）、历史记录保持本机不接 B 站服务端历史** |
| **`v1.6.1`** | **修复全局 D-pad 死锁与全宽列表项被误判为容器，所有主内容区恢复遥控器可达** |

```bash
git checkout tv-v4-focus-fix      # 回到某个锚点
git revert <commit>               # 保留审计轨迹地撤销某次改动
```

## 14. 致谢

- [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) — 上游桌面版及其 Apache-2.0 开源代码
- [mpv_audio_kit](https://github.com/ales-drnz/mpv_audio_kit)（BSD-3-Clause）与 mpv / FFmpeg 社区
- [lyricGeter](https://github.com/WisteriaZy/lyricGeter) — 歌词获取与解析逻辑参考
- 小米 MiSans 字体、Flutter / Rust / Dart 开源社区
