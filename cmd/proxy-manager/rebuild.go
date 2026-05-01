package main

import (
	"fmt"
	"os"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/subscribe"
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

	// subscribe 服务在 internal/subscribe 包，单独触发避免反向 import。
	// 升级到 v4.0.6+ 时这一步把旧的 User=root unit 降到 User=proxy-manager。
	if subErr := subscribe.Rebuild(); subErr != nil {
		utils.PrintWarn("[subscribe] 重建失败: %v", subErr)
		if err == nil {
			err = subErr
		}
	} else if hasSubscribeEnabled() {
		rebuilt = append(rebuilt, "Subscribe service")
	}

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

// hasSubscribeEnabled 探一下 store 里的 subscribe block 是不是启用过——
// Rebuild 内部会 no-op 如果没启用，但我们要在 rebuilt 列表里如实显示。
func hasSubscribeEnabled() bool {
	out, err := os.ReadFile("/etc/proxy-manager/nodes.json")
	if err != nil {
		return false
	}
	// 不引入 store 包做完整解析，只检查文件里有没有 subscribe.domain 非空。
	return len(out) > 0 && (containsSubstr(out, `"domain":"`) || containsSubstr(out, `"domain": "`))
}

func containsSubstr(haystack []byte, needle string) bool {
	if len(needle) == 0 || len(needle) > len(haystack) {
		return false
	}
	nb := []byte(needle)
	for i := 0; i+len(nb) <= len(haystack); i++ {
		match := true
		for j := 0; j < len(nb); j++ {
			if haystack[i+j] != nb[j] {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
