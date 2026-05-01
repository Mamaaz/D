package sni

import (
	"sort"
	"strings"
	"sync"
	"time"
)

// RankedResult 是排序后的单条记录。
type RankedResult struct {
	Result *ProbeResult
	Score  float64
}

// Rank 并发探测一组 host，按 Reality SNI 适合度打分排序。返回从优到劣。
// onProgress 每完成一个 host 调一次（可为 nil），适合 UI 渲染进度点。
func Rank(hosts []string, parallel int, onProgress func()) []RankedResult {
	results := probeAll(hosts, parallel, onProgress)
	scored := make([]RankedResult, 0, len(results))
	for _, r := range results {
		scored = append(scored, RankedResult{Result: r, Score: scoreReality(r)})
	}
	sort.SliceStable(scored, func(i, j int) bool {
		si := scored[i].Result.Suitable()
		sj := scored[j].Result.Suitable()
		if si != sj {
			return si
		}
		return scored[i].Score > scored[j].Score
	})
	return scored
}

func probeAll(hosts []string, parallel int, onProgress func()) []*ProbeResult {
	if parallel < 1 {
		parallel = 8
	}
	out := make([]*ProbeResult, len(hosts))
	sem := make(chan struct{}, parallel)
	var wg sync.WaitGroup
	for i, h := range hosts {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, h string) {
			defer wg.Done()
			defer func() { <-sem }()
			out[i] = Probe(h, 5*time.Second)
			if onProgress != nil {
				onProgress()
			}
		}(i, h)
	}
	wg.Wait()
	return out
}

// scoreReality 给一个 host 在 Reality SNI 场景下的"适合度"打分。
// 高分 = 推荐。打分逻辑透明：
//   - 不合格 (Suitable=false) → -1e9 (确保排到末尾)
//   - HTTP 200 → +1000；HTTP 5xx → -500
//   - HTTP HEAD 协议错 (EOF/timeout) → -200
//   - CDN (cloudflare/akamai/...) → -300
//   - Server 隐版本号 (如纯 "nginx") → +100
//   - ALPN h2 → +100
//   - TLS 握手 RTT 直接当负分；HTTP RTT 减半权重
func scoreReality(r *ProbeResult) float64 {
	if !r.Suitable() {
		return -1e9
	}
	score := 0.0
	switch {
	case r.HTTPStatus == 200:
		score += 1000
	case r.HTTPStatus >= 500:
		score -= 500
	}
	if r.HTTPErr != nil {
		score -= 200
	}
	if r.IsCDN() {
		score -= 300
	}
	if r.Server != "" && !strings.Contains(strings.ToLower(r.Server), "/") {
		score += 100
	}
	if r.ALPN == "h2" {
		score += 100
	}
	score -= float64(r.HandshakeMs)
	score -= float64(r.HTTPRTTMs) / 2
	return score
}

// ParseInput 自动识别输入：CSV (任何含 cert_domain 列的格式) 或一行一 host。
// 跳过空行和 # 开头注释行。去重。
func ParseInput(lines []string) []string {
	var out []string
	seen := map[string]bool{}
	csvDomainCol := -1
	for _, raw := range lines {
		ln := strings.TrimSpace(raw)
		if ln == "" || strings.HasPrefix(ln, "#") {
			continue
		}
		if csvDomainCol < 0 && strings.Contains(ln, ",") &&
			strings.Contains(strings.ToLower(ln), "cert_domain") {
			cols := splitSimpleCSV(ln)
			for i, c := range cols {
				if strings.EqualFold(strings.TrimSpace(c), "cert_domain") {
					csvDomainCol = i
					break
				}
			}
			continue
		}
		var host string
		if csvDomainCol >= 0 {
			cols := splitSimpleCSV(ln)
			if csvDomainCol < len(cols) {
				host = strings.TrimSpace(cols[csvDomainCol])
			}
		} else {
			host = ln
		}
		if host == "" || strings.ContainsAny(host, " \t") {
			continue
		}
		if seen[host] {
			continue
		}
		seen[host] = true
		out = append(out, host)
	}
	return out
}

func splitSimpleCSV(line string) []string {
	var fields []string
	var cur strings.Builder
	inQ := false
	for _, ch := range line {
		switch ch {
		case '"':
			inQ = !inQ
		case ',':
			if inQ {
				cur.WriteRune(ch)
			} else {
				fields = append(fields, cur.String())
				cur.Reset()
			}
		default:
			cur.WriteRune(ch)
		}
	}
	fields = append(fields, cur.String())
	return fields
}
