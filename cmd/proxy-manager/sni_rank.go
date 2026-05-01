package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/sni"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runSNIRank 是 `proxy-manager sni-rank` 子命令——薄包装，逻辑全在 internal/sni。
//
// 输入：stdin / --in <file> / 命令行 positional args。CSV 自动识别。
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
	scored := sni.Rank(hosts, parallel, func() {
		fmt.Fprint(os.Stderr, ".")
	})
	fmt.Fprintln(os.Stderr)

	PrintRankTable(scored, top)
	PrintRecommendation(scored)
}

// PrintRankTable 渲染排序后的表格。CLI 和 TUI 共用同一渲染逻辑，
// 大写字母导出后 ui 包能直接调。
func PrintRankTable(scored []sni.RankedResult, top int) {
	if top > len(scored) {
		top = len(scored)
	}
	fmt.Printf("%s%-6s %-32s %-8s %-7s %-15s %-6s %s%s\n",
		utils.ColorCyan, "Rank", "Host", "RTT", "HTTP", "Server", "ALPN", "Score", utils.ColorReset)
	fmt.Println(strings.Repeat("─", 90))
	for i := 0; i < top; i++ {
		r := scored[i].Result
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
			http, truncate(server, 15), truncate(r.ALPN, 6), scored[i].Score)
	}
	if len(scored) > top {
		fmt.Printf("\n... 隐藏 %d 个 (用 --top %d 显示全部)\n", len(scored)-top, len(scored))
	}
}

// PrintRecommendation 输出推荐 host + 现成的 edit 命令。
func PrintRecommendation(scored []sni.RankedResult) {
	if len(scored) == 0 {
		return
	}
	best := scored[0]
	if !best.Result.Suitable() {
		fmt.Println()
		fmt.Printf("%s没有候选满足 Reality SNI 标准 (TLS 1.3 + 证书可信)。%s\n",
			utils.ColorRed, utils.ColorReset)
		fmt.Println("建议换一段 IP 范围重新扫描。")
		return
	}
	fmt.Println()
	fmt.Printf("%s🏆 推荐: %s%s%s\n", utils.ColorCyan, utils.ColorGreen, best.Result.Host, utils.ColorReset)
	fmt.Printf("   一键应用：proxy-manager edit reality --field sni --value %s\n", best.Result.Host)
	fmt.Println()
}

// MARK: - input parsing (CLI-specific)

func collectHosts(args []string, infile string) []string {
	var lines []string
	flagsWithValue := map[string]bool{"--in": true, "--top": true, "--parallel": true}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if strings.HasPrefix(a, "--") {
			if flagsWithValue[a] && !strings.Contains(a, "=") && i+1 < len(args) {
				i++
			}
			continue
		}
		lines = append(lines, a)
	}
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
	if len(lines) == 0 && !isStdinTerminal() {
		sc := bufio.NewScanner(os.Stdin)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		for sc.Scan() {
			lines = append(lines, sc.Text())
		}
	}
	return sni.ParseInput(lines)
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

func isStdinTerminal() bool {
	fi, err := os.Stdin.Stat()
	if err != nil {
		return true
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}
