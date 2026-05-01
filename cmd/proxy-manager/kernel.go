package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runKernel 是 `proxy-manager kernel` 子命令的入口。
//
// 用法：
//
//	proxy-manager kernel             # 列出所有内核 + 当前/最新版本
//	proxy-manager kernel list        # 同上
//	proxy-manager kernel upgrade     # 交互选要升的内核
//	proxy-manager kernel upgrade --all
//	proxy-manager kernel upgrade xray-core
func runKernel(args []string) {
	sub := "list"
	if len(args) > 0 {
		sub = args[0]
	}
	switch sub {
	case "list", "ls", "":
		runKernelList()
	case "upgrade", "update":
		runKernelUpgrade(args[1:])
	case "-h", "--help":
		fmt.Println(kernelHelp())
	default:
		fmt.Fprintf(os.Stderr, "未知子命令: %s\n%s\n", sub, kernelHelp())
		os.Exit(2)
	}
}

func kernelHelp() string {
	return `用法: proxy-manager kernel <command>

  list                  列出所有内核 + 当前/最新版本 (默认行为)
  upgrade [name|--all]  升级指定内核或全部 (无参数 = 交互选)`
}

func runKernelList() {
	kernels := install.ListKernels()
	if len(kernels) == 0 {
		fmt.Println("尚未安装任何协议")
		return
	}
	fmt.Println()
	fmt.Printf("%s%-14s %-12s %-12s %-8s %s%s\n",
		utils.ColorCyan, "Kernel", "Current", "Latest", "Status", "Used by", utils.ColorReset)
	fmt.Println(strings.Repeat("─", 80))
	for _, k := range kernels {
		cur := k.CurrentVersion()
		latest := k.LatestVersion()
		status, color := compareVer(cur, latest)
		fmt.Printf("%-14s %-12s %-12s %s%-8s%s %s\n",
			k.Name, dashIfEmpty(cur), dashIfEmpty(latest),
			color, status, utils.ColorReset, strings.Join(k.UsedBy, ", "))
	}
	fmt.Println()
	fmt.Println("升级：proxy-manager kernel upgrade [name|--all]")
}

func runKernelUpgrade(args []string) {
	kernels := install.ListKernels()
	if len(kernels) == 0 {
		fmt.Println("尚未安装任何协议")
		return
	}

	target := ""
	all := false
	for _, a := range args {
		switch a {
		case "--all":
			all = true
		default:
			if !strings.HasPrefix(a, "--") {
				target = a
			}
		}
	}

	var pick []install.Kernel
	switch {
	case all:
		pick = kernels
	case target != "":
		for _, k := range kernels {
			if strings.EqualFold(k.Name, target) {
				pick = append(pick, k)
				break
			}
		}
		if len(pick) == 0 {
			fmt.Fprintf(os.Stderr, "未找到内核: %s\n", target)
			fmt.Fprintln(os.Stderr, "可用:")
			for _, k := range kernels {
				fmt.Fprintf(os.Stderr, "  - %s\n", k.Name)
			}
			os.Exit(2)
		}
	default:
		// 交互选
		fmt.Println()
		fmt.Printf("%s选择要升级的内核:%s\n", utils.ColorCyan, utils.ColorReset)
		for i, k := range kernels {
			fmt.Printf("  %d. %s  %s → %s\n", i+1, k.Name,
				dashIfEmpty(k.CurrentVersion()), dashIfEmpty(k.LatestVersion()))
		}
		fmt.Printf("  %d. 全部升级\n", len(kernels)+1)
		fmt.Println("  0. 取消")
		fmt.Println()
		idx := utils.PromptInt("请选择", 0, 0, len(kernels)+1)
		if idx == 0 {
			fmt.Println("已取消")
			return
		}
		if idx == len(kernels)+1 {
			pick = kernels
		} else {
			pick = []install.Kernel{kernels[idx-1]}
		}
	}

	// 逐个升
	var firstErr error
	for _, k := range pick {
		fmt.Println()
		fmt.Printf("%s━━━━━━━━ %s ━━━━━━━━%s\n", utils.ColorCyan, k.Name, utils.ColorReset)
		if err := k.Upgrade(); err != nil {
			utils.PrintError("%s 升级失败: %v", k.Name, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		utils.PrintSuccess("%s 升级完成", k.Name)
	}

	fmt.Println()
	if firstErr != nil {
		os.Exit(1)
	}
	utils.PrintSuccess("全部完成。验证: proxy-manager doctor")
}

func compareVer(cur, latest string) (string, string) {
	if cur == "" {
		return "?", utils.ColorYellow
	}
	if latest == "" {
		return "?", utils.ColorYellow
	}
	// 简单字符串比较：去掉 v 前缀。版本号都用 semver 形式时 OK。
	cn := strings.TrimPrefix(cur, "v")
	ln := strings.TrimPrefix(latest, "v")
	if cn == ln {
		return "✓ 最新", utils.ColorGreen
	}
	return "可升级", utils.ColorYellow
}

func dashIfEmpty(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
