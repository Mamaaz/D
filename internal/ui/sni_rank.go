package ui

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/sni"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// doRankSNI 是 TUI 「Reality SNI 候选评估」菜单项的入口。流程：
//
//  1. 提示用户粘贴扫描结果（CSV 或一行一 host），空行结束
//  2. 解析、并发探测、按 Reality 适合度打分排序
//  3. 渲染排序表 + 推荐 top 1
//  4. 询问是否一键应用：调 install.EditReality 改 SNI + 重启服务
//
// 没装 Reality 也能跑——只是最后那步应用会被拦下。
func doRankSNI() {
	fmt.Println()
	fmt.Printf("%s=== Reality SNI 候选评估 ===%s\n", utils.ColorCyan, utils.ColorReset)
	fmt.Println()
	fmt.Println("粘贴 RealiTLScanner / XSurge 输出的 CSV，或每行一个 hostname。")
	fmt.Printf("%s输入空行结束。%s\n", utils.ColorYellow, utils.ColorReset)
	fmt.Println()

	lines := readUntilBlank()
	hosts := sni.ParseInput(lines)
	if len(hosts) == 0 {
		utils.PrintWarn("没有解析出 hostname。")
		return
	}

	fmt.Println()
	fmt.Printf("%s扫描 %d 个候选...%s\n", utils.ColorCyan, len(hosts), utils.ColorReset)
	scored := sni.Rank(hosts, 8, func() {
		fmt.Fprint(os.Stderr, ".")
	})
	fmt.Fprintln(os.Stderr)
	fmt.Println()

	renderRankTable(scored, 10)

	if len(scored) == 0 || !scored[0].Result.Suitable() {
		fmt.Println()
		utils.PrintWarn("没有候选满足 Reality SNI 标准。建议换一段 IP 范围重新扫描。")
		return
	}

	best := scored[0].Result
	fmt.Println()
	fmt.Printf("%s🏆 推荐:%s %s%s%s\n", utils.ColorCyan, utils.ColorReset, utils.ColorGreen, best.Host, utils.ColorReset)
	fmt.Println()

	if !install.IsRealityInstalled() {
		fmt.Printf("%s当前没装 VLESS Reality。复制下面命令后续应用：%s\n", utils.ColorYellow, utils.ColorReset)
		fmt.Printf("  proxy-manager edit reality --field sni --value %s\n\n", best.Host)
		return
	}

	if !utils.PromptConfirm(fmt.Sprintf("应用推荐 SNI = %s 并重启 sing-box-reality?", best.Host)) {
		fmt.Println("已取消。可手工跑：proxy-manager edit reality --field sni --value " + best.Host)
		return
	}
	if err := install.EditReality("sni", best.Host); err != nil {
		utils.PrintError("应用失败: %v", err)
		return
	}
	utils.PrintSuccess("✓ Reality SNI 已切到 %s，服务已重启。", best.Host)
	fmt.Println("提示：")
	fmt.Println("  - 客户端要拿新配置（XSurge 自动 sync 即可，或 proxy-manager export）")
	fmt.Println("  - 验证: proxy-manager doctor")
}

// readUntilBlank 从 stdin 读，直到空行或 EOF。返回非空行。
func readUntilBlank() []string {
	sc := bufio.NewScanner(os.Stdin)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	var lines []string
	for sc.Scan() {
		ln := sc.Text()
		if strings.TrimSpace(ln) == "" {
			break
		}
		lines = append(lines, ln)
	}
	return lines
}

// renderRankTable 跟 cmd/proxy-manager/sni_rank.go 的 PrintRankTable 同款，
// 但把字段保留在 ui 包内，避免 ui 反向 import cmd。重复一段渲染代码值得，
// 比循环依赖干净。
func renderRankTable(scored []sni.RankedResult, top int) {
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
		alpn := r.ALPN
		if len(alpn) > 6 {
			alpn = alpn[:6]
		}
		host := r.Host
		if len(host) > 32 {
			host = host[:32]
		}
		fmt.Printf("%s %-4d %-32s %-8s %-7s %-15s %-6s %.0f\n",
			mark, i+1, host, fmt.Sprintf("%dms", r.HandshakeMs),
			http, server, alpn, scored[i].Score)
	}
	if len(scored) > top {
		fmt.Printf("\n... 隐藏 %d 个\n", len(scored)-top)
	}
}
