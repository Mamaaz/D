package main

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/Mamaaz/proxy-manager/internal/ui"
)

const version = "4.0.0"

func main() {
	// 处理命令行参数
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--help", "-h", "help":
			showHelp()
			return
		case "--version", "-v":
			fmt.Printf("Proxy Manager v%s\n", version)
			return
		case "update":
			doUpdate()
			return
		case "--action":
			// 执行指定操作 (由 TUI 调用)
			if len(os.Args) > 2 {
				ui.ExecuteAction(os.Args[2])
			}
			return
		case "--simple", "-s":
			// 简易菜单模式
			checkRoot()
			ui.RunSimpleMenu()
			return
		}
	}

	// 检查 root 权限
	checkRoot()

	// 默认使用简易菜单模式 (更兼容)
	// 如果要使用 TUI 模式，需要传入 --tui 参数
	for _, arg := range os.Args[1:] {
		if arg == "--tui" {
			if err := ui.Run(); err != nil {
				fmt.Printf("运行错误: %v\n", err)
				os.Exit(1)
			}
			return
		}
	}

	// 默认: 简易菜单模式
	ui.RunSimpleMenu()
}

func checkRoot() {
	if os.Geteuid() != 0 {
		fmt.Println("请使用 root 用户运行此脚本")
		os.Exit(1)
	}
}

func showHelp() {
	fmt.Printf(`Proxy Manager v%s

多协议代理服务器一键管理工具

用法:
  proxy-manager              运行交互式管理界面 (简易模式)
  proxy-manager --tui        运行 TUI 界面 (需要终端支持)
  proxy-manager --simple     运行简易菜单模式
  proxy-manager --help       显示此帮助信息
  proxy-manager --version    显示版本信息
  proxy-manager update       更新到最新版

支持的协议:
  - Snell + Shadow-TLS
  - SS-2022 + Shadow-TLS
  - VLESS Reality
  - Hysteria2
  - AnyTLS

安装命令:
  bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh)

`, version)
}

func doUpdate() {
	fmt.Println("正在检查更新...")
	fmt.Println()

	// 构建安装脚本 URL
	installURL := "https://raw.githubusercontent.com/Mamaaz/D/main/P/proxy_manager_go/scripts/install.sh"

	// 使用 bash 执行更新脚本
	cmd := exec.Command("bash", "-c", fmt.Sprintf("curl -sL '%s' | bash -s update", installURL))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	if err := cmd.Run(); err != nil {
		fmt.Printf("更新失败: %v\n", err)
		os.Exit(1)
	}
}
