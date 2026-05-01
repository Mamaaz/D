// Package subscribe implements the HTTPS subscription endpoint that serves
// installed nodes in Surge / Clash Meta / sing-box / xray / raw JSON formats.
//
// Endpoints
//
//	GET /s/{format}/{token}
//	GET /healthz                (200 OK, no auth — for monitoring)
//
// Authentication is a single token in the URL path, compared in constant time.
// Rotating the token via `proxy-manager subscribe rotate-token` issues a new
// token; the old token stays valid for store.PreviousTokenGracePeriod (7 days)
// so clients have a window to update without going dark mid-rotation.
//
// Per-IP rate limiting + ban-on-repeated-401 in ratelimit.go gives defense in
// depth against token brute force / leaked-token abuse.
package subscribe

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/format"
	"github.com/Mamaaz/proxy-manager/internal/store"
)

// rl 是 process-级 rate limiter。serveSubscribe / token 校验失败 都通过它
// 共享 ban 状态。Handler 创建,所以每次 daemon 重启清零 (单 binary 自用够)。
var rl = newLimiter()

// Handler returns the http.Handler that serves all subscription routes.
// It re-loads the store on every request so new installs/uninstalls take
// effect without restarting the daemon.
func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("/s/", serveSubscribe)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.NotFound(w, r)
	})
	return logMiddleware(rateLimitMiddleware(rl, mux))
}

func serveSubscribe(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/s/"), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		http.NotFound(w, r)
		return
	}
	formatName, token := parts[0], parts[1]

	s, err := store.Load()
	if err != nil {
		http.Error(w, "store unavailable", http.StatusInternalServerError)
		return
	}
	ip := clientIP(r)
	if !acceptToken(s.Subscribe, token, time.Now()) {
		rl.recordUnauth(ip, time.Now())
		http.NotFound(w, r) // 404 not 401 to avoid revealing token presence
		return
	}
	rl.recordAuth(ip)

	// Stable order so identical store state always renders identical output.
	sort.SliceStable(s.Nodes, func(i, j int) bool { return s.Nodes[i].ID < s.Nodes[j].ID })

	if err := writeFormat(w, formatName, s); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
	}
}

// acceptToken 接受当前 token,或者 rotate 之后还在宽限期里的旧 token。
// rotate 后给客户端 7 天时间重新拿 URL,避免一刀切断订阅。
func acceptToken(cfg store.SubscribeConfig, supplied string, now time.Time) bool {
	if validToken(cfg.Token, supplied) {
		return true
	}
	if cfg.PreviousToken != "" && now.Before(cfg.PreviousTokenExpiresAt) {
		return validToken(cfg.PreviousToken, supplied)
	}
	return false
}

// validToken returns true iff configured and supplied tokens match in
// constant time. An empty configured token always rejects — guards against
// a misconfigured daemon serving anonymously.
func validToken(configured, supplied string) bool {
	if configured == "" || len(supplied) != len(configured) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(configured), []byte(supplied)) == 1
}

func writeFormat(w http.ResponseWriter, name string, s *store.Store) error {
	switch name {
	case "json":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(s)
	case "surge":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, n := range s.Nodes {
			line, err := format.ToSurge(&n)
			if err != nil {
				continue
			}
			fmt.Fprintln(w, line)
		}
		return nil
	case "clash", "mihomo":
		// Mihomo (formerly Clash.Meta) is the active fork; it accepts standard
		// Clash YAML/JSON. Same handler — alias for discoverability.
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		proxies := make([]map[string]any, 0, len(s.Nodes))
		for _, n := range s.Nodes {
			entry, err := format.ToClash(&n)
			if err != nil {
				continue
			}
			proxies = append(proxies, entry)
		}
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(map[string]any{"proxies": proxies})
	case "qx", "quantumultx":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, n := range s.Nodes {
			line, err := format.ToQX(&n)
			if err != nil {
				continue
			}
			fmt.Fprintln(w, line)
		}
		return nil
	case "singbox", "sing-box":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		outbounds := make([]map[string]any, 0, len(s.Nodes)*2)
		for _, n := range s.Nodes {
			entries, err := format.ToSingbox(&n)
			if err != nil {
				continue
			}
			outbounds = append(outbounds, entries...)
		}
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(map[string]any{"outbounds": outbounds})
	case "xray":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		outbounds := make([]map[string]any, 0, len(s.Nodes))
		for _, n := range s.Nodes {
			if !format.NeedsBridge(&n) {
				continue
			}
			entries, err := format.ToXray(&n)
			if err != nil {
				continue
			}
			outbounds = append(outbounds, entries...)
		}
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(map[string]any{"outbounds": outbounds})
	}
	return fmt.Errorf("unknown format: %s (supported: json, surge, clash, mihomo, singbox, xray, qx)", name)
}

func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Mask the token in logs: /s/surge/abc123 -> /s/surge/***
		path := r.URL.Path
		if strings.HasPrefix(path, "/s/") {
			parts := strings.SplitN(path[3:], "/", 2)
			if len(parts) == 2 {
				path = "/s/" + parts[0] + "/***"
			}
		}
		log.Printf("%s %s %s", r.Method, path, r.RemoteAddr)
		next.ServeHTTP(w, r)
	})
}
