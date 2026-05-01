package ui

import (
	"fmt"

	"github.com/Mamaaz/proxy-manager/internal/store"
	"github.com/Mamaaz/proxy-manager/internal/subscribe"
	"github.com/Mamaaz/proxy-manager/internal/utils"
)

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
	for _, k := range []string{"surge", "clash", "singbox", "xray", "json"} {
		if v, ok := urls[k]; ok {
			fmt.Printf("  %-8s %s\n", k+":", v)
		}
	}
	fmt.Println()
	fmt.Printf("%sXSurge (Mac 状态栏 app)%s 直接添加 json URL 即可。\n",
		utils.ColorGreen, utils.ColorReset)
}
