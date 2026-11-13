// Package oauth 按星音电视版现有的 Google Drive 登录方式完成 OAuth。
// 与 tools/gdrive_auth.py 完全同构：桌面应用 loopback 回调、
// scope=drive.readonly、access_type=offline、prompt=consent。
package oauth

import (
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

const (
	AuthURL     = "https://accounts.google.com/o/oauth2/v2/auth"
	Scope       = "https://www.googleapis.com/auth/drive.readonly"
	RedirectURI = "http://127.0.0.1:53682/"
	ListenAddr  = "127.0.0.1:53682"
)

// TokenURL 单独用 var，方便单元测试用 httptest 替换端点。
var TokenURL = "https://oauth2.googleapis.com/token"

// Tokens 是 token 端点返回的结果；我们只需要 refresh_token 长期保存。
type Tokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	TokenType    string `json:"token_type"`
}

// NewState 生成一次性 state，防止 CSRF。
func NewState() string {
	// 用纳秒时间 + 随机端口占用情况做简单熵；state 只用于本地回环校验。
	return fmt.Sprintf("%d", time.Now().UnixNano())
}

// AuthURLFor 生成浏览器授权地址。
func AuthURLFor(clientID, state string) string {
	q := url.Values{
		"client_id":     {clientID},
		"redirect_uri":  {RedirectURI},
		"response_type": {"code"},
		"scope":         {Scope},
		"access_type":   {"offline"},
		"prompt":        {"consent"},
		"state":         {state},
	}
	return AuthURL + "?" + q.Encode()
}

// StartLoopback 在 127.0.0.1:53682 起一个临时服务，等待浏览器回调。
// 返回的 channel 只投递一次授权码；ctx 取消或超时会关闭服务。
func StartLoopback(ctx context.Context, state string) (<-chan string, func(), error) {
	lc := net.ListenConfig{}
	ln, err := lc.Listen(ctx, "tcp", ListenAddr)
	if err != nil {
		return nil, nil, fmt.Errorf("无法监听 %s（端口可能被占用）: %w", ListenAddr, err)
	}
	ch := make(chan string, 1)
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if q.Get("state") != state {
			http.Error(w, "state 校验失败", http.StatusBadRequest)
			return
		}
		if e := q.Get("error"); e != "" {
			http.Error(w, "授权被拒绝："+e, http.StatusBadRequest)
			return
		}
		code := q.Get("code")
		if code == "" {
			http.Error(w, "未收到授权码", http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte("<html><meta charset='utf-8'><body style='font:16px sans-serif;padding:40px'>授权完成，可以关闭本页并回到应用。</body></html>"))
		select {
		case ch <- code:
		default:
		}
	})
	srv := &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	go func() { _ = srv.Serve(ln) }()
	stop := func() {
		c, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		_ = srv.Shutdown(c)
	}
	go func() {
		<-ctx.Done()
		stop()
	}()
	return ch, stop, nil
}

// Exchange 用授权码（浏览器自动回调或手动粘贴）换 refresh_token。
func Exchange(ctx context.Context, clientID, clientSecret, code string) (*Tokens, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return nil, errors.New("授权码不能为空")
	}
	form := url.Values{
		"code":         {code},
		"client_id":    {clientID},
		"grant_type":   {"authorization_code"},
		"redirect_uri": {RedirectURI},
	}
	if s := strings.TrimSpace(clientSecret); s != "" {
		form.Set("client_secret", s)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, TokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("无法连接 Google 账号服务：%w", err)
	}
	defer resp.Body.Close()
	var body struct {
		Tokens
		Error       string `json:"error"`
		Description string `json:"error_description"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("解析 Google 响应失败：%w", err)
	}
	if resp.StatusCode != http.StatusOK || body.Error != "" {
		// 保留 error code（如 invalid_grant），应用据此提示「授权已过期，
		// 请重新配对」；description 作为补充说明。
		msg := body.Error
		if body.Description != "" {
			msg = body.Error + ": " + body.Description
		}
		return nil, fmt.Errorf("换取令牌失败（HTTP %d）：%s", resp.StatusCode, msg)
	}
	if body.RefreshToken == "" {
		return nil, errors.New("Google 未返回 refresh_token，请确认已把账号加入测试用户、scope 为 drive.readonly，并在授权页重新同意离线访问")
	}
	return &body.Tokens, nil
}
