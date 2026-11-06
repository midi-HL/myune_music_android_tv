# MyuneMusic → Android 移植说明（当前阶段：CI 构建可安装 APK）

本仓库是 `github.com/xiaobaimc/myune_music` 的 Android 移植工作副本。上游是 Flutter 3.47.5 / Dart 3.10 的 Windows / Linux 桌面本地音乐播放器，原本没有 `android/` 目录。所有 Android 编译都在 GitHub Actions 完成，本地不需要 Flutter / Rust / NDK。

首个 arm64-v8a APK 已通过真机验证：启动、导入、播放、后台媒体控制均正常。随后按真机反馈补齐沉浸式全屏、应用内密度、SAF 目录树、content URI 播放/元数据、触屏 hover 回退与横屏双栏；后续又修复后台任务状态、竖屏方向、竖屏歌词过小，并按第四轮视频/截图反馈删除会导致黑边与拖拽错位的 Transform 缩放，恢复播放页顶部导航、歌词设置抽屉与桌面一致的竖向音量条。CI 现在同时输出 arm64-v8a 与 armeabi-v7a 两个单 ABI APK。

## 当前已完成的改造

1. **`lib/main.dart` 平台隔离**
   - `window_manager` / `tray_manager` / `hotkey_manager` / `flutter_single_instance` 的初始化与托盘回调只在桌面执行。
   - `build()` 中跳过 `DragToResizeArea` + `Hotkeys`。
   - 系统字体枚举 `SystemFonts` 与启动更新检查在 Android 跳过；保留 `MpvAudioKit.ensureInitialized()` 与 `RustLib.init()`。

2. **窗口标题栏**
   - 通用标题栏在 Android 隐藏；播放页标题栏保留返回键与三点按钮，仅去掉窗口拖动区、最小化/全屏/关闭等桌面窗口按钮。三点按钮打开「歌词显示设置」抽屉。

3. **设置页快捷键 tab**
   - `lib/page/setting/setting_page.dart` 在 Android 隐藏「快捷键」导航项，并为 `case 4` 加空白页兜底。这样不会触达 `hotkey_manager` 的桌面原生 API 和 `HotKeyRecorder` 键盘录制 UI。

4. **`rust_builder/cargokit/gradle/plugin.gradle` 兼容 Flutter 3.47.5**
   - 同时识别 `FlutterPlugin` 与 `com.flutter.gradle.FlutterPlugin`。
   - 优先调用 `FlutterPluginUtils.getTargetPlatforms(project)`；旧 Flutter 仍回退到 `plugin.getTargetPlatforms()`。
   - 不修这一步，cargokit 会静默跳过 `librust_lib_myune_music.so`，`RustLib.init()` 在真机上会失败。

5. **沉浸式全屏与应用内密度**
   - Android 启动和 `AppLifecycleState.resumed` 时应用 `SystemUiMode.immersiveSticky`，隐藏状态栏与手势导航条。
   - `MaterialApp.builder` 在 Android 用 `AndroidUiScaler` 调整 `TextScaler` 与 `visualDensity`；默认 `100%`，设置 → 常规 → 「文字与控件密度」可调 `85–115%`。画面始终铺满屏幕，不改 `MediaQuery.size`、系统 DPI 或物理像素比，避免黑边和拖拽浮层坐标漂移。
   - 桌面平台完全保持原布局。

6. **SAF 音乐库与 content URI**
   - `android/MainActivity.kt` 在 CI 生成 runner 后注入 `ACTION_OPEN_DOCUMENT_TREE`、持久化 URI 权限、递归音频枚举和字节读取通道。
   - `lib/services/android_content_resolver.dart` 是 Dart 侧唯一 SAF 适配层；Android 的「添加音乐目录」改用目录树授权，歌单 `folderPaths` 与歌曲 ID 可保存 `content://` URI。
   - 播放端由 `mpv_audio_kit` 的 `openFileDescriptor` 把 `content://` 转成 `fd://`；元数据读取则把音频缓存到应用私有临时文件后交给现有 Rust `readAudioInfo`，避免修改 FRB 生成代码。
   - 外置同目录 `.lrc` 的 SAF 关联、ReplayGain 写回仍按桌面路径语义处理；内嵌歌词、封面、时长、播放恢复已覆盖。

7. **触屏与横屏布局**
   - `HoverOverlayControl` 在 Android 点击展开浮层、点击外部或再次点图标关闭；音量浮层与桌面一致，是连续竖向 Slider。
   - 歌词来源优先级弹窗在窄屏自动收窄，并使用 48dp 触屏拖拽把手与长按拖拽。
   - `MainView` 在宽屏横屏下把歌曲详情固定为右栏 detail pane，窄屏保持原 Navigator 行为。

8. **`.github/workflows/build_android.yml`**
   - 固定 Flutter `3.47.5` / Java 21；其默认 compileSdk 36、minSdk 24、NDK `28.2.13676358` 与 `mpv_audio_kit` 锁定 commit 的要求一致。
   - 用 `flutter create --platforms=android --org com.midihl --project-name myune_music_android` 生成固定 applicationId 的 runner；备份/恢复 `pubspec.lock`，因为 Flutter 3.47.5 的 `create` 会把它重写为只含 SDK 依赖的空壳。
   - 使用 matrix 分别构建 `android-arm64` 与 `android-arm`，每次只编译一个 target-platform，避免 Rust/cargokit 与 libmpv 下载任务在多 ABI 下互相覆盖产物。
   - 幂等注入 `android.permission.INTERNET`；媒体会话所需的 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS` 由 `mpv_audio_kit` 的 Manifest 合并带入。
   - 默认使用 Flutter 模板的 debug 签名；四个签名 secrets 齐全时自动切换 `release signingConfig`。
   - 产物：`myune-music-arm64-v8a-release.apk` / `myune-music-armeabi-v7a-release.apk`，Artifact 名分别为 `myune-music-android-arm64` / `myune-music-android-armv7`。
   - CI 里还对齐了 vendored cargokit 的 Gradle 9 API、`file_picker 10.2.0` 与 `rust_builder/android` 写死的旧 compileSdk，以及旧插件的 Kotlin JVM target 校验；这些补丁不改变 Dart 依赖树。

## 当前可用构建

当前源码对应 commit `9dd594c`，Actions run `42191112151`，两个 matrix job 均 `success`。

- `arm64-v8a`：[Artifact 13489993674](https://github.com/midi-HL/myune_music_android/actions/runs/42191112151/artifacts/13489993674)
  - zip 41,924,021 bytes，zip SHA-256 `afef12b20dab74810b57ed81ecdd1023caa574155eb17edd8424e109d88f3944`
  - APK `myune-music-arm64-v8a-release.apk` 73,819,902 bytes，SHA-256 `08bf0d4a3f92234d260aa32d92947d7c7a9b7c2bd783e2d3697ec739ba0f5cd9`
  - 签名证书 SHA-256 `1e88d6fe7120fc97d00f4b6711b1fdd0d7e9ca65e3001dd4ce9a1658d7f9f809`
- `armeabi-v7a`：[Artifact 13490257925](https://github.com/midi-HL/myune_music_android/actions/runs/42191112151/artifacts/13490257925)
  - zip 41,370,352 bytes，zip SHA-256 `352e0c388536b22cbb4d74646d824f02f0d94711d8d7bfad102bffc2e24e60b0`
  - APK `myune-music-armeabi-v7a-release.apk` 71,247,620 bytes，SHA-256 `7773315a0afa01c4fb574410668d8e646b0835d1f8b50b32ed1faa2c4634df88`
  - 签名证书 SHA-256 `8ba6553f82c43f47daae062eac22fda6f56642fbd01e3f0cc727e7196a145657`

两个包均为 debug 签名 `C=US, O=Android, CN=Android Debug`；每个 runner 独立生成 debug keystore，因此两个 ABI 的证书不同，覆盖安装遇到签名冲突时先卸载旧测试包。CI 已核对各自 ABI 的 `libmpv.so` 与 `librust_lib_myune_music.so`。

历史构建：`42059743949` 验证启动与播放链路，`42126221458` 加入全屏/SAF/触屏适配，`42163020869` 是第四轮反馈前的基线。

## 签名

当前阶段特意使用 debug 签名：debug keystore 可让 APK 直接安装测试，不需要你先提供正式 keystore。后续换成正式签名时，在 GitHub 仓库 `Settings → Secrets and variables → Actions` 添加：

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` 的输出 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | key 密码 |
| `ANDROID_KEY_ALIAS` | key alias |

四个值齐全后，workflow 会生成 `android/key.properties` 并把 release 的 `signingConfig` 从 debug 切到正式 keystore；任何一项缺失都保持 debug 签名。注意 debug 与正式签名的 APK 不能覆盖安装，换签名时先卸载测试包。

## 真机验证清单（拿到 APK 后）

1. 首次启动进入主界面，不闪退、不黑屏、不提示 Rust / libmpv 加载失败。
2. Android 13+ 首次播放时观察通知权限请求；设置页不出现「快捷键」入口。
3. 播放链路：当前仍按桌面逻辑读取文件路径，能用应用私有目录 / 可直读路径中的音频最好；若因 Android 分区存储读不到文件，记录日志与现象，这是 Phase 3 的输入。
4. 点歌后有声音，暂停 / 继续 / 上一首 / 下一首可用。
5. 锁屏、通知栏或蓝牙耳机媒体键能控制播放，切到后台继续播放。
6. 记录设备型号、Android 版本、APK 签名者 SHA-256、通过 / 失败项。

## 第四轮真机复验清单

1. 设置 → 常规 → 「文字与控件密度」在 85% / 100% / 115% 下都铺满屏幕，不出现小画面、黑边、拖拽浮层飞角或点击错位。
2. 播放页顶部有返回键和三点按钮；三点打开「歌词显示设置」抽屉，字号、字重、间距、模糊强度可调整并生效。
3. 音量按钮展开桌面同款竖向连续 Slider；点击外部、再次点图标可关闭；拖动音量实时变化。
4. 横屏播放页与电脑端截图接近：封面/进度/控制按钮占左栏，歌词占右栏，控件不再过小；竖屏仍可自由旋转，歌词明显放大。
5. 歌词来源优先级长按拖拽把手后条目在列表内移动，重置/取消/确定都正常。
6. 高级页「清理无效文件」可选择全部歌单，能识别 SAF 授权撤销后的失效 `content://` 条目；「刷新所有文件夹歌单」在授权失效时报错而不清空歌单。
7. 添加音乐目录、SAF 递归扫描、歌曲显示名、封面/时长/内嵌歌词、重启后播放、删除歌单/歌曲/目录、打开文件、长按菜单、ReplayGain 对 SAF 歌曲明确失败均逐项回归。
8. 播放中划掉最近任务后声音停止；重新打开 App 状态一致；后台播放、锁屏/通知栏/蓝牙控制、歌词点击跳转、音效设置保持正常。
9. 分别安装 `arm64-v8a` 与 `armeabi-v7a` 包，确认对应设备能启动、加载 `libmpv.so` 和 `librust_lib_myune_music.so`、正常出声。

## 已知限制

- 外置同目录 `.lrc` 的 SAF 关联、ReplayGain 写回、按修改日期排序对 `content://` 的精确时间支持仍需后续增强；ReplayGain 写回对 SAF 文档会明确记为失败，不会把 `content://` 当本地路径写坏。
- 应用内密度只影响文字和部分 Material 控件，不缩放硬编码的封面/画布尺寸；播放页仍按真实屏幕尺寸计算自己的布局。
- 宽屏双栏是主导航层 master-detail，歌单页内部已有自己的横屏列表双栏；两者叠加时以当前页面的响应式判断为准。

## 已知风险

- `mpv_audio_kit` 的 `android/build.gradle.kts` 会在构建时按 ABI 下载预编译 `libmpv.so`（release `libmpv-r13`），CI 需要外网访问 GitHub Releases；下载任务吞掉网络异常并继续，若 APK 缺少 `libmpv.so` 要在日志里检查 SHA-256 校验段。
- `rust_builder/android/build.gradle` 是 FRB 2.10.0 的 AGP 7.3 / compileSdk 33 模板，Gradle 依赖解析由 app 的 AGP 9.1 主导；若 CI 暴露不兼容，优先让 app runner 统一版本，而不是把 vendored 插件升级到未验证组合。
- 目前仓库是 shallow 单 commit 历史；如需保留上游完整历史，另起一轮 `git fetch --unshallow` 后再整理。

## 许可证与发布前清单

主体代码沿用上游 Apache-2.0，详见根目录 `LICENSE`；本移植对其做了上述改动，并在本文件记录改动内容。字体 MiSans 由小米提供，免费商用但版权仍归小米，许可链接见上游 `README.md`。

`mpv_audio_kit` 自身的 Dart/Kotlin 封装为 BSD-3-Clause；它打包的 `libmpv.so` 来自 mpv / FFmpeg 生态，包含 **GPL（以及可能的 LGPL）组件**。公开发布 APK 或把仓库改 public 前，需完成：

1. 核对 `libmpv-r13` 中每个预编译库的实际许可证与构建配置；
2. 在发行物里附对应许可证全文、版权声明、NOTICE 与本移植的改动标注；
3. 提供对应 GPL 组件的完整源码或有效的书面源码获取方式，覆盖实际分发的二进制版本；
4. 若 FFmpeg 启用了 GPL 编解码器，按 GPL 而非 LGPL 处理整个分发链路。

因此本阶段目标仓库保持 **private**，Artifact 仅用于内部真机测试，不视为公开发行。
