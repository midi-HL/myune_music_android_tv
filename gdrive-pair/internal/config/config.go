// Package config 保存 Google OAuth 客户端凭据与配对偏好。
// 纯标准库实现，不依赖任何 GUI / CGO，便于在任意平台编译与测试。
package config

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// Config 是持久化到本机用户配置目录的设置。
// ClientID / ClientSecret 是 Google 要求的必填信息；缺失时 GUI 会自动
// 跳转到设置页并提示用户填写，填好后永久保存，下次启动不再询问。
type Config struct {
	ClientID     string `json:"client_id"`
	ClientSecret string `json:"client_secret"`
	SourceName   string `json:"source_name"`
	RootFolderID string `json:"root_folder_id"`
	// 上次成功配对使用的电视地址，方便下次少打字。
	LastPairURL string `json:"last_pair_url"`
}

// Default 返回一份可直接使用的默认配置。
func Default() Config {
	return Config{SourceName: "我的 Google Drive"}
}

// IsGoogleInfoComplete 判断 Google 要求的信息是否已填。
// client_secret 对「桌面应用」类型可留空（部分租户不强制），因此只校验
// client_id；与电视端 /submit 的校验条件保持一致。
func (c Config) IsGoogleInfoComplete() bool {
	return strings.TrimSpace(c.ClientID) != ""
}

// Validate 返回配置不合法的原因；合法时返回 nil。
func (c Config) Validate() error {
	if !c.IsGoogleInfoComplete() {
		return errors.New("请先填写 OAuth client_id")
	}
	return nil
}

// Path 返回配置文件路径：<用户配置目录>/gdrive-pair/config.json。
func Path() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "gdrive-pair", "config.json"), nil
}

// Load 读取配置；文件不存在时返回默认配置（不是错误）。
func Load() (Config, error) {
	p, err := Path()
	if err != nil {
		return Default(), err
	}
	b, err := os.ReadFile(p)
	if errors.Is(err, os.ErrNotExist) {
		return Default(), nil
	}
	if err != nil {
		return Default(), err
	}
	var c Config
	if err := json.Unmarshal(b, &c); err != nil {
		return Default(), err
	}
	// 与默认值合并，避免旧版本配置文件缺字段时得到空字符串。
	d := Default()
	if strings.TrimSpace(c.SourceName) == "" {
		c.SourceName = d.SourceName
	}
	return c, nil
}

// Save 把配置永久写入本机（权限 0600，避免同机其他用户读到凭据）。
func Save(c Config) error {
	p, err := Path()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(p, append(b, '\n'), 0o600)
}
