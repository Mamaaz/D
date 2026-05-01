package subscribe

import (
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func TestLimiterTokenBucket(t *testing.T) {
	l := newLimiter()
	now := time.Unix(1000000, 0)

	// 前 rlBurst 次都应放行
	for i := 0; i < rlBurst; i++ {
		ok, _ := l.allow("1.1.1.1", now)
		if !ok {
			t.Fatalf("burst request %d should be allowed", i)
		}
	}
	// 第 rlBurst+1 次应被拒
	ok, _ := l.allow("1.1.1.1", now)
	if ok {
		t.Fatal("over-burst request should be denied")
	}
	// 等 60 秒后,token 桶应充满
	ok, _ = l.allow("1.1.1.1", now.Add(60*time.Second))
	if !ok {
		t.Fatal("after refill, request should be allowed")
	}
}

func TestLimiterUnauthBan(t *testing.T) {
	l := newLimiter()
	now := time.Unix(1000000, 0)
	// 一直放行第一波
	l.allow("2.2.2.2", now)

	for i := 0; i < rlUnauthThreshold; i++ {
		l.recordUnauth("2.2.2.2", now)
	}
	// 达阈值后下一次 allow 应直接拒绝
	ok, until := l.allow("2.2.2.2", now)
	if ok {
		t.Fatal("after unauth threshold, IP should be banned")
	}
	if !until.After(now) {
		t.Fatalf("ban should extend into the future, got %v", until)
	}
	// 计数清零路径:成功授权后,再来 5 次失败才再次 ban
	l.recordAuth("2.2.2.2")
	// 等 ban 过期
	future := now.Add(rlBanDuration + time.Second)
	for i := 0; i < rlUnauthThreshold-1; i++ {
		l.recordUnauth("2.2.2.2", future)
	}
	ok, _ = l.allow("2.2.2.2", future)
	if !ok {
		t.Fatal("unauth count should have reset after recordAuth")
	}
}

func TestClientIPParsing(t *testing.T) {
	cases := map[string]string{
		"1.2.3.4:55555":         "1.2.3.4",
		"[2001:db8::1]:55555":   "2001:db8::1",
		"127.0.0.1:1":           "127.0.0.1",
	}
	for in, want := range cases {
		r := httptest.NewRequest("GET", "/", nil)
		r.RemoteAddr = in
		if got := clientIP(r); got != want {
			t.Errorf("clientIP(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestAcceptTokenGracePeriod(t *testing.T) {
	now := time.Now()
	cfg := store.SubscribeConfig{
		Token:                  "newtoken",
		PreviousToken:          "oldtoken",
		PreviousTokenExpiresAt: now.Add(time.Hour),
	}
	if !acceptToken(cfg, "newtoken", now) {
		t.Fatal("current token should be accepted")
	}
	if !acceptToken(cfg, "oldtoken", now) {
		t.Fatal("previous token within grace period should be accepted")
	}
	// 宽限期结束 → 旧 token 失效
	if acceptToken(cfg, "oldtoken", now.Add(2*time.Hour)) {
		t.Fatal("previous token after grace period must NOT be accepted")
	}
	if acceptToken(cfg, "wrongtoken", now) {
		t.Fatal("unrelated token must not be accepted")
	}
}
