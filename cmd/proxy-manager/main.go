package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"time"

	"github.com/Mamaaz/proxy-manager/internal/ui"
	"github.com/Mamaaz/proxy-manager/internal/version"
)

// 注：版本号实际定义在 internal/version 包；这里 alias 一下方便就近用。
// CI ldflags 注入 internal/version.Version (见 .github/workflows/release.yml)。
// 本地未注入时显示 "dev"。

func main() {
	// 处理命令行参数
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "--help", "-h", "help":
			showHelp()
			return
		case "--version", "-v":
			fmt.Printf("Proxy Manager v%s\n", version.Version)
			return
		case "update":
			doUpdate()
			return
		case "export":
			runExport(os.Args[2:])
			return
		case "subscribe":
			runSubscribe(os.Args[2:])
			return
		case "doctor":
			runDoctor(os.Args[2:])
			return
		case "sni-test":
			runSNITest(os.Args[2:])
			return
		case "sni-rank":
			runSNIRank(os.Args[2:])
			return
		case "edit":
			runEdit(os.Args[2:])
			return
		case "kernel":
			runKernel(os.Args[2:])
			return
		case "service-rebuild":
			checkRoot()
			runServiceRebuild(os.Args[2:])
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
  proxy-manager export --format=<json|surge|clash|mihomo|singbox|xray|qx>
                             导出已安装节点为指定格式 (输出到 stdout)
  proxy-manager subscribe <command>
                             订阅 HTTPS 服务: enable / disable / status / url / rotate-token
                             (详细: proxy-manager subscribe --help)
  proxy-manager doctor       一键诊断: 协议服务/证书/订阅服务状态
  proxy-manager sni-test <host>
                             从 VPS 视角验证候选 Reality SNI: TLS1.3/X25519/h2/证书
  proxy-manager sni-rank [--in scan.csv] [--top N] [host ...]
                             批量探测 + 自动打分排序 + 推荐最佳；接受
                             RealiTLScanner CSV 或 hostname list (stdin / args)
  proxy-manager edit         修改已安装协议的可变字段，无需 reinstall:
                             - reality: port/uuid/short-id/sni
  proxy-manager kernel       管理底层内核 (xray-core / sing-box)
                             list (default) | upgrade [name|--all]
  proxy-manager service-rebuild
                             重建所有已安装协议的 systemd 单元
                             (升级二进制后用，让 unit 文件改动生效)

支持的协议:
  - VLESS Reality
  - Hysteria2
  - AnyTLS
  - AnyTLS + Reality

安装命令:
  bash <(curl -sL https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh)

`, version.Version)
}

func doUpdate() {
	fmt.Println("正在检查更新...")
	fmt.Println()

	const installURL = "https://raw.githubusercontent.com/Mamaaz/D/main/scripts/install.sh"

	// 不能用 `curl ... | bash -s update`:install.sh `set -e` + 里面 `read -p`
	// 在管道模式下 stdin 已被脚本本体占用,read 直接拿到 EOF 返回 1,set -e
	// 让脚本在确认提示那行立即终止 → 用户看到 "exit status 1" 没解释。
	// 改成: 先把脚本下到 tmpfile,再 `bash tmpfile update`,os.Stdin 仍是终端,
	// 交互 read 能正常工作。
	scriptPath, err := downloadToTemp(installURL)
	if err != nil {
		fmt.Printf("下载更新脚本失败: %v\n", err)
		os.Exit(1)
	}
	defer os.Remove(scriptPath)

	cmd := exec.Command("bash", scriptPath, "update")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		fmt.Printf("更新失败: %v\n", err)
		os.Exit(1)
	}
}

func downloadToTemp(url string) (string, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	f, err := os.CreateTemp("", "proxy-manager-update-*.sh")
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		os.Remove(f.Name())
		return "", err
	}
	if err := f.Close(); err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return f.Name(), nil
}
