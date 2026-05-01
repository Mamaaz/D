package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runSNIRank 实现 `proxy-manager sni-rank` 子命令——对一批候选 SNI 并发跑
// sni-test，按"VPS 视角适合度"打分排序。
//
// 输入支持 3 种：
//   - stdin (一行一个 hostname；自动跳过 RealiTLScanner CSV 表头)
//   - --in <file>  同上
//   - 命令行 args: sni-rank host1 host2 ...
//
// CSV 自动识别：首行匹配 "IP,ORIGIN,CERT_DOMAIN,..." 时按 RealiTLScanner
// 输出格式取 CERT_DOMAIN 列；否则把每行整体当 hostname。
//
// 用法示例：
//
//	# 把 RealiTLScanner CSV 直接 pipe 进来
//	cat scan.csv | proxy-manager sni-rank --top 5
//
//	# 直接给一组域名
//	proxy-manager sni-rank apple.com cloudflare.com microsoft.com
func runSNIRank(args []string) {
	infile := flagValue(args, "--in")
	topStr := flagValue(args, "--top")
	parallelStr := flagValue(args, "--parallel")

	top := 10
	if topStr != "" {
		if n, err := atoiPositive(topStr); err == nil {
			top = n
		}
	}
	parallel := 8
	if parallelStr != "" {
		if n, err := atoiPositive(parallelStr); err == nil {
			parallel = n
		}
	}

	hosts := collectHosts(args, infile)
	if len(hosts) == 0 {
		fmt.Fprintln(os.Stderr, "用法: proxy-manager sni-rank [--in scan.csv] [--top N] [--parallel N] [host ...]")
		fmt.Fprintln(os.Stderr, "  也可 stdin 输入 (每行一个 host 或 RealiTLScanner CSV)")
		os.Exit(2)
	}

	fmt.Printf("%s扫描 %d 个候选...%s\n\n", utils.ColorCyan, len(hosts), utils.ColorReset)
	results := probeAll(hosts, parallel)

	scored := make([]rankedResult, 0, len(results))
	for _, r := range results {
		scored = append(scored, rankedResult{result: r, score: scoreReality(r)})
	}
	// suitable + score 高的优先；不合格的放最后
	sort.SliceStable(scored, func(i, j int) bool {
		si := scored[i].result.Suitable()
		sj := scored[j].result.Suitable()
		if si != sj {
			return si // suitable 在前
		}
		return scored[i].score > scored[j].score
	})

	printRankTable(scored, top)
	printRecommendation(scored)
}

type rankedResult struct {
	result *SNIProbeResult
	score  float64
}

// scoreReality 给一个 host 在 Reality SNI 场景下的"适合度"打分。
// 高分 = 推荐。打分逻辑透明，避免黑盒：
//   - 不合格 (Suitable=false) → -1e9 (确保排到末尾)
//   - HTTP 200 → +1000；HTTP 5xx → -500；其他状态 → 0
//   - 是 CDN (cloudflare/akamai/...) → -300 (Reality 不建议 CDN)
//   - 隐版本 nginx (无 nginx/1.x.y) → +100 (运维痕迹专业)
//   - HEAD EOF 等 → -200 (HTTP 协议层异常)
//   - RTT 罚分: TLS 握手 + HTTP 总耗时；每 1ms = -1
func scoreReality(r *SNIProbeResult) float64 {
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
		score += 100 // 没暴露版本号
	}
	if r.ALPN == "h2" {
		score += 100
	}
	score -= float64(r.HandshakeMs)
	score -= float64(r.HTTPRTTMs) / 2 // HTTP RTT 权重低一些
	return score
}

func probeAll(hosts []string, parallel int) []*SNIProbeResult {
	out := make([]*SNIProbeResult, len(hosts))
	sem := make(chan struct{}, parallel)
	var wg sync.WaitGroup
	for i, h := range hosts {
		wg.Add(1)
		sem <- struct{}{}
		go func(i int, h string) {
			defer wg.Done()
			defer func() { <-sem }()
			out[i] = probeSNI(h, 5*time.Second)
			fmt.Fprintf(os.Stderr, ".")
		}(i, h)
	}
	wg.Wait()
	fmt.Fprintln(os.Stderr)
	return out
}

func printRankTable(scored []rankedResult, top int) {
	if top > len(scored) {
		top = len(scored)
	}
	fmt.Printf("%s%-6s %-32s %-8s %-7s %-15s %-6s %s%s\n",
		utils.ColorCyan, "Rank", "Host", "RTT", "HTTP", "Server", "ALPN", "Score", utils.ColorReset)
	fmt.Println(strings.Repeat("─", 90))
	for i := 0; i < top; i++ {
		r := scored[i].result
		mark := "✅"
		if !r.Suitable() {
			mark = "❌"
		}
		http := "-"
		if r.HTTPStatus > 0 {
			http = fmt.Sprintf("%d", r.HTTPStatus)
		} else if r.HTTPErr != nil {
			http = "ERR"
		}
		server := r.Server
		if len(server) > 14 {
			server = server[:14]
		}
		fmt.Printf("%s %-4d %-32s %-8s %-7s %-15s %-6s %.0f\n",
			mark, i+1, truncate(r.Host, 32), fmt.Sprintf("%dms", r.HandshakeMs),
			http, truncate(server, 15), truncate(r.ALPN, 6), scored[i].score)
	}
	if len(scored) > top {
		fmt.Printf("\n... 隐藏 %d 个 (用 --top %d 显示全部)\n", len(scored)-top, len(scored))
	}
}

func printRecommendation(scored []rankedResult) {
	if len(scored) == 0 {
		return
	}
	best := scored[0]
	if !best.result.Suitable() {
		fmt.Println()
		fmt.Printf("%s没有候选满足 Reality SNI 标准 (TLS 1.3 + 证书可信)。%s\n",
			utils.ColorRed, utils.ColorReset)
		fmt.Println("建议换一段 IP 范围重新扫描。")
		return
	}
	fmt.Println()
	fmt.Printf("%s🏆 推荐: %s%s%s\n", utils.ColorCyan, utils.ColorGreen, best.result.Host, utils.ColorReset)
	fmt.Printf("   一键应用：proxy-manager edit reality --field sni --value %s\n", best.result.Host)
	fmt.Println()
}

// MARK: - input parsing

func collectHosts(args []string, infile string) []string {
	var lines []string
	// 1) 命令行 positional args。flagValue 已经提取过 --xxx，但简单 loop
	// 还要跳过 "--top 6" 这种"flag + 下一个 token = 值"的情况。
	flagsWithValue := map[string]bool{"--in": true, "--top": true, "--parallel": true}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if strings.HasPrefix(a, "--") {
			// "--top=6" 形式自带值，无需跳下一个；"--top 6" 跳一个。
			if flagsWithValue[a] && !strings.Contains(a, "=") && i+1 < len(args) {
				i++
			}
			continue
		}
		lines = append(lines, a)
	}
	// 2) --in 文件
	if infile != "" {
		if data, err := os.ReadFile(infile); err == nil {
			for _, ln := range strings.Split(string(data), "\n") {
				lines = append(lines, ln)
			}
		} else {
			fmt.Fprintf(os.Stderr, "无法读取 %s: %v\n", infile, err)
			os.Exit(1)
		}
	}
	// 3) stdin (仅当没有任何上面的输入时检测)
	if len(lines) == 0 && !isStdinTerminal() {
		sc := bufio.NewScanner(os.Stdin)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		for sc.Scan() {
			lines = append(lines, sc.Text())
		}
	}
	return parseHosts(lines)
}

// parseHosts: 自动识别 CSV 表头里的 cert_domain 列（大小写兼容）。
// 支持 RealiTLScanner 原生格式 (IP,ORIGIN,CERT_DOMAIN,...) 和 XSurge 复制
// 出来的 (cert_domain,ip,issuer,...). 找不到表头时把每行当 hostname。
func parseHosts(lines []string) []string {
	var out []string
	seen := map[string]bool{}
	csvDomainCol := -1 // -1 = 还没识别 / 不是 CSV 模式
	for _, raw := range lines {
		ln := strings.TrimSpace(raw)
		if ln == "" || strings.HasPrefix(ln, "#") {
			continue
		}
		// 第一行如果含逗号 + cert_domain (任意大小写) → 当 CSV 表头处理
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
		if host == "" || strings.Contains(host, " ") || strings.Contains(host, "\t") {
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

func atoiPositive(s string) (int, error) {
	n := 0
	for _, c := range s {
		if c < '0' || c > '9' {
			return 0, fmt.Errorf("not a number: %s", s)
		}
		n = n*10 + int(c-'0')
	}
	if n <= 0 {
		return 0, fmt.Errorf("must be positive")
	}
	return n, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// isStdinTerminal: 判断 stdin 是不是 TTY。pipe 进来的 stdin 不是 TTY，
// 我们读它；交互终端则不读避免阻塞。
func isStdinTerminal() bool {
	fi, err := os.Stdin.Stat()
	if err != nil {
		return true
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}
