# 星音 StarNote · Google Drive 配对助手

电脑端图形化程序，用来协助电视登录 Google Drive 只读源。界面参考
[Kazumi](https://github.com/Predidit/Kazumi)：Material 3 深色配色、圆角卡片、
侧边导航 + 顶部栏。

**Go + Fyne**，纯 Go 业务逻辑 + 原生 GUI，无 WebView、无 Electron、无逐帧动画，
轻量且跨平台。手机端不需要额外 App，直接扫电视上的二维码打开配页即可
（配页已同步为同一套视觉风格）。

## 它做什么

与电视版 `tools/gdrive_auth.py` 的登录方式完全一致，只是加了图形界面和持久化设置：

1. **设置**：填 Google Cloud 的 `client_id` / `client_secret`（桌面应用类型）。
   启动时若未填，会**自动跳转到设置页并弹窗提示**；填好后**永久保存在本机**
   （`用户配置目录/gdrive-pair/config.json`，Unix 权限 0600）。
2. **获取授权**：点「打开浏览器授权」走标准 OAuth loopback
   （`scope=drive.readonly`、`access_type=offline`、`prompt=consent`），
   自动捕获回调；回调不通时也可以**直接粘贴授权码**换取 `refresh_token`。
3. **与电视配对**：把电视二维码内容或网址填进来（也可只填 6 位配对码，
   复用上次电视地址），点「与电视配对」把凭据 POST 到电视本机 `/submit`。
   电视会当场校验凭据并回显账号，按「完成」即可。

凭据**只提交到局域网里的这台电视**，不经过任何第三方服务；应用不联网上传配置。

## 一次性前提

- 电视能访问 Google；电脑/手机与电视在**同一 WiFi**。
- 在 [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
  创建「桌面应用」OAuth 客户端；同意屏幕启用 Drive API、加入
  `drive.readonly` 范围，并把自己的账号加进「测试用户」。

> Testing 状态签发的 `refresh_token` **7 天过期**（Google 官方规则）。
> 到期后重新打开电视的配对页，用同一份设置再跑一次「获取授权 + 配对」即可，
> `client_id` / `client_secret` 不用重填。应用会保存上次电视地址，配页只需换
> 新的 6 位配对码。

## 构建

### 本机（Linux / macOS / Windows）

需要 Go 1.23+ 与 C 编译器（Fyne 桌面端依赖 GLFW/OpenGL；Linux 还需
`libgl1-mesa-dev xorg-dev`）。

```bash
cd gdrive-pair
go mod tidy
make test                 # 纯 Go 业务包单元测试（无需 GUI 依赖）
make build                # 本机平台
```

产物：`bin/gdrive-pair`（Windows 为 `gdrive-pair.exe`）。

### 交叉编译 Linux x86_64 / ARM64 / Windows amd64

Fyne 推荐用官方 `fyne-cross`（Docker，内置交叉工具链与 mingw，宿主无需 CGO）：

```bash
go install github.com/fyne-io/fyne-cross@latest
make cross-amd64          # -> fyne-cross/bin/linux-amd64/
make cross-arm64          # -> fyne-cross/bin/linux-arm64/
make cross-windows        # -> fyne-cross/bin/windows-amd64/*.exe
```

CI（`.github/workflows/gdrive-pair.yml`）会在 push 时自动跑单元测试并产出
**Linux amd64 / Linux arm64 / Windows amd64** 三个可执行文件；发布版会作为
Release 附件提供，均为单文件绿色程序，无需安装。

## 为什么不做手机原生 App

手机端**沿用电视二维码打开的自包含配页**（已与电脑端同步为 Kazumi 风格），
不额外提供 Android/iOS 原生包，理由：

1. Google OAuth 客户端的创建（Cloud Console、同意屏幕加 `drive.readonly`、
   测试用户、桌面应用凭据）本身就是桌面浏览器流程，手机上操作极其繁琐；
2. 用户既然已在电脑上完成申请，顺势在同一台电脑完成授权与配对是自然延伸，
   无需再切到手机；
3. 手机侧保留扫码配页，已覆盖「身边只有手机」的兜底场景，不是功能空白；
4. 再维护一套 Fyne 移动端包需要 Android SDK/NDK、签名与侧载分发，收益远低于
   成本，也会让「轻量」这一前提失效。

## 目录结构

```
gdrive-pair/
  internal/config/   配置持久化（纯标准库，无 CGO，可单测）
  internal/oauth/    OAuth loopback + 授权码换 refresh_token
  internal/pair/     电视 /submit 协议（URL 规范化、Ping、提交）
  cmd/gdrive-pair/   Fyne GUI（Kazumi 风格主题 + 三个页面）
```

业务逻辑与 GUI 分离，因此 `go test ./internal/...` 在没有图形库、没有 CGO 的
环境里也能跑，适合 CI 快速回归。

## 电视端操作

网络媒体 → 网络硬盘 → **添加 Google Drive** → 扫码 / 复制网址 → 在本程序里
填网址完成授权与配对 → 电视按「完成」。
