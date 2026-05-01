package ui

import (
	"fmt"
	"os"

	"github.com/Mamaaz/proxy-manager/internal/format"
	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/subscribe"
	"github.com/Mamaaz/proxy-manager/internal/utils"
	"github.com/mdp/qrterminal/v3"
)

// printNodeShareURL 给一个新装的节点打分享 URL + QR。客户端扫码即导入
// 单个节点，不依赖订阅服务（测试用、或 subscribe 还没启用时）。
//
// 当前只支持 VLESS Reality (`vless://...`)。其他协议的标准 share URL 格式
// 各异 (Hy2 是 `hy2://`、AnyTLS 没标准) — 待真有需求再加。
func printNodeShareURL(nodeType store.NodeType) {
	s, err := store.LoadOrMigrate()
	if err != nil {
		return
	}
	var node *store.Node
	for i := range s.Nodes {
		if s.Nodes[i].Type == nodeType {
			node = &s.Nodes[i]
			break
		}
	}
	if node == nil {
		return
	}
	if nodeType != store.TypeVLESSReality {
		return // 其他协议暂未实现 share URL
	}
	share := format.VlessRealityShareURL(node)
	fmt.Println()
	fmt.Printf("%s单节点分享链接%s（扫码导入到任意 Reality 客户端，不需要订阅服务）:\n",
		utils.ColorCyan, utils.ColorReset)
	fmt.Printf("  %s%s%s\n", utils.ColorGreen, share, utils.ColorReset)
	fmt.Println()
	fmt.Println("  扫码:")
	printQR(share)
}

// printSubscribeURLs 在协议安装成功后打印订阅 URL（如果订阅服务已启用）。
// 让用户安装完直接看到给 XSurge / Surge / Clash / sing-box / xray 用的 5 种
// 订阅 URL，免去他们额外跑 `proxy-manager subscribe url` 才知道。
//
// 订阅服务未启用时给出 enable 提示，引导用户开通。
func printSubscribeURLs() {
	s, err := store.LoadOrMigrate()
	if err != nil {
		return
	}
	urls := subscribe.Urls(s)
	if urls == nil {
		fmt.Println()
		fmt.Printf("%s提示:%s 当前未启用订阅服务，客户端只能手动复制上面的 Surge 行使用。\n",
			utils.ColorYellow, utils.ColorReset)
		fmt.Println("    启用订阅服务可让客户端 (XSurge / Surge / Clash) 自动同步配置:")
		fmt.Printf("    %sproxy-manager subscribe enable%s\n",
			utils.ColorCyan, utils.ColorReset)
		fmt.Println("    或在交互菜单选 subscribe 相关选项。")
		return
	}
	fmt.Println()
	fmt.Printf("%s订阅 URL%s（客户端添加这些 URL 即可自动同步配置）:\n",
		utils.ColorCyan, utils.ColorReset)
	for _, k := range []string{"surge", "clash", "mihomo", "singbox", "xray", "qx", "json"} {
		if v, ok := urls[k]; ok {
			fmt.Printf("  %-8s %s\n", k+":", v)
		}
	}
	fmt.Println()
	fmt.Printf("%sXSurge (Mac 状态栏 app)%s 直接复制上面 json URL 添加订阅即可。\n",
		utils.ColorGreen, utils.ColorReset)
	// 不再打 json 订阅 URL 的 QR — XSurge 用复制粘贴 URL 字符串，QR 没用；
	// 上面 printNodeShareURL 给的 vless:// 单节点 share 才是手机扫码场景。
}

// printQR 跟 cmd/proxy-manager/subscribe.go 同款；ui 包独立 import qrterminal
// 避免循环依赖，代价是几行代码重复——比让 cmd 反过来导出 ui helper 干净。
func printQR(text string) {
	cfg := qrterminal.Config{
		Level:          qrterminal.M,
		Writer:         os.Stdout,
		HalfBlocks:     true,
		BlackChar:      qrterminal.BLACK_BLACK,
		WhiteChar:      qrterminal.WHITE_WHITE,
		BlackWhiteChar: qrterminal.BLACK_WHITE,
		WhiteBlackChar: qrterminal.WHITE_BLACK,
		QuietZone:      1,
	}
	qrterminal.GenerateWithConfig(text, cfg)
}
