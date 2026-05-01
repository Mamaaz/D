package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/install"
	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

// runEdit 实现 `proxy-manager edit` 子命令。
//
// 修改已安装协议的可变字段（端口/密码/SNI 等）。当前 MVP 只支持
// VLESS Reality 的 port / uuid / short-id / sni 4 个字段——这些字段
// 改动是纯 config + restart，无证书牵扯。
//
// 用法：
//
//	proxy-manager edit                              # 全交互
//	proxy-manager edit reality                      # 选 Reality + 交互选字段
//	proxy-manager edit reality --field uuid --value <new-uuid>
//	                                               # 一次性 (适合脚本)
func runEdit(args []string) {
	field := flagValue(args, "--field")
	value := flagValue(args, "--value")

	protocol := ""
	for _, a := range args {
		if !strings.HasPrefix(a, "--") {
			protocol = a
			break
		}
	}

	// 1) 选协议
	if protocol == "" {
		s, err := store.LoadOrMigrate()
		if err != nil {
			fmt.Fprintf(os.Stderr, "读取节点失败: %v\n", err)
			os.Exit(1)
		}
		protocol = pickInstalledProtocol(s.Nodes)
		if protocol == "" {
			os.Exit(1)
		}
	}

	switch strings.ToLower(protocol) {
	case "reality", "vless-reality", "vless":
		runEditReality(field, value)
	default:
		fmt.Fprintf(os.Stderr, "暂未支持编辑该协议: %s\n", protocol)
		fmt.Fprintln(os.Stderr, "目前只支持: reality")
		fmt.Fprintln(os.Stderr, "Hysteria2 / AnyTLS 涉及 ACME 证书重签，复杂度更高；其他协议直接 install 重装。")
		os.Exit(2)
	}
}

func pickInstalledProtocol(nodes []store.Node) string {
	if len(nodes) == 0 {
		fmt.Fprintln(os.Stderr, "尚未安装任何协议")
		return ""
	}
	supported := map[store.NodeType]string{
		store.TypeVLESSReality: "VLESS Reality",
	}
	type opt struct {
		key  string
		desc string
	}
	var opts []opt
	for _, n := range nodes {
		if name, ok := supported[n.Type]; ok {
			opts = append(opts, opt{key: string(n.Type), desc: name + "  (port :" + fmt.Sprint(n.Port) + ")"})
		}
	}
	if len(opts) == 0 {
		fmt.Fprintln(os.Stderr, "已安装的协议都还没有 edit 支持 (Hysteria2/AnyTLS 涉及 ACME 重签暂未实现)")
		return ""
	}
	if len(opts) == 1 {
		fmt.Printf("选中: %s\n", opts[0].desc)
		return opts[0].key
	}
	fmt.Println("选择要编辑的协议:")
	for i, o := range opts {
		fmt.Printf("  %d. %s\n", i+1, o.desc)
	}
	idx := utils.PromptInt("请选择", 1, 1, len(opts))
	return opts[idx-1].key
}

func runEditReality(field, value string) {
	fields, err := install.CurrentRealityFields()
	if err != nil {
		fmt.Fprintf(os.Stderr, "读取 Reality 配置失败: %v\n", err)
		os.Exit(1)
	}

	// 交互模式：列出字段让用户选
	if field == "" {
		fmt.Println()
		fmt.Printf("%sVLESS Reality 当前可编辑字段:%s\n", utils.ColorCyan, utils.ColorReset)
		for i, f := range fields {
			fmt.Printf("  %d. %-15s = %s\n", i+1, f.DisplayName, f.CurrentValue)
			fmt.Printf("       %s%s%s\n", utils.ColorYellow, f.Description, utils.ColorReset)
		}
		fmt.Println("  0. 取消")
		fmt.Println()
		idx := utils.PromptInt("选择要修改的字段", 0, 0, len(fields))
		if idx == 0 {
			fmt.Println("已取消")
			return
		}
		picked := fields[idx-1]
		field = picked.Name

		fmt.Println()
		fmt.Printf("当前 %s: %s%s%s\n", picked.DisplayName, utils.ColorCyan, picked.CurrentValue, utils.ColorReset)
		newVal := utils.PromptInput(fmt.Sprintf("输入新 %s (回车取消)", picked.DisplayName), "")
		if newVal == "" {
			fmt.Println("已取消")
			return
		}
		value = newVal

		fmt.Println()
		if !utils.PromptConfirm(fmt.Sprintf("确认把 %s 改为 %s 并重启服务?", picked.DisplayName, value)) {
			fmt.Println("已取消")
			return
		}
	}

	// 应用
	if err := install.EditReality(field, value); err != nil {
		fmt.Fprintf(os.Stderr, "%s修改失败:%s %v\n", utils.ColorRed, utils.ColorReset, err)
		os.Exit(1)
	}
	fmt.Println()
	fmt.Printf("%s✓ %s 已更新%s\n", utils.ColorGreen, field, utils.ColorReset)
	fmt.Println()
	fmt.Println("接下来：")
	fmt.Println("  - 客户端要拿新配置: proxy-manager export --format=surge (或其他)")
	fmt.Println("  - 如已启用订阅服务: 客户端订阅会自动同步")
	fmt.Println("  - 验证: proxy-manager doctor")
}
