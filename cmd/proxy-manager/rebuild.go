package main

import (
	"fmt"
	"os"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runServiceRebuild implements `proxy-manager service-rebuild`.
//
// Use case: a binary upgrade changes systemd unit semantics (e.g.,
// User=root → User=sing-box for the Reality service). Older deployments
// keep the old unit file because install/uninstall is the only thing that
// rewrites them. Calling this after upgrade re-renders every unit and
// restarts the affected services.
//
// Safe to run on a fresh / partially-installed VPS — protocols without a
// .txt config file are silently skipped.
func runServiceRebuild(args []string) {
	_ = args
	utils.PrintInfo("正在重建已安装协议的 systemd 单元...")

	rebuilt, err := install.RebuildAllServices()
	if len(rebuilt) > 0 {
		fmt.Println()
		fmt.Println("已重建并重启的服务:")
		for _, name := range rebuilt {
			fmt.Printf("  ✓ %s\n", name)
		}
		fmt.Println()
	} else {
		utils.PrintInfo("没有需要重建的协议（尚未安装任何协议或全部重建失败）")
	}

	if err != nil {
		utils.PrintError("部分重建失败: %v", err)
		os.Exit(1)
	}
	utils.PrintSuccess("完成")
}
