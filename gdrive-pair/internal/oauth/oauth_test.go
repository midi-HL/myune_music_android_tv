package oauth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestAuthURLFor(t *testing.T) {
	u, err := url.Parse(AuthURLFor("abc.apps.googleusercontent.com", "STATE123"))
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	for k, want := range map[string]string{
		"client_id":     "abc.apps.googleusercontent.com",
		"redirect_uri":  RedirectURI,
		"response_type": "code",
		"scope":         Scope,
		"access_type":   "offline",
		"prompt":        "consent",
		"state":         "STATE123",
	} {
		if got := q.Get(k); got != want {
			t.Errorf("%s = %q, want %q", k, got, want)
		}
	}
	if u.Host != "accounts.google.com" {
		t.Fatalf("unexpected host %q", u.Host)
	}
}

func TestExchangeRejectsEmptyCode(t *testing.T) {
	if _, err := Exchange(context.Background(), "id", "", "   "); err == nil {
		t.Fatal("empty code should fail")
	}
}

func TestExchangeParsesRefreshToken(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Error(err)
		}
		if r.Form.Get("grant_type") != "authorization_code" {
			t.Errorf("grant_type = %q", r.Form.Get("grant_type"))
		}
		if r.Form.Get("client_secret") != "SECRET" {
			t.Errorf("client_secret = %q", r.Form.Get("client_secret"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"AT","refresh_token":"RT","expires_in":3600,"token_type":"Bearer"}`))
	}))
	defer srv.Close()

	orig := TokenURL
	TokenURL = srv.URL
	defer func() { TokenURL = orig }()

	tok, err := Exchange(context.Background(), "ID", "SECRET", "CODE")
	if err != nil {
		t.Fatalf("Exchange: %v", err)
	}
	if tok.RefreshToken != "RT" || tok.AccessToken != "AT" {
		t.Fatalf("unexpected tokens: %+v", tok)
	}
}

func TestExchangeSurfacesGoogleError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"Bad Request"}`))
	}))
	defer srv.Close()
	orig := TokenURL
	TokenURL = srv.URL
	defer func() { TokenURL = orig }()

	_, err := Exchange(context.Background(), "ID", "", "CODE")
	if err == nil || !strings.Contains(err.Error(), "invalid_grant") {
		t.Fatalf("expected invalid_grant error, got %v", err)
	}
}

func TestStartLoopbackReceivesCode(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	state := "S1"
	ch, stop, err := StartLoopback(ctx, state)
	if err != nil {
		t.Skipf("loopback port unavailable: %v", err)
	}
	defer stop()

	go func() {
		resp, err := http.Get(RedirectURI + "?state=" + state + "&code=THE_CODE")
		if err == nil {
			_ = resp.Body.Close()
		}
	}()
	select {
	case code := <-ch:
		if code != "THE_CODE" {
			t.Fatalf("code = %q", code)
		}
	case <-ctx.Done():
		t.Fatal("timed out waiting for code")
	}
}
