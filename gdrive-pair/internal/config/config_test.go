package config

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestIsGoogleInfoComplete(t *testing.T) {
	c := Default()
	if c.IsGoogleInfoComplete() {
		t.Fatal("empty client_id should be incomplete")
	}
	if err := c.Validate(); err == nil {
		t.Fatal("Validate should reject empty client_id")
	}
	c.ClientID = "  abc.apps.googleusercontent.com  "
	if !c.IsGoogleInfoComplete() {
		t.Fatal("client_id with spaces should count as complete")
	}
	if err := c.Validate(); err != nil {
		t.Fatalf("Validate should accept: %v", err)
	}
	c.ClientSecret = "" // 桌面应用类型允许留空
	if !c.IsGoogleInfoComplete() {
		t.Fatal("client_secret is optional")
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	// Windows 使用 APPDATA；两类环境都指向临时目录，保证可移植。
	t.Setenv("APPDATA", dir)

	c := Config{
		ClientID:     "id.apps.googleusercontent.com",
		ClientSecret: "GOCSPX-secret",
		SourceName:   "测试盘",
		RootFolderID: "folder-1",
		LastPairURL:  "http://192.168.1.20:18780/?pair=AB3D7K",
	}
	if err := Save(c); err != nil {
		t.Fatalf("Save: %v", err)
	}
	p, err := Path()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "gdrive-pair", "config.json")); err != nil {
		// 某些平台 UserConfigDir 会额外附加子目录，只要 Path() 指向的文件存在即可。
		if _, err2 := os.Stat(p); err2 != nil {
			t.Fatalf("config file not found: %v / %v", err, err2)
		}
	}
	got, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got != c {
		t.Fatalf("round trip mismatch:\n got %+v\nwant %+v", got, c)
	}
	// Windows 不实现 Unix 权限位，跳过该检查；Unix / Linux 上必须保证 0600。
	if runtime.GOOS != "windows" {
		info, err := os.Stat(p)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm()&0o077 != 0 {
			t.Fatalf("config must not be readable by others, mode=%v", info.Mode().Perm())
		}
	}
}

func TestLoadMissingReturnsDefault(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	t.Setenv("APPDATA", dir)
	got, err := Load()
	if err != nil {
		t.Fatalf("Load on missing file should not fail: %v", err)
	}
	if got.SourceName != Default().SourceName {
		t.Fatalf("missing file should yield default, got %+v", got)
	}
}
