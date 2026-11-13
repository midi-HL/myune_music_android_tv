// gdrive-pair 是星音 TV 版 Google Drive 只读源的电脑端配对助手。
//
// 流程与电视版现有的 tools/gdrive_auth.py 完全一致：
//  1. 设置页填 Google OAuth client_id / client_secret（缺失时启动自动跳转）；
//  2. 浏览器完成 OAuth（或直接粘贴授权码）换 refresh_token；
//  3. 输入电视二维码内容 / 局域网地址，POST 到电视的 /submit 完成配对。
//
// 界面参考 Kazumi：Material 3 深色配色、圆角卡片、侧边导航 + 顶部栏。
// 业务逻辑在 internal/ 下的纯 Go 包，GUI 层只负责呈现。
package main

import (
	"context"
	"fmt"
	"net/url"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/widget"

	"github.com/midi-HL/myune_music_android/gdrive-pair/internal/config"
	"github.com/midi-HL/myune_music_android/gdrive-pair/internal/oauth"
	"github.com/midi-HL/myune_music_android/gdrive-pair/internal/pair"
)

type ui struct {
	app    fyne.App
	window fyne.Window

	cfg          config.Config
	refreshToken string
	lastPairURL  string

	// 设置页
	clientID     *widget.Entry
	clientSecret *widget.Entry
	sourceName   *widget.Entry
	rootFolderID *widget.Entry

	// 授权页
	codeEntry  *widget.Entry
	refreshLbl *widget.Label
	authHint   *widget.Label

	// 配对页
	pairEntry *widget.Entry

	// 全局日志（只挂在底部一次，避免同一 widget 被多个页面复用）
	status  *widget.Label
	logBox  *widget.Entry
	logPane fyne.CanvasObject

	content *fyne.Container
	navBtns []*widget.Button
	pages   map[string]fyne.CanvasObject
}

func main() {
	a := app.NewWithID("com.midihl.gdrivepair")
	a.Settings().SetTheme(newKazumiTheme())
	w := a.NewWindow("星音 StarNote · Google Drive 配对助手")
	w.Resize(fyne.NewSize(900, 660))

	u := &ui{app: a, window: w, pages: make(map[string]fyne.CanvasObject)}
	u.cfg, _ = config.Load()
	u.lastPairURL = u.cfg.LastPairURL
	u.build()
	w.SetContent(u.root())
	u.requireGoogleInfoOnStart()
	w.ShowAndRun()
}

func (u *ui) log(format string, args ...any) {
	line := fmt.Sprintf(format, args...)
	u.logBox.SetText(u.logBox.Text + line + "\n")
	u.status.SetText(line)
}

func (u *ui) showErr(err error) {
	u.log("错误: %v", err)
	dialog.ShowError(err, u.window)
}

// ---------- 页面构建 ----------

func (u *ui) build() {
	u.status = widget.NewLabel("准备就绪")
	u.logBox = widget.NewMultiLineEntry()
	u.logBox.SetPlaceHolder("操作日志…")
	u.logBox.SetMinRowsVisible(5)
	u.logPane = widget.NewCard("日志", "", container.NewVBox(u.logBox, u.status))

	u.buildSettings()
	u.buildAuthorize()
	u.buildPair()
}

func (u *ui) buildSettings() {
	u.clientID = widget.NewEntry()
	u.clientID.SetPlaceHolder("xxxxxxxx.apps.googleusercontent.com")
	u.clientSecret = widget.NewPasswordEntry()
	u.clientSecret.SetPlaceHolder("GOCSPX-... （桌面应用类型可留空）")
	u.sourceName = widget.NewEntry()
	u.sourceName.SetPlaceHolder("我的 Google Drive")
	u.rootFolderID = widget.NewEntry()
	u.rootFolderID.SetPlaceHolder("留空 = 我的云端硬盘")

	form := widget.NewForm(
		widget.NewFormItem("OAuth client_id *", u.clientID),
		widget.NewFormItem("client_secret", u.clientSecret),
		widget.NewFormItem("源名称", u.sourceName),
		widget.NewFormItem("根文件夹 ID", u.rootFolderID),
	)
	card := widget.NewCard("Google Cloud 凭据", "只保存在本机，不会上传到任何服务器", form)

	hint := widget.NewLabel(
		"在 Google Cloud Console 创建「桌面应用」OAuth 客户端；\n" +
			"同意屏幕启用 Drive API、加入 drive.readonly 范围，\n" +
			"并把你的账号加进「测试用户」。\n" +
			"Testing 状态签发的 refresh_token 7 天过期，届时重新授权即可。")
	hint.Wrapping = fyne.TextWrapWord

	save := widget.NewButton("保存设置", func() {
		u.cfg.ClientID = strings.TrimSpace(u.clientID.Text)
		u.cfg.ClientSecret = strings.TrimSpace(u.clientSecret.Text)
		u.cfg.SourceName = strings.TrimSpace(u.sourceName.Text)
		if u.cfg.SourceName == "" {
			u.cfg.SourceName = config.Default().SourceName
		}
		u.cfg.RootFolderID = strings.TrimSpace(u.rootFolderID.Text)
		if err := u.cfg.Validate(); err != nil {
			u.showErr(err)
			return
		}
		if err := config.Save(u.cfg); err != nil {
			u.showErr(err)
			return
		}
		u.log("设置已永久保存")
		dialog.ShowInformation("已保存", "设置已保存，下次启动不会再次询问。", u.window)
	})
	save.Importance = widget.HighImportance

	u.pages["settings"] = container.NewVBox(card, hint, save, layout.NewSpacer())
	u.syncSettingsFields()
}

func (u *ui) syncSettingsFields() {
	u.clientID.SetText(u.cfg.ClientID)
	u.clientSecret.SetText(u.cfg.ClientSecret)
	u.sourceName.SetText(u.cfg.SourceName)
	u.rootFolderID.SetText(u.cfg.RootFolderID)
}

func (u *ui) buildAuthorize() {
	u.codeEntry = widget.NewEntry()
	u.codeEntry.SetPlaceHolder("浏览器回调失败时，把授权码粘贴到这里")
	u.refreshLbl = widget.NewLabel("尚未获取 refresh_token")
	u.refreshLbl.Wrapping = fyne.TextWrapWord
	u.authHint = widget.NewLabel("第 1 步：先在「设置」里填好 Google 凭据，再点下面的按钮。")
	u.authHint.Wrapping = fyne.TextWrapWord

	openBrowser := widget.NewButton("1. 打开浏览器授权（自动捕获）", func() {
		u.startBrowserAuth()
	})
	openBrowser.Importance = widget.HighImportance
	manual := widget.NewButton("2. 用粘贴的授权码换取令牌", func() {
		u.exchange(u.codeEntry.Text)
	})

	card := widget.NewCard("获取 Google 授权", "scope = drive.readonly（只读），与电视版登录方式一致",
		container.NewVBox(
			u.authHint,
			openBrowser,
			widget.NewSeparator(),
			u.codeEntry,
			manual,
			widget.NewSeparator(),
			u.refreshLbl,
		))
	u.pages["authorize"] = container.NewVBox(card, layout.NewSpacer())
}

func (u *ui) buildPair() {
	u.pairEntry = widget.NewEntry()
	u.pairEntry.SetPlaceHolder("http://192.168.1.20:18780/?pair=AB3D7K")
	if u.lastPairURL != "" {
		u.pairEntry.SetText(u.lastPairURL)
	}
	hint := widget.NewLabel(
		"第 2 步：在电视上打开「添加 Google Drive」，把二维码内容或网址填进来。\n" +
			"也可以只填 6 位配对码（会使用上次连接的电视地址）。")
	hint.Wrapping = fyne.TextWrapWord

	ping := widget.NewButton("测试连接", func() {
		norm, _, err := u.resolvePairURL(u.pairEntry.Text)
		if err != nil {
			u.showErr(err)
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
		defer cancel()
		if err := pair.Ping(ctx, norm); err != nil {
			u.showErr(err)
			return
		}
		u.log("电视配对服务可达")
	})
	submit := widget.NewButton("与电视配对", func() { u.submitToTV() })
	submit.Importance = widget.HighImportance

	card := widget.NewCard("与电视配对", "凭据直接 POST 到电视本机，不经过第三方服务",
		container.NewVBox(
			hint,
			u.pairEntry,
			container.NewHBox(ping, submit),
		))
	u.pages["pair"] = container.NewVBox(card, layout.NewSpacer())
}

// ---------- 业务逻辑 ----------

func (u *ui) startBrowserAuth() {
	if err := u.cfg.Validate(); err != nil {
		u.showErr(err)
		u.show("settings")
		return
	}
	state := oauth.NewState()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	ch, stop, err := oauth.StartLoopback(ctx, state)
	if err != nil {
		cancel()
		u.log("无法启动本地回调: %v", err)
		u.showErr(fmt.Errorf("本地回调端口被占用，请改用「直接输入授权码」: %w", err))
		return
	}
	authURL := oauth.AuthURLFor(u.cfg.ClientID, state)
	parsed, err := url.Parse(authURL)
	if err != nil || u.app.OpenURL(parsed) != nil {
		stop()
		cancel()
		u.log("无法打开浏览器，请把下面地址复制到浏览器:\n%s", authURL)
		return
	}
	u.log("已在浏览器打开授权页，等待回调…")
	go func() {
		defer cancel()
		defer stop()
		select {
		case code := <-ch:
			u.exchange(code)
		case <-ctx.Done():
			u.log("等待授权超时，请重试或用「直接输入授权码」")
		}
	}()
}

func (u *ui) exchange(code string) {
	if err := u.cfg.Validate(); err != nil {
		u.showErr(err)
		u.show("settings")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	u.log("正在换取 refresh_token…")
	tok, err := oauth.Exchange(ctx, u.cfg.ClientID, u.cfg.ClientSecret, code)
	if err != nil {
		if strings.Contains(err.Error(), "invalid_grant") {
			u.log("授权码已失效（或 refresh_token 已过期），请重新授权")
		}
		u.showErr(err)
		return
	}
	u.refreshToken = tok.RefreshToken
	u.refreshLbl.SetText("已获取 refresh_token（" + mask(u.refreshToken) + "）")
	u.log("已获取 refresh_token，请继续「与电视配对」")
	dialog.ShowInformation("授权成功", "已获取 refresh_token，请继续「与电视配对」。", u.window)
	u.show("pair")
}

func mask(s string) string {
	if len(s) <= 10 {
		return "***"
	}
	return s[:6] + "..." + s[len(s)-4:]
}

// resolvePairURL 支持完整二维码内容、IP、以及只填 6 位配对码三种输入。
func (u *ui) resolvePairURL(raw string) (string, string, error) {
	raw = strings.TrimSpace(raw)
	if raw != "" && !strings.ContainsAny(raw, ":/?") && len(raw) <= 8 {
		if u.lastPairURL == "" {
			return "", "", fmt.Errorf("只填了配对码，但没有上次的电视地址；请填完整二维码内容")
		}
		base, err := url.Parse(u.lastPairURL)
		if err != nil {
			return "", "", err
		}
		raw = base.Scheme + "://" + base.Host + "/?pair=" + url.QueryEscape(raw)
	}
	return pair.NormalizePairURL(raw)
}

func (u *ui) submitToTV() {
	if u.refreshToken == "" {
		u.showErr(fmt.Errorf("请先在「获取授权」页拿到 refresh_token"))
		u.show("authorize")
		return
	}
	norm, code, err := u.resolvePairURL(u.pairEntry.Text)
	if err != nil {
		u.showErr(err)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	u.log("正在把凭据提交到电视…")
	_, err = pair.Submit(ctx, norm, pair.Credentials{
		Name:         u.cfg.SourceName,
		ClientID:     u.cfg.ClientID,
		ClientSecret: u.cfg.ClientSecret,
		RefreshToken: u.refreshToken,
		RootFolderID: u.cfg.RootFolderID,
		Pair:         code,
	})
	if err != nil {
		u.showErr(err)
		return
	}
	u.lastPairURL = norm
	u.cfg.LastPairURL = norm
	_ = config.Save(u.cfg)
	u.pairEntry.SetText(norm)
	u.log("配对成功，请回到电视按「完成」")
	dialog.ShowInformation("配对成功", "凭据已提交到电视。请回到电视按「完成」。", u.window)
}

// ---------- 外壳：顶部栏 + 侧边导航 + 底部日志 ----------

func navIndex(key string) int {
	switch key {
	case "settings":
		return 0
	case "authorize":
		return 1
	default:
		return 2
	}
}

func (u *ui) show(key string) {
	page, ok := u.pages[key]
	if !ok {
		return
	}
	u.content.Objects = []fyne.CanvasObject{page}
	u.content.Refresh()
	for i, b := range u.navBtns {
		if i == navIndex(key) {
			b.Importance = widget.HighImportance
		} else {
			b.Importance = widget.MediumImportance
		}
		b.Refresh()
	}
}

func (u *ui) root() fyne.CanvasObject {
	title := widget.NewLabelWithStyle("星音 StarNote", fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	sub := widget.NewLabel("Google Drive 配对助手")
	top := container.NewVBox(
		container.NewHBox(title, sub, layout.NewSpacer(), widget.NewLabel("只读 · 本机配对")),
		widget.NewSeparator(),
	)

	navKeys := []string{"settings", "authorize", "pair"}
	labels := []string{"设置", "获取授权", "与电视配对"}
	navObjs := make([]fyne.CanvasObject, 0, len(labels))
	for i, label := range labels {
		key := navKeys[i]
		b := widget.NewButton(label, func() { u.show(key) })
		u.navBtns = append(u.navBtns, b)
		navObjs = append(navObjs, b)
	}
	hint := widget.NewLabel("电视端:\n网络媒体 →\n网络硬盘 →\n添加 Google Drive")
	hint.Wrapping = fyne.TextWrapWord
	nav := container.NewVBox(
		container.NewPadded(container.NewVBox(navObjs...)),
		layout.NewSpacer(),
		container.NewPadded(hint),
	)

	u.content = container.NewStack()
	return container.NewBorder(top, u.logPane, nav, nil, container.NewPadded(u.content))
}

func (u *ui) requireGoogleInfoOnStart() {
	if u.cfg.IsGoogleInfoComplete() {
		u.show("authorize")
		u.log("已加载本机保存的 Google 凭据")
		return
	}
	u.show("settings")
	u.log("还没有填 Google 要求的 client_id，已自动跳转到设置页")
	dialog.ShowInformation("请先填写 Google 凭据",
		"需要先填写 OAuth client_id（和可选的 client_secret）。\n"+
			"填写并保存后会永久保存在本机，之后即可与电视配对。", u.window)
}
