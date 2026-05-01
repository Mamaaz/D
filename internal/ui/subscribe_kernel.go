package ui

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/subscribe"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// doSubscribeMenu 是菜单 #15 的入口：订阅服务管理。
//
// 之前 subscribe 只能 CLI 子命令操作 (proxy-manager subscribe enable/disable/url/...)，
// 隐藏太深；现在 TUI 一进来就能选择启用 / 停用 / 看 URL / 轮换 token / 看状态。
func doSubscribeMenu() {
	for {
		fmt.Println()
		fmt.Printf("%s=== 订阅服务管理 ===%s\n", utils.ColorCyan, utils.ColorReset)
		fmt.Printf("当前状态: %s\n", subscribe.Status())
		fmt.Println()
		fmt.Println("  1. 启用订阅服务 (subscribe enable)")
		fmt.Println("  2. 停用订阅服务 (subscribe disable)")
		fmt.Println("  3. 查看 7 种格式订阅 URL + 二维码")
		fmt.Println("  4. 轮换 token (rotate-token，旧 URL 7 天后才失效)")
		fmt.Println("  0. 返回")
		fmt.Println()
		choice := utils.PromptInt("请选择", 0, 0, 4)
		switch choice {
		case 0:
			return
		case 1:
			runSubscribeEnableInteractive()
		case 2:
			runSubprocess("subscribe", "disable")
		case 3:
			runSubprocess("subscribe", "url")
		case 4:
			runSubprocess("subscribe", "rotate-token")
		}
		waitForEnter()
	}
}

// runSubscribeEnableInteractive 包装 subscribe enable 流程。问 domain / port /
// email 后调子进程跑 (复用现有 cmd/proxy-manager/subscribe.go runSubscribeEnable)。
func runSubscribeEnableInteractive() {
	domain := utils.PromptInput("订阅域名 (如 sub.example.com)", "")
	if domain == "" {
		utils.PrintError("domain 必填")
		return
	}
	email := utils.PromptInput("ACME 注册邮箱 (可空)", "")
	port := utils.PromptInput("订阅监听端口 (空 = 随机 10000-65000)", "")

	args := []string{"subscribe", "enable", "--domain", domain}
	if email != "" {
		args = append(args, "--email", email)
	}
	if port != "" {
		if _, err := strconv.Atoi(port); err == nil {
			args = append(args, "--port", port)
		}
	}
	runSubprocess(args...)
}

// runSubprocess 调当前 proxy-manager binary 的某个子命令；stdout/stderr 直通。
// 比直接调内部函数省心：复用已有 CLI 流程的所有 prompt + 错误处理。
func runSubprocess(args ...string) {
	bin, _ := os.Executable()
	cmd := exec.Command(bin, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		utils.PrintError("子命令失败: %v", err)
	}
}

// doKernelUpgradeAll 是菜单 #15：一键升级所有已装内核 (xray / sing-box)。
// 等价于 CLI 的 `proxy-manager kernel upgrade --all`，但 TUI 用户不用记命令。
func doKernelUpgradeAll() {
	kernels := install.ListKernels()
	if len(kernels) == 0 {
		utils.PrintWarn("尚未安装任何协议，没有内核要升级。")
		return
	}
	fmt.Println()
	fmt.Printf("%s=== 一键升级所有内核 ===%s\n", utils.ColorCyan, utils.ColorReset)
	for _, k := range kernels {
		cur := k.CurrentVersion()
		latest := k.LatestVersion()
		fmt.Printf("  %s: %s → %s\n", k.Name, dashIfEmpty(cur), dashIfEmpty(latest))
	}
	fmt.Println()
	if !utils.PromptConfirm("确认全部升级？") {
		fmt.Println("已取消")
		return
	}
	var firstErr error
	for _, k := range kernels {
		fmt.Printf("\n%s━━━━━━ %s ━━━━━━%s\n", utils.ColorCyan, k.Name, utils.ColorReset)
		if err := k.Upgrade(); err != nil {
			utils.PrintError("%s: %v", k.Name, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		utils.PrintSuccess("%s 升级完成", k.Name)
	}
	if firstErr == nil {
		utils.PrintSuccess("\n全部内核升级完成。验证: proxy-manager doctor")
	}
}

func dashIfEmpty(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

// 占位 — 让 store 这个 import 不被 lint 报 unused (subscribe.Urls 在
// runSubscribeEnableInteractive 等处间接引用)。
var _ = store.NodeType("")
