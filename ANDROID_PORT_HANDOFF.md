# MyuneMusic → Android 项目交接文档

> 本文件是回档后的完整交接说明。代码基线按用户更正后的要求回到 2026-11-06 07:13 的 `558a71f`（11 点左右仓库里的版本、也是 `a28f2c9` 的前一个版本），仅额外接入 64 位 / 32 位双 ABI 构建；12:13 之后所有 UI、缩放、横屏、密度、原生视口 DPI、挖孔主题改动均已撤销。

## 1. 项目是什么

- 上游：`github.com/xiaobaimc/myune_music`，Flutter 3.47.5 / Dart 3.10 的 Windows / Linux 桌面本地音乐播放器。
- 目标：把桌面播放器移植成 Android 可安装 APK，成果放在用户 GitHub 账号下的 private 仓库 `midi-HL/myune_music_android`。
- 本地工作副本：`C:\Users\hlmid\Desktop\cchh\myune_music_android\myune_music_src`。
- 远端：
  - `origin` → `https://github.com/midi-HL/myune_music_android.git`
  - `upstream` → `https://github.com/xiaobaimc/myune_music.git`
- 编译策略：本机只做静态检查；Flutter、Rust、NDK、Gradle、签名、打包全部由 `.github/workflows/build_android.yml` 在 GitHub Actions 上完成。本机不要求安装 Flutter / Rust / NDK。
- 仓库当前保持 private；Artifact 仅用于内部真机测试，不作为公开发行。

## 2. 技术栈与运行时链路

| 层 | 组件 | 用途 |
| --- | --- | --- |
| UI | Flutter 3.47.5 / Material 3 / Provider | 桌面原有页面、设置、歌单、歌词、播放页 |
| 播放 | `mpv_audio_kit`（锁定 commit `e87688132c2fc1b0960877a59a7b5a535b64917a`） | libmpv 播放、MediaSession、AudioFocus、后台媒体控制 |
| 元数据 | Rust + `flutter_rust_bridge` / `cargokit` | 通过 `readAudioInfo` 读取封面、时长、内嵌歌词等 |
| 文件访问 | Android SAF + `content://` | 目录树授权、递归音频枚举、字节读取 |
| 原生桥 | `ci/MainActivity.kt` | `ACTION_OPEN_DOCUMENT_TREE`、持久化 URI 权限、ContentResolver 查询、字节读取 |
| CI | GitHub Actions + Flutter 3.47.5 + Java 21 + SDK 36 + NDK 28.2.13676358 | 生成 Android runner、编译双 ABI release APK、上传 Artifact |
| 签名 | 默认 Flutter 模板 debug keystore | 四个正式签名 secrets 齐全时自动切到 release keystore |

播放链路要点：

1. Android「添加音乐目录」通过 SAF 获得目录树 URI 并持久化读权限。
2. 原生层递归枚举 `content://` 音频，把 URI / 显示名 / MIME / 修改时间返回 Dart。
3. 歌单 `folderPaths` 与歌曲 ID 可保存 `content://` URI。
4. 播放端由 `mpv_audio_kit` 的 `openFileDescriptor` 把 `content://` 转成 `fd://`。
5. Rust 元数据解析器只接受真实文件路径；`lib/services/android_content_resolver.dart` 把音频字节缓存到应用私有临时目录后再交给 `readAudioInfo`，避免修改 FRB 生成代码。

## 3. 当前回档版本

- 用户更正后指定回档点：`558a71f`，提交时间 2026-11-06 07:13:16 +08:00，提交信息 `docs: record immersive and SAF APK build`；它是 11 点左右仓库里的版本，也是 `a28f2c9` 的前一个版本。
- 第一阶段已倒序 `git revert` 撤销 `a28f2c9` 之后的五个提交，保留已推送历史和审计轨迹：
  - `0f63f86` docs: record final player-page and portrait fixes APK
  - `9dd594c` android: fix UI density, player controls and SAF library maintenance
  - `7c3306c` docs: record verified dual-ABI APK artifacts
  - `24bc8c0` android: restore full UI scaling and rework landscape player
  - `f5e944a` docs: record restored UI scaling APK artifacts
- 第二阶段撤销 `706d38b`、`7433a3f`、`a28f2c9` 对应的代码效果：`lib/widgets/android_ui_scale.dart` 删除，`ANDROID_PORT_README.md`、`lib/main.dart`、`lib/page/song_detail_page.dart`、`lib/widgets/lyrics_widget.dart` 恢复到 `558a71f`。
- 当前代码与 `558a71f` 一致；唯一保留的新增改动是 `.github/workflows/build_android.yml` 的双 ABI matrix 与本交接文档。
- 用户更正说明：不是 `a28f2c9` 中午 12:31 版，而是再上一个版本。

## 4. 这个版本保留的改造

### 4.1 平台隔离

- `lib/main.dart`：
  - `window_manager` / `tray_manager` / `hotkey_manager` / `flutter_single_instance` 初始化与托盘回调仅在桌面执行。
  - `build()` 在 Android 跳过 `DragToResizeArea` 与 `Hotkeys`；桌面仍保留原逻辑。
  - `SystemFonts` 与启动更新检查在 Android 跳过；保留 `MpvAudioKit.ensureInitialized()` 与 `RustLib.init()`。
- `lib/page/setting/setting_page.dart`：Android 隐藏「快捷键」导航项，并为 `case 4` 加空白页兜底，避免触达桌面原生热键 API。
- 两个 `AppWindowTitleBar` 在 Android 返回 `SizedBox.shrink()`。

### 4.2 沉浸式全屏与方向

- `lib/main.dart` 启动时和 `AppLifecycleState.resumed` 时调用 `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`。
- Android 启动时通过 `SystemChrome.setPreferredOrientations` 锁定 `landscapeLeft` / `landscapeRight`；桌面端不受影响。

### 4.3 应用内整界面缩放

- `lib/main.dart` 内嵌 `_AndroidUiScaler`：
  - 在更大的逻辑画布上布局整棵 UI，再用 `OverflowBox + Transform.scale` 视觉缩小。
  - `transformHitTests: true`，点击坐标随变换一起缩放。
  - 没有独立 `lib/widgets/android_ui_scale.dart`，也没有 `AndroidUiScaleScope` / `AndroidScaleCompensator`。
- `lib/page/setting/settings_provider.dart`：
  - 键 `android_ui_scale`，默认 `0.72`，范围 `0.55–1.00`。
  - `setAndroidUiScale` clamp 后写入 `SharedPreferences` 并通知界面。
- `lib/page/setting/tabs/general_tab.dart`：设置 → 常规 → 「界面缩放」，Slider 范围 `0.55–1.00`，9 档，拖动即时写设置。
- 桌面平台完全不使用这套缩放。

### 4.4 播放页适配

- `lib/page/song_detail_page.dart`：
  - 按 `MediaQuery.size` 面积计算桌面原布局的 `scale`。
  - 横屏沿用桌面双栏关系；页面内保留 `isPortrait` 判断与竖屏单栏歌词 + 底部 `PortraitPlaybar` 分支。
  - 没有 `portraitBoost`、没有播放页二次缩放补偿。
  - 标题栏仍由 `AppWindowTitleBar` 占位，Android 上该组件返回空。
- `lib/widgets/lyrics_widget.dart`：没有 `fontScale` 参数，沿用上游按窗口尺寸计算的字号与行距。
- `lib/main.dart` 的 `didChangeAppLifecycleState` 只处理 `resumed` 时重新应用沉浸式模式；没有 `detached` 时的媒体会话停止逻辑。

### 4.5 SAF 与触屏

- `ci/MainActivity.kt`：
  - MethodChannel `myune_music_android/saf` 提供 `pickDirectoryTree`、`listAudioFiles`、`readBytes`。
  - `ACTION_OPEN_DOCUMENT_TREE` 请求持久化读权限；`takePersistableUriPermission` 保留授权。
  - BFS 递归遍历目录树，最多 20000 个文档，按 MIME 或扩展名筛选音频。
  - `readBytes` 最多读取 24 MiB，用于私有缓存副本。
- `lib/services/android_content_resolver.dart` 是 Dart 侧唯一 SAF 适配层，提供 `pickDirectoryTree`、`listAudioFiles`、`readBytes`、`cachePathForRead`、`displayName`。
- `lib/widgets/hover_overlay_control.dart`：Android 禁用鼠标 hover 自动隐藏，改为点击展开 / 再次点击关闭浮层。
- `lib/widgets/volume_control_state.dart`：Android 音量浮层是横向 Slider 加 `-` / `+` 按钮；桌面原逻辑不变。
- `lib/layout/main_view.dart`：宽屏横屏把歌曲详情固定成右栏 detail pane；窄屏保持原 Navigator 行为。

### 4.6 CI 构建

- 固定 Flutter `3.47.5`、Java 21、compileSdk 36、build-tools 36.0.0、NDK `28.2.13676358`、CMake `3.22.1`。
- 用 `flutter create --platforms=android --org com.midihl --project-name myune_music_android --android-language kotlin --no-pub .` 生成 runner；备份并恢复 `pubspec.lock`，避免 Flutter 3.47.5 的 `create` 把锁文件重写成空壳。
- 把 `ci/MainActivity.kt` 注入到生成的 runner：`android/app/src/main/kotlin/com/midihl/myune_music_android/MainActivity.kt`。
- 对齐 vendored cargokit Gradle 9 API、`file_picker 10.2.0` 和 `rust_builder/android` 的旧 compileSdk；旧插件 Kotlin JVM target 校验降级为 warning。
- 幂等注入 `android.permission.INTERNET`；媒体会话权限由 `mpv_audio_kit` Manifest 合并带入。
- 默认 debug 签名；四个 secrets 齐全时生成 `android/key.properties` 并切到正式 release signingConfig。
- 回档基线原本只出 arm64-v8a；本轮新增 matrix：
  - `arm64-v8a` / `android-arm64` / `myune-music-android-arm64` → `myune-music-arm64-v8a-release.apk`
  - `armeabi-v7a` / `android-arm` / `myune-music-android-armv7` → `myune-music-armeabi-v7a-release.apk`
- 每个 job 只编译一个 target-platform，避免 Rust/cargokit 与 libmpv 下载任务在多 ABI 下互相覆盖产物；上传前检查对应 ABI 的 `libmpv.so` 与 `librust_lib_myune_music.so`。

## 5. 11 点左右提出问题的结论

**现在改得是越改越垃圾了，完全没法用，放弃了。甚至问题比原本的多得多。**

## 6. 已知限制与风险

- 应用内缩放使用 `main.dart` 内嵌的 `Transform.scale` + 逻辑画布；没有播放页补偿层。
- Android 启动时锁定横屏方向。
- 音量控件在 Android 是横向 Slider + `+/-`；桌面端保持原实现。
- Android 播放页 `AppWindowTitleBar` 返回空；宽屏横屏走 `MainView` 的 master-detail 布局。
- 外置同目录 `.lrc` 的 SAF 关联、ReplayGain 写回、按修改日期排序对 `content://` 的精确时间支持未增强。
- `mpv_audio_kit` 构建时按 ABI 下载预编译 `libmpv.so`（release `libmpv-r13`），CI 需要外网访问 GitHub Releases；若 APK 缺少 `.so`，检查构建日志中的 SHA-256 校验段。
- `rust_builder/android/build.gradle` 源自 FRB 2.10.0 的 AGP 7.3 / compileSdk 33 模板，Gradle 依赖解析由 app runner 的 AGP 9.1 主导；若出现不兼容，优先统一 app runner 版本。
- 每个 matrix job 独立生成 debug keystore，两个 ABI 的签名证书通常不同；覆盖安装遇到签名冲突时先卸载旧测试包。切换正式签名时同样先卸载 debug 测试包。
- workflow 的 `.so` 检查对两个库分别使用 `grep -F` 且没有 `|| true`；任一必需库缺失会让对应 job 明确失败，便于定位。

## 7. 签名

当前阶段使用 debug 签名，可直接安装测试，不需要正式 keystore。若后续切换正式签名，在 GitHub 仓库 `Settings → Secrets and variables → Actions` 添加四个 secrets：

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` 的输出 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | key 密码 |
| `ANDROID_KEY_ALIAS` | key alias |

四个值齐全后 workflow 自动把 release `signingConfig` 从 debug 切到正式 keystore；任何一项缺失都保持 debug。debug 与正式签名 APK 不能覆盖安装。

## 8. 本机静态检查方式

本机没有 Flutter / Dart / Rust / NDK / kotlinc，按约定使用：

```bash
git diff --check
python - <<'PY'
import yaml
from pathlib import Path
yaml.safe_load(Path('.github/workflows/build_android.yml').read_text(encoding='utf-8'))
print('workflow yaml ok')
PY
```

以及 Dart / Kotlin 括号平衡、workflow 内嵌 Python 脚本 `compile()` 与模拟执行、CI 日志 / Artifact 下载校验。真正的编译和 APK 校验全部交给 GitHub Actions。

## 9. 构建与交付

### 9.1 历史基线

`558a71f` 对应的历史 Actions run 是 `42126221458`，结论 `success`，只出 arm64：

- Artifact：`myune-music-android-arm64`，ID `13461727050`
- zip：41,922,438 bytes，SHA-256 `58d32b25fb23205a2fd5aa371d1c4d41b904a80f3ab4c0f0d00519e4dba5035b`
- APK：`app-release.apk`，约 71 MB，SHA-256 `b4d6f16bad441f04d9e8e5ac37589a0bba2b3bd972f44cea5cdfb59f14dd4027`
- 签名：`C=US, O=Android, CN=Android Debug`，证书 SHA-256 `2f4fd0d8b5e7ba2a6351038b21fa4c1416104bf408c25fcfbcffdb9cdbfdd74b`

更早构建：

- `42059743949`：验证首个启动与播放链路。
- `42126221458`：加入沉浸式全屏、整界面缩放、SAF、触屏适配，即本次回档基线。

### 9.2 本轮重新编译产物

> 占位：推送回档到 `558a71f` 后重新编译，CI 完成后回填 Actions run、两个 matrix job 的结论、Artifact ID / 下载入口、zip / APK 大小与 SHA-256、签名证书 SHA-256、`.so` 清单。

上一轮 `42226182533` 编译的是 `a28f2c9` + 双 ABI workflow，不是本次目标版本；其 Artifact 不作为本轮交付依据。

## 10. 真机回归清单

1. 分别安装 `myune-music-arm64-v8a-release.apk` 与 `myune-music-armeabi-v7a-release.apk`；覆盖安装遇签名冲突时先卸载旧测试包。
2. 首次启动进入主界面，不闪退、不黑屏，不提示 Rust / libmpv 加载失败。
3. 设置页不出现「快捷键」入口；状态栏与手势导航条默认隐藏；记录方向是否按版本锁定横屏。
4. 设置 → 常规 → 「界面缩放」在 55% / 72% / 100% 下记录实际表现。
5. 添加音乐目录弹出 SAF 目录树授权；授权后递归扫描 `content://` 音频，重启 App 后仍可播放。
6. 点歌出声，暂停 / 继续 / 上一首 / 下一首、进度条、点击歌词跳转可用。
7. 切到后台继续播放；锁屏 / 通知栏 / 蓝牙媒体键可控制。
8. 记录播放中划掉最近任务后的声音、媒体会话和重新进入状态。
9. 记录设备型号、Android 版本、ABI、APK 签名者 SHA-256、通过 / 失败项。
10. 若出现问题，按用户指定结论记录，不在本轮继续扩展修复。

## 11. 许可证与发布前清单

主体代码沿用上游 Apache-2.0，详见根目录 `LICENSE`；本移植对其做了改动并在 `ANDROID_PORT_README.md` 记录。字体 MiSans 由小米提供，免费商用但版权仍归小米，许可链接见上游 `README.md`。

`mpv_audio_kit` 自身的 Dart/Kotlin 封装为 BSD-3-Clause；它打包的 `libmpv.so` 来自 mpv / FFmpeg 生态，包含 **GPL（以及可能的 LGPL）组件**。公开发布 APK 或把仓库改 public 前需完成：

1. 核对 `libmpv-r13` 中每个预编译库的实际许可证与构建配置；
2. 在发行物里附对应许可证全文、版权声明、NOTICE 与本移植的改动标注；
3. 提供对应 GPL 组件的完整源码或有效的书面源码获取方式，覆盖实际分发的二进制版本；
4. 若 FFmpeg 启用了 GPL 编解码器，按 GPL 而非 LGPL 处理整个分发链路。

因此本阶段目标仓库保持 **private**，Artifact 仅用于内部真机测试，不视为公开发行。

## 12. 给下一个执行者的边界

- 当前代码基线是 `558a71f` + 双 ABI workflow；不要擅自把 12:13 之后的 UI 修复、密度缩放、横屏重构、原生 DPI 缩放或挖孔主题带回来。
- 涉及 11 点问题时只按第 5 节结论记录，不主动扩展修复。
- 若需要新的技术方向、签名策略、仓库公开、正式发布或功能范围调整，先向用户列选项并等用户拍板。
- 编译继续走 GitHub Actions；本机只做静态检查、日志核查、Artifact 下载与哈希校验。
