// Package pair 与电视端的临时配对服务通信。
// 协议与电视版 google_drive_pairing.dart 的 /submit 完全一致：
//
//	POST http://<ip>:18780/submit
//	{"name","clientId","clientSecret","refreshToken","rootFolderId","pair"}
package pair

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Credentials 是提交给电视的载荷字段（JSON 命名必须与 Dart 端一致）。
type Credentials struct {
	Name         string `json:"name"`
	ClientID     string `json:"clientId"`
	ClientSecret string `json:"clientSecret"`
	RefreshToken string `json:"refreshToken"`
	RootFolderID string `json:"rootFolderId"`
	Pair         string `json:"pair"`
}

// Result 是电视端 /submit 的响应。
type Result struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

// NormalizePairURL 接受电视上显示的各种输入形式并返回规范化的配对地址：
//   - 完整二维码内容：http://192.168.1.20:18780/?pair=AB3D7K
//   - 只有 IP 或 IP:端口：192.168.1.20 / 192.168.1.20:18780
//   - 只粘贴 6 位配对码时，需要配合上次使用的地址（由 GUI 处理）
func NormalizePairURL(raw string) (string, string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", "", errors.New("请填写电视上的二维码内容或局域网地址")
	}
	if !strings.Contains(raw, "://") {
		raw = "http://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return "", "", fmt.Errorf("无法解析电视地址：%q", raw)
	}
	if u.Scheme != "http" {
		return "", "", errors.New("电视配对服务使用 http，不支持 " + u.Scheme)
	}
	if u.Port() == "" {
		u.Host = net.JoinHostPort(u.Hostname(), "18780")
	}
	pair := u.Query().Get("pair")
	if pair == "" {
		return "", "", errors.New("地址里没有 6 位配对码，请从电视上重新扫码（二维码内容带 ?pair=XXXXXX）")
	}
	// 只保留 scheme + host + /?pair=...，去掉其它无关参数。
	return u.Scheme + "://" + u.Host + "/?pair=" + url.QueryEscape(pair), pair, nil
}

// SubmitURL 由配对地址推出 /submit 端点。
func SubmitURL(pairURL string) (string, error) {
	u, err := url.Parse(pairURL)
	if err != nil {
		return "", err
	}
	u.Path = "/submit"
	return u.String(), nil
}

// Ping 检查电视配对服务是否可达（GET /ping）。
func Ping(ctx context.Context, pairURL string) error {
	u, err := url.Parse(pairURL)
	if err != nil {
		return err
	}
	u.Path = "/ping"
	u.RawQuery = ""
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("无法连接电视（确认与电视在同一 WiFi、配对页仍打开）：%w", err)
	}
	defer resp.Body.Close()
	return nil
}

// Submit 把凭据提交给电视；电视会当场用 refresh_token 校验并回显账号。
func Submit(ctx context.Context, pairURL string, c Credentials) (*Result, error) {
	if strings.TrimSpace(c.ClientID) == "" || strings.TrimSpace(c.RefreshToken) == "" {
		return nil, errors.New("client_id 与 refresh_token 不能为空")
	}
	if strings.TrimSpace(c.Pair) == "" {
		return nil, errors.New("缺少配对码")
	}
	endpoint, err := SubmitURL(pairURL)
	if err != nil {
		return nil, err
	}
	b, err := json.Marshal(c)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("无法连接电视配对服务：%w", err)
	}
	defer resp.Body.Close()
	var out Result
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("电视返回的响应无法解析（HTTP %d）：%w", resp.StatusCode, err)
	}
	if !out.OK {
		msg := out.Error
		if msg == "" {
			msg = fmt.Sprintf("HTTP %d", resp.StatusCode)
		}
		return &out, errors.New("电视拒绝了凭据：" + msg)
	}
	return &out, nil
}
