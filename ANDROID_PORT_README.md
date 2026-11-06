# MyuneMusic → Android 移植说明（当前阶段：CI 构建可安装 APK）

本仓库是 `github.com/xiaobaimc/myune_music` 的 Android 移植工作副本。上游是 Flutter 3.47.5 / Dart 3.10 的 Windows / Linux 桌面本地音乐播放器，原本没有 `android/` 目录。所有 Android 编译都在 GitHub Actions 完成，本地不需要 Flutter / Rust / NDK。

首个 arm64-v8a APK 已通过真机验证：启动、导入、播放、后台媒体控制均正常。随后按真机反馈补齐沉浸式全屏、应用内缩放、SAF 目录树、content URI 播放/元数据、触屏 hover 回退与横屏双栏；第三轮又修复播放页二次缩放、播放/音量控件命中、竖屏方向锁定、竖屏歌词过小，以及划掉后台任务后媒体会话状态错位。

## 当前已完成的改造

1. **`lib/main.dart` 平台隔离**
   - `window_manager` / `tray_manager` / `hotkey_manager` / `flutter_single_instance` 的初始化与托盘回调只在桌面执行。
   - `build()` 中跳过 `DragToResizeArea` + `Hotkeys`。
   - 系统字体枚举 `SystemFonts` 与启动更新检查在 Android 跳过；保留 `MpvAudioKit.ensureInitialized()` 与 `RustLib.init()`。

2. **窗口标题栏**
   - 两个 `AppWindowTitleBar` 在 Android 返回 `SizedBox.shrink()`，去掉桌面窗口边框。

3. **设置页快捷键 tab**
   - `lib/page/setting/setting_page.dart` 在 Android 隐藏「快捷键」导航项，并为 `case 4` 加空白页兜底。这样不会触达 `hotkey_manager` 的桌面原生 API 和 `HotKeyRecorder` 键盘录制 UI。

4. **`rust_builder/cargokit/gradle/plugin.gradle` 兼容 Flutter 3.47.5**
   - 同时识别 `FlutterPlugin` 与 `com.flutter.gradle.FlutterPlugin`。
   - 优先调用 `FlutterPluginUtils.getTargetPlatforms(project)`；旧 Flutter 仍回退到 `plugin.getTargetPlatforms()`。
   - 不修这一步，cargokit 会静默跳过 `librust_lib_myune_music.so`，`RustLib.init()` 在真机上会失败。

5. **沉浸式全屏与应用内缩放**
   - Android 启动和 `AppLifecycleState.resumed` 时应用 `SystemUiMode.immersiveSticky`，隐藏状态栏与手势导航条。
   - `MaterialApp.builder` 在 Android 用 `_AndroidUiScaler` 把整棵 UI 布局在更大的逻辑画布后整体缩小；默认 `0.72`，设置 → 常规 → 「界面缩放」可调 `0.55–1.00`，不改系统 DPI。
   - 桌面平台完全保持原布局。

6. **SAF 音乐库与 content URI**
   - `android/MainActivity.kt` 在 CI 生成 runner 后注入 `ACTION_OPEN_DOCUMENT_TREE`、持久化 URI 权限、递归音频枚举和字节读取通道。
   - `lib/services/android_content_resolver.dart` 是 Dart 侧唯一 SAF 适配层；Android 的「添加音乐目录」改用目录树授权，歌单 `folderPaths` 与歌曲 ID 可保存 `content://` URI。
   - 播放端由 `mpv_audio_kit` 的 `openFileDescriptor` 把 `content://` 转成 `fd://`；元数据读取则把音频缓存到应用私有临时文件后交给现有 Rust `readAudioInfo`，避免修改 FRB 生成代码。
   - 外置同目录 `.lrc` 的 SAF 关联、ReplayGain 写回仍按桌面路径语义处理；内嵌歌词、封面、时长、播放恢复已覆盖。

7. **触屏与横屏布局**
   - `HoverOverlayControl` 在 Android 点击展开浮层且不自动消失；音量浮层提供横向 Slider 与 +/- 按钮。
   - `MainView` 在宽屏横屏下把歌曲详情固定为右栏 detail pane，窄屏保持原 Navigator 行为。

8. **`.github/workflows/build_android.yml`**
   - 固定 Flutter `3.47.5` / Java 21；其默认 compileSdk 36、minSdk 24、NDK `28.2.13676358` 与 `mpv_audio_kit` 锁定 commit 的要求一致。
   - 用 `flutter create --platforms=android --org com.midihl --project-name myune_music_android` 生成固定 applicationId 的 runner；备份/恢复 `pubspec.lock`，因为 Flutter 3.47.5 的 `create` 会把它重写为只含 SDK 依赖的空壳。
   - 只构建 `android-arm64`，收窄 Rust 交叉编译、libmpv 下载和真机测试的变量。
   - 幂等注入 `android.permission.INTERNET`；媒体会话所需的 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS` 由 `mpv_audio_kit` 的 Manifest 合并带入。
   - 默认使用 Flutter 模板的 debug 签名；四个签名 secrets 齐全时自动切换 `release signingConfig`。
   - 产物：`build/app/outputs/flutter-apk/*.apk`，Artifact 名 `myune-music-android-arm64`。
   - CI 里还对齐了 vendored cargokit 的 Gradle 9 API、`file_picker 10.2.0` 与 `rust_builder/android` 写死的旧 compileSdk，以及旧插件的 Kotlin JVM target 校验；这些补丁不改变 Dart 依赖树。

## 当前可用构建

- Actions run：`42126221458`，结论 `success`。
- Artifact：`myune-music-android-arm64`（zip 41,922,438 bytes，SHA-256 `58d32b25fb23205a2fd5aa371d1c4d41b904a80f3ab4c0f0d00519e4dba5035b`）。
- APK：`app-release.apk`，71 MB；APK SHA-256 `b4d6f16bad441f04d9e8e5ac37589a0bba2b3bd972f44cea5cdfb59f14dd4027`。
- 签名：`C=US, O=Android, CN=Android Debug`；签名证书 SHA-256 `2f4fd0d8b5e7ba2a6351038b21fa4c1416104bf408c25fcfbcffdb9cdbfdd74b`。
- 下载入口：`https://github.com/midi-HL/myune_music_android/actions/runs/42126221458/artifacts/13461727050`（GitHub 登录后可下载）。

历史首个构建为 run `42059743949`，用于验证启动与播放链路；当前 APK 已包含全屏、缩放、SAF 与触屏适配。

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

## 第三轮真机复验清单

1. 横屏、竖屏都可自由旋转；竖屏播放页歌词和控件明显更大、不再沿用桌面窄窗口比例。
2. 播放页不再被全局缩放二次缩小；播放/暂停、上一首/下一首、进度条、音量 Slider / +/- 都能正常点击。
3. 状态栏、手势导航条默认隐藏；从边缘滑动可临时唤出，回到 App 后再次自动隐藏。
4. 设置 → 常规 → 「界面缩放」对列表/设置页仍生效；播放页不再受它二次影响。
5. 横屏宽屏下右侧固定显示歌曲详情；竖屏保持单栏大歌词布局。
6. 播放中划掉最近任务后声音停止；重新打开 App 状态一致，按播放或重新点歌立即响应，无需第二次冷启动。
7. 添加音乐目录弹出系统目录授权；授权后递归扫描 `content://` 音频，重启 App 后仍可播放。
8. 回归：点歌出声、歌词点击跳转、暂停/继续/切歌、锁屏/通知栏/蓝牙控制、切后台续播。

## 已知限制

- 外置同目录 `.lrc` 的 SAF 关联、ReplayGain 写回、按修改日期排序对 `content://` 的精确时间支持仍需后续增强；当前优先保证音频读取、元数据与播放链路。
- 应用内缩放是视觉层 `Transform.scale` + 逻辑画布，不替换各页面的硬编码尺寸；极窄设备可继续调低 `android_ui_scale`。
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
