package pair

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestNormalizePairURL(t *testing.T) {
	cases := []struct {
		in       string
		wantURL  string
		wantPair string
	}{
		{"http://192.168.1.20:18780/?pair=AB3D7K", "http://192.168.1.20:18780/?pair=AB3D7K", "AB3D7K"},
		{"192.168.1.20:18780/?pair=AB3D7K", "http://192.168.1.20:18780/?pair=AB3D7K", "AB3D7K"},
		{"http://192.168.1.20/?pair=ZZZ999", "http://192.168.1.20:18780/?pair=ZZZ999", "ZZZ999"},
	}
	for _, c := range cases {
		got, p, err := NormalizePairURL(c.in)
		if err != nil {
			t.Errorf("%s: %v", c.in, err)
			continue
		}
		if got != c.wantURL || p != c.wantPair {
			t.Errorf("%s -> %s / %s, want %s / %s", c.in, got, p, c.wantURL, c.wantPair)
		}
	}
	for _, bad := range []string{"", "http://192.168.1.20:18780/", "https://x/?pair=A"} {
		if _, _, err := NormalizePairURL(bad); err == nil {
			t.Errorf("%q should fail", bad)
		}
	}
}

func TestSubmitURL(t *testing.T) {
	u, _ := url.Parse("http://192.168.1.20:18780/?pair=AB3D7K")
	_ = u
	got, err := SubmitURL("http://192.168.1.20:18780/?pair=AB3D7K")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "/submit") {
		t.Fatalf("SubmitURL = %q", got)
	}
}

func TestSubmitSendsExpectedPayload(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/submit" {
			t.Errorf("path = %q", r.URL.Path)
		}
		if r.Method != http.MethodPost {
			t.Errorf("method = %q", r.Method)
		}
		var c Credentials
		if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
			t.Error(err)
		}
		if c.ClientID != "ID" || c.RefreshToken != "RT" || c.Pair != "AB3D7K" {
			t.Errorf("payload mismatch: %+v", c)
		}
		if c.Name != "我的盘" || c.RootFolderID != "F1" || c.ClientSecret != "SEC" {
			t.Errorf("optional fields mismatch: %+v", c)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer srv.Close()
	// 让 /submit 指向测试服务器；SubmitURL 会保留 host 与 scheme。
	u, _ := url.Parse(srv.URL)
	base := u.Scheme + "://" + u.Host + "/?pair=AB3D7K"

	res, err := Submit(context.Background(), base, Credentials{
		Name: "我的盘", ClientID: "ID", ClientSecret: "SEC",
		RefreshToken: "RT", RootFolderID: "F1", Pair: "AB3D7K",
	})
	if err != nil {
		t.Fatalf("Submit: %v", err)
	}
	if !res.OK {
		t.Fatal("expected ok")
	}
}

func TestSubmitReportsTvError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"ok":false,"error":"凭据校验失败"}`))
	}))
	defer srv.Close()
	u, _ := url.Parse(srv.URL)
	base := u.Scheme + "://" + u.Host + "/?pair=AB3D7K"
	_, err := Submit(context.Background(), base, Credentials{
		ClientID: "ID", RefreshToken: "RT", Pair: "AB3D7K",
	})
	if err == nil || !strings.Contains(err.Error(), "凭据校验失败") {
		t.Fatalf("expected TV error, got %v", err)
	}
}

func TestSubmitValidatesInput(t *testing.T) {
	if _, err := Submit(context.Background(), "http://x/?pair=A", Credentials{Pair: "A"}); err == nil {
		t.Fatal("missing credentials should fail")
	}
	if _, err := Submit(context.Background(), "http://x/?pair=A", Credentials{ClientID: "I", RefreshToken: "R"}); err == nil {
		t.Fatal("missing pair should fail")
	}
}
