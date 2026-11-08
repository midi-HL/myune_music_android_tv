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

- 代码提交：`a921a74` `Revert to 07:13 baseline and rebuild dual ABI APKs`。
- Actions run：`42234763869`，结论 `success`。
  - `build (arm64-v8a, android-arm64, myune-music-android-arm64)`：`success`，2026-11-06T14:32:06Z → 14:41:27Z。
  - `build (armeabi-v7a, android-arm, myune-music-android-armv7)`：`success`，2026-11-06T14:32:06Z → 14:41:59Z。
- CI annotation 只有 Node.js 20 / `setup-java@v4` / Ubuntu 26 迁移提示，与构建结果无关。

#### arm64-v8a / 64 位

- Artifact：`myune-music-android-arm64`，ID `13512820441`
- 下载：`https://github.com/midi-HL/myune_music_android/actions/runs/42234763869/artifacts/13512820441`
- zip：41,922,469 bytes，SHA-256 `55cb0610189a3ee7c145db2ba02a244b1a51942160b291fb5458a53406b5eaad`
- APK：`myune-music-arm64-v8a-release.apk`，73,754,354 bytes，SHA-256 `d84964810c23dd485de199237ac41f773b4f4bd32ae80fd846c3843bfa935c5e`
- 签名：`C=US, O=Android, CN=Android Debug`；证书 SHA-256 `7c1d21854b3372ec87c4b33cf9f1793a28b1ce71858f9a6d892202a71d510082`
- 已核对 `lib/arm64-v8a/libmpv.so`（8,318,304 bytes）与 `lib/arm64-v8a/librust_lib_myune_music.so`（1,900,736 bytes）

#### armeabi-v7a / 32 位

- Artifact：`myune-music-android-armv7`，ID `13511561424`
- 下载：`https://github.com/midi-HL/myune_music_android/actions/runs/42234763869/artifacts/13511561424`
- zip：41,361,216 bytes，SHA-256 `486c0c0515743ad59c4f62a882fa5af2193763e70c5e62978ac169389f73426c`
- APK：`myune-music-armeabi-v7a-release.apk`，71,231,224 bytes，SHA-256 `06eb7ab50d151d8b5da85f9de1ccf8cb1652028c2fa6a451b32e105450e6b3af`
- 签名：`C=US, O=Android, CN=Android Debug`；证书 SHA-256 `4235f6f574b8819e3f7549c312f53640db62e86b85446fe65ba9fee0a76ba0e4`
- 已核对 `lib/armeabi-v7a/libmpv.so`（8,171,192 bytes）与 `lib/armeabi-v7a/librust_lib_myune_music.so`（1,267,884 bytes）

两个包均为 debug 签名。每个 matrix runner 独立生成 debug keystore，两个 ABI 的证书不同；覆盖安装遇到签名冲突时先卸载旧测试包。

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

## 13. Android TV 适配（2026-11-08）

### 13.1 仓库与回滚

TV 工作改在**新仓库**进行，原仓库 `midi-HL/myune_music_android` 保持不动。

- 新仓库：`https://github.com/midi-HL/myune_music_android_tv`（private，`main` 为默认分支）。
- 本地新增 remote 别名为 `tv`；`origin` / `upstream` 未改动。
- 推送时携带了 `main` 的**完整 310 个提交**，未做 squash / 改写历史。
- 回滚锚点（tag 与提交一一对应）：

  | Tag | 提交 | 含义 |
  | --- | --- | --- |
  | `baseline-558a71f-0713` | `558a71f` | 11-06 07:13 回档基线，沉浸式 + 缩放 + SAF 首个可用版 |
  | `baseline-4168e51-pre-tv` | `4168e51` | TV 适配开始前的完整状态（双 ABI workflow + 交接文档） |

  回滚方式：`git checkout baseline-4168e51-pre-tv`（或在该 tag 上新建分支），
  也可用 `git revert <TV 提交>` 保留审计轨迹。两个 tag 均已推送到新仓库远端。

### 13.2 范围与文件

新增 `lib/tv/`：`tv_actions.dart`（逻辑动作）、`tv_key_map.dart`（Android 键值归一化）、
`tv_device.dart`（TV 判定）、`tv_settings.dart`（持久化）、`tv_gamepad_icons.dart`、
`tv_navigation.dart`（返回与抽屉）、`tv_focus.dart`（安全区 / 缩放 / 焦点 / 主题）、
`tv_input_scope.dart`（输入分发）、`tv_settings_tab.dart`（设置 UI）。

改动：`ci/MainActivity.kt`（TV 判定 + 按键事件广播，不吞键）、`lib/main.dart`、
`lib/layout/app_shell.dart`、`lib/page/setting/setting_page.dart`、
`lib/page/setting/tabs/general_tab.dart`、`.github/workflows/build_android.yml`。

同一 APK 自动识别 TV：设备非 TV 时所有新增代码路径均不生效，手机端的
0.72 缩放、横屏锁定、沉浸式、SAF 行为保持原样。SAF 目录树授权按用户要求保留不动。

### 13.3 输入设计

- 方向键 / OK / 回车 / 空格 / 字符输入**放行给 Flutter**，由焦点系统与文本输入处理；
  输入层不重复驱动，避免一次按键跳两格。Space 与 Enter 因此是「激活」而不是播放/暂停。
- 播放控制走媒体键、键盘功能键与手柄肩键；未带媒体键的遥控器通过
  方向键 + OK 的焦点控件完成全部操作，媒体键只是加速键。
- Xbox 与 PlayStation 手柄在 Android 上共用 `BUTTON_A/B/X/Y/L1/R1/L2/R2/START/SELECT`，
  按**物理位置**统一映射；设置 → 电视与输入 → 手柄图标可切换显示
  「自动识别 / Xbox / PlayStation」，仅影响图标，不影响功能。
- 非标准键值：设置页「学习模式」记录按下的任意 keyCode，可逐项绑定到逻辑动作，
  自定义映射优先于内置映射并持久化。厂商私有键值因此可被兼容，但**不承诺预置覆盖**。
- 返回键：`PopScope` + 320ms 去重统一处理系统 BACK、手柄 B 与键盘 Esc，
  先逐级关闭抽屉 / 对话框 / 播放页，主界面返回电视桌面。

### 13.4 CI 与 TV 桌面入口

在原有 Manifest 补丁步骤中幂等注入 `LEANBACK_LAUNCHER`、
`android.software.leanback` / `android.hardware.touchscreen` / `android.hardware.gamepad`
（均 `required="false"`，保证手机与电视都能装），并用标准库生成 320×180
`drawable-xhdpi/tv_banner.png`。两个 ABI job 都产出带 TV 入口的 APK，不新增独立包。

### 13.5 已知限制

- 海外标准 Android TV 为目标设备；国内盒子的私有键值依赖「按键学习」自行绑定。
- 媒体键若被 `mpv_audio_kit` 的 MediaSession 先行消费，`dispatchKeyEvent` 可能收不到；
  播放页焦点控件仍可完整操作。
- 拖拽排序（`ReorderableDragStartListener`）与右键菜单在纯遥控器下不可达，
  可用 `PopupMenuButton` 等可聚焦控件替代路径。
- 手柄 A / ✕ 若某些设备只上报 `KEYCODE_BUTTON_A` 而不上报 `DPAD_CENTER`，
  需在学习模式里把它绑定到「确认」类动作；标准 Android TV 设备通常已规范化。
- 本机无 Flutter / Dart / Kotlin 工具链，编译与 APK 校验全部交由 GitHub Actions。

## 14. 真机回归后的修复（2026-11-08 下午）

用户用海外标准 Android TV + 遥控器实测：`fc84dfe` 版本**所有界面方向键完全失效**（侧边栏、底部播放栏、播放页控制、歌词跳转、播放列表抽屉、音效设置弹窗、循环按钮、音频条），只能用鼠标；播放页开启动态背景后出现黑色移动色块；音量条被移植成横向 Slider + 加减键；歌词显示设置入口随窗口标题栏一起消失。

### 14.1 方向键失效的根因与修复

Flutter 在 Android 上确实把方向键绑定 `DirectionalFocusIntent`、`select/enter/space/gameButtonA` 绑定 `ActivateIntent`，默认策略 `ReadingOrderTraversalPolicy`；但 `DirectionalFocusAction` 使用 `primaryFocus?.inDirection(...)`。应用冷启动时 `primaryFocus` 是 `rootScope`，没有任何可遍历控件获得焦点，方向键全部空转，OK 键也无处激活。原 `TvInputScope` 只把方向键放行给 Flutter、未主动建立焦点，因此整条链路始终没有起点。

新增 `lib/tv/tv_focus_nav.dart`：

- `TvFocusScope`：TV 分支的 `Actions > Shortcuts > FocusTraversalGroup > Stack`，显式把四个方向键映射到自定义 `TvDirectionalFocusIntent`，由 `TvDirectionalFocusAction` 调用 `policy.inDirection()`；方向查找失败时退化为 `next/previous`。`Actions` 放在 `Shortcuts` 之上，保证自定义动作能被查找到。
- `TvFocusController`：启动、路由 `didPush/didPop`、抽屉打开后两帧自动把焦点落到真实控件；`findFirstFocus` + 基于 `FocusNode.children` 的焦点树遍历（含 `FocusScope` 的浮层 / 抽屉节点）；`ModalRoute.of(context)` 过滤对话框控件。
- `TvFocusNavigatorObserver`：挂到 `MaterialApp.navigatorObservers`，所有 `showDialog` / `showMenu` / 播放页路由自动聚焦。
- `TvFocusHighlight`：跟随 `primaryFocus` 真实 `RenderBox` 的全局焦点框（深色底描边 + 青色高亮），不依赖控件自身的 focused 样式，任何控件都看得见焦点。
- `TvFocusable`：给原本无 Focus 节点的控件补 `Focus` + `ActivateIntent` 回调。
- `TvOverlayRegistry`：返回键优先关闭 `OverlayEntry` 浮层，再逐级 `Navigator.maybePop()`。
- `main_view.dart`：TV 分支改用自建可聚焦侧边栏（每项 `TvFocusable`，第一项 `autofocus`），非 TV 继续用 `NavigationRail`。

`Shortcuts` 的层级高于输入框 / Slider 自身的 `Shortcuts`，因此文本光标移动与滑块调节仍由 Flutter 原生处理，不会被抢。播放页的「鼠标静止 5 秒隐藏控件」在 TV 上强制关闭，避免 `IgnorePointer` 让控件失去可达性。

### 14.2 音量条

`lib/widgets/volume_control_state.dart` 删除 Android 分支的横向 Slider + `-` / `+` 按钮，全平台恢复桌面端的 `RotatedBox(quarterTurns: -1)` 竖向 Slider + 数值显示。`lib/widgets/hover_overlay_control.dart` 在 TV 上：点一下音量图标展开竖条并自动把焦点交到 Slider（`autofocus` + `scheduleFocusWhere`），方向键上下调音量，返回键关闭；浮层登记到 `TvOverlayRegistry`。浮层内不再误触静音。

### 14.3 歌词显示设置入口

`LyricsSettingsDrawer` 一直挂在 `SongDetailPage` 的 `Scaffold.drawer`，但桌面端入口在 `AppWindowTitleBar`，而该组件在 Android 返回 `SizedBox.shrink()`，导致入口消失。现在在 `lib/widgets/song_detail_page/playbar.dart` 横屏与竖屏的控制排都与启停 / 上一首下一首同一排补上「歌词显示设置」按钮（`Icons.text_format`），点击 `openDrawer()` 并自动聚焦抽屉；TV 上抽屉宽度放宽到 420。

### 14.4 播放页黑色移动色块

根因是 `song_detail_page.dart` 的 `MeshGradient`（`mesh_gradient: ^1.3.8`）由 `AnimationController.repeat(reverse: true)` 每帧重建 4 个近黑色点，在 Android TV GPU 上产生移动黑块；歌词与封面是上层 child 所以正常。TV 分支强制 `enableDynamicBackground = false` 并停止动画，静态背景也跳过 `ImageFiltered`/大半径 blur，改用降亮度封面 + 遮罩层；桌面 / 手机端保留 40 sigma 高斯模糊与动态背景。

### 14.5 应用名与图标

- 显示名定为 **星音 StarNote**（用户选定），由 workflow 注入 `android:label`，手机与 TV 桌面共用。
- 原项目图标是深蓝圆底 + 白色八分音符 + 四角星芒（`logo.png` 1024²、`icon.png` 430² 单色版）。据此重新生成并提交 `ci/branding/`：`tv_banner.png`（320×180，含中文名与英文名）、5 个密度的 `ic_launcher*.png` / `ic_launcher_round*.png`。
- workflow 在生成 runner 后复制这些资源、删除模板 `mipmap-anydpi-v26/*.xml`（避免 Adaptive Icon 覆盖品牌图标），并校验注入结果。

### 14.6 回滚

`baseline-4168e51-pre-tv` 与 `baseline-558a71f-0713` 两个 tag 不变；本节改动是 `fc84dfe` 之后的新提交，可用 `git revert <新提交>` 回到 `fc84dfe`（第一版 TV，方向键不可用），或直接 checkout 上述 tag 回到移植前。

## 15. 第三轮真机回归修复（2026-11-08 晚）

用户再次用真机 + 遥控器回归，指出第 14 节方案仍有多处不符合预期，并明确要求只修「目前说明的 bug」。
本节**覆盖第 14 节中与之冲突的描述**：14.1 的全局 `TvFocusHighlight` 与
`ReadingOrderTraversalPolicy.inDirection() + next()/previous()` 兜底、14.4 的
「TV 上禁用动态背景 / 降亮度封面」均已作废。

### 15.1 本轮反馈与对应处理

| 反馈 | 处理 |
| --- | --- |
| 原版没有额外亮框，现在出现两个高亮框；设置菜单初次进入整栏被框住；界面像被大改 | 删除 `TvFocusHighlight` 全局焦点框与 `applyTvFocusTheme()`，`main.dart` 恢复 `themeProvider.lightThemeData / darkThemeData`；焦点高亮只用 Material / Android 原生样式 |
| 设置里「安全边框 / 过扫描安全边距」不合理，正常电视不需要 | 删除 `TvSafeArea`、`tv_overscan` 持久化字段与设置页「过扫描安全边距」Slider；`main.dart` 的 TV builder 不再包裹安全区 |
| 方向键逻辑反直觉：视觉上左右却跳到上下 | 重写 `TvFocusController.moveFocus()` 为严格几何方向查找，按 `RenderBox` 全局 `Rect.center` 只在对应半平面找最近控件，不做阅读顺序兜底；找不到就不移动 |
| 侧边栏能操作但条件严苛，很难到最右侧栏 / 侧边控件；旁边框里全部控件要能鼠标或触控控制 | 保留自建 TV rail，每项加 `MouseRegion + GestureDetector.onTap`，与 OK 键 `onActivate` 共用同一个 `onSelect` |
| 音频 / 歌曲进度条四个方向键都被 Slider 吞掉，焦点卡死，只能鼠标拖出；播放页同样 | 新增 `TvPointerOnlySlider`（`canRequestFocus:false` + `skipTraversal` + `descendantsAreFocusable/Traversable:false`），TV 上把进度条从键盘焦点链排除，保留鼠标 / 触控拖动；快进快退仍由媒体键与手柄扳机承担 |
| 播放页动态背景被「修没了」，只剩封面降亮度，没有模糊与动态 | 按用户要求**直接还原原代码**：`enableDynamicBackground = settings.enableDynamicBackground`、`MeshGradient` 动画、静态 `ImageFiltered(sigmaX/Y: 40)` 全部恢复；黑块暂不修（用户明确「短时间内修不好就先不修」） |
| 音量调节里有文字提示，正常人都知道怎么用 | 删除 `↑↓ 调音量 · 返回关闭` 提示文字，保留竖向 Slider 与数值 |
| 关闭浮层后焦点落空 | `HoverOverlayControl._removeOverlay()` 在 TV 上调度 `scheduleEnsureFocus()`，重新给方向键找起点 |

### 15.2 严格空间导航实现要点

- `TvDirectionalFocusAction.invoke()` 不再调用 `policy.inDirection()`；改为 `TvFocusController.instance.moveFocus(direction, node)`。
- `moveFocus()` 用 `collectCandidates(rootScope)` 收集所有可聚焦控件（沿 `FocusNode.children` 递归，含 `FocusScopeNode`），按 `rectOf()` 取全局 `Rect`；按左 / 右 / 上 / 下四个半平面过滤，`score = 主方向距离 + 副方向偏移 × 2`。
- 跳过整页级大容器（宽 ≥ 92% 且高 ≥ 88%）、包住当前控件的祖先容器，并限定同一 `enclosingScope`，避免焦点跑到抽屉 / 弹窗背后。
- `_pickLeaf()` 选面积最小的可聚焦控件，避免焦点落到整页容器导致「整个界面被框住」。
- 输入框焦点时返回 `KeyEventResult.ignored`，让 `EditableText` 自己的 Shortcuts 处理光标（返回 null 会被 Shortcuts 当成 handled 吞键）。

### 15.3 Slider 覆盖清单

除音量竖条外，所有 `Slider` 在 TV 上都由 `TvPointerOnlySlider` 包裹：
主界面底部进度条、播放页横屏 / 竖屏进度条、TV 设置「界面缩放」、
歌词显示设置 4 个滑块、音效 / 均衡器 2 个滑块、主题配色 1 个、
自定义背景 3 个、常规设置 1 个（手机分支，TV 不构建但保持一致）。
音量竖条按用户要求保留键盘焦点（上下调音量、返回键退出），不包裹。

### 15.4 复核与回滚

- 静态复核 51/51 通过：括号平衡、Slider 包裹覆盖、已删除项残留、import 路径、关键行为断言。
- 提交 `af37e16`（第三轮修复）。回滚：`git revert af37e16` 回到 `096355a`（第二轮），
  或 checkout `tv-v2-focus-fix`；更早基线仍是 `baseline-4168e51-pre-tv` / `baseline-558a71f-0713`。

---

## 16. 第四轮真机回归修复（2026-11-08 晚，5 张截图）

本轮只处理用户 5 张截图列出的问题，不扩展其它工作。**本节覆盖第 15 节中已作废的描述**：
15.2 的「限定同一 `enclosingScope`」、15.3 的「音效 / 均衡器滑块由 `TvPointerOnlySlider` 包裹」不再成立。

### 16.1 用户确认的三点澄清

| 问题 | 用户确认 |
| --- | --- |
| 第一张图「下面还有更多可选项……不会自己往下拉」 | 方向键把焦点移到被弹窗裁在可视区之外的选项时，弹窗内容自动滚动把焦点露出来（自动滚动） |
| 第四张图「要多加个返回的功能」 | 返回键等同 ✕ 关闭 |
| 第二、三张图要补的高亮 | 原生式背景高亮（**不要描边框**，不叠加双重高亮） |

### 16.2 反馈与处理

| 反馈 | 处理 |
| --- | --- |
| 第五张图（最严重）：红圈与绿圈像两个不同图层，焦点只在红圈时不能移到绿圈；例如焦点在底部「切换播放方式」按钮按上进不了内容区那三首歌，继续按反而跳到「设置」；专辑 / 歌手界面同样 | `moveFocus()` 删除 `candidate.node.enclosingScope != scope` 硬过滤。改为 `_modalLayerOf()`：仅 `Drawer` / `PopupRoute`（Dialog、菜单、BottomSheet）算模态浮层，浮层打开时把焦点锁在该层内；主界面允许跨越左侧栏、内容区 `Navigator` 页面、底部播放栏等不同 `FocusScope` 按几何方向自由移动 |
| 第一张图：音效设置「音高 / 速度」遥控器到不了 | 新增 `TvAdjustableSlider`：用一层可聚焦的 `Focus` 包住原 `Slider`，`descendantsAreFocusable:false` 让 Slider 内部会吞四向键的 Focus / Shortcuts 退出焦点链；水平滑块 `←/→` 调值、`↑/↓` 放行给全局几何导航离开，竖向频段滑块 `↑/↓` 调值、`←/→` 离开。音效弹窗的音高、倍速、均衡器频段改用它；鼠标 / 触控拖动仍走原 `Slider` |
| 第一张图：下方更多可选项焦点到了但内容不自动往下拉 | `moveFocus()` 的候选判定区域在滚动方向放宽上下各一屏（`scrollReach`），允许焦点落到被裁切选项；焦点落定后用 `Scrollable.ensureVisible()` 把它滚进可视区 |
| 第二张图：底部专辑封面焦点无高亮 | `playbar.dart` 的 `FilledButton` 用 `WidgetStateProperty.resolveWith` 在 `WidgetState.focused` 时把背景向 `primary` 插值 32%，并加 `overlayColor`；不画描边框 |
| 第三张图：侧边栏焦点完全无高亮，原版有 | 新增 `TvFocusHighlight`（`StatefulWidget` + 自有 `FocusNode` + 聚焦时 `setState`）；TV rail 每项改用它，`_TvRailItem` 增加 `focused` 参数，聚焦时叠加 `primary` 30% 半透明背景（`AnimatedContainer`），不画描边框。外层 `MouseRegion + GestureDetector.onTap` 保留，鼠标 / 触控仍可操作 |
| 第四张图：「正在播放」抽屉返回键不能像 ✕ 一样关闭 | `TvBackHandler.handle()` 分层：浮层栈 → 显式关闭 `endDrawer` / `drawer`（含播放页自己 Scaffold 上的歌词设置抽屉，用 `focusableContexts()` + `Scaffold.maybeOf` 定位）→ `navigator.maybePop()` → `SystemNavigator.pop()`。不再依赖 `maybePop()` 返回值：`PopScope(canPop:false)` 会把它变成空操作，改用 `TvFocusNavigatorObserver.popCount` 判断是否真的关闭了 route；加 `_handling` 重入保护。关闭抽屉后 `scheduleRestoreFocus()` 强制重选焦点 |
| 原生控件焦点态整体偏弱 | `TvFocusScope.initState()` 设置 `FocusManager.instance.highlightMode = FocusHighlightMode.traditional`，让 Material 原生焦点态正常显示；仍不叠加全局自定义主题与描边框 |

### 16.3 进度条与设置滑块的分工

- **进度条**（主界面底部、播放页横屏 / 竖屏）继续用 `TvPointerOnlySlider`，不参与键盘焦点遍历，避免四向键被吞；快进 / 快退仍由媒体键与手柄扳机承担。
- **音量竖条**继续保留键盘焦点（上下调音量、返回键退出），不包裹。
- **音效设置滑块**改用 `TvAdjustableSlider`。
- 其它设置页滑块（界面缩放、歌词显示设置、主题配色、自定义背景、常规设置）本轮**按用户当前交代的范围保持 `TvPointerOnlySlider` 不变**，仍可用鼠标 / 触控；若后续要求遥控器也能调这些值，再统一替换。

### 16.4 验证方式与已知限制

- 静态复核 62/62 通过：括号平衡、关键行为断言、已删除项残留、import 覆盖、进度条 / 音量条 / 动态背景 / 过扫描等回归项。
- 本机按用户要求**不再控制真机电视**；曾尝试安装 Android TV 模拟器，已装好 SDK 命令行工具、emulator、Android TV 系统镜像并创建 AVD，但本机 Windows Hypervisor Platform / AEHD 未启用且会话非管理员，x86_64 镜像无法启动、ARM64 镜像被 QEMU 拒绝，用户随后明确要求放弃模拟器安装。**因此本轮没有真机 / 模拟器 UI 实测**，需用户在真机回归。
- 提交：见 `git log` 中 `android/tv: round-4` 开头的提交；回滚用 `git revert <该提交>`，或 checkout `tv-v3-focus-fix` / `baseline-4168e51-pre-tv`。
