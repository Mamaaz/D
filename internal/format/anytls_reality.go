// AnyTLS + Reality 格式生成 (v4.0.25)
//
// 服务端是 sing-box anytls inbound + tls.reality 块。客户端兼容情况：
//   - sing-box / mihomo / NekoBox: ✓
//   - QuantumultX 测试版: ✓ (字段 over-tls=true, tls-host=, reality-base64-pubkey=)
//   - Surge / xray-only 客户端: ✗
//
// Surge / xray 输出返回错误，让上层 export / 订阅服务跳过这条节点。
package format

import (
	"fmt"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func anytlsRealityToSurge(_ *store.Node) string {
	// Surge 至今不支持 AnyTLS+Reality；返回注释行不出错。
	return "# AnyTLS+Reality not supported by Surge"
}

func anytlsRealityToClash(n *store.Node) map[string]any {
	p := n.Params
	return map[string]any{
		"name":               n.Name,
		"type":               "anytls",
		"server":             n.Server,
		"port":               n.Port,
		"password":           str(p, "password"),
		"udp":                true,
		"tls":                true,
		"servername":         str(p, "server_name"),
		"client-fingerprint": "chrome",
		"reality-opts": map[string]any{
			"public-key": str(p, "public_key"),
			"short-id":   str(p, "short_id"),
		},
	}
}

func anytlsRealityToSingbox(n *store.Node) map[string]any {
	p := n.Params
	return map[string]any{
		"type":        "anytls",
		"tag":         n.ID,
		"server":      n.Server,
		"server_port": n.Port,
		"password":    str(p, "password"),
		"tls": map[string]any{
			"enabled":     true,
			"server_name": str(p, "server_name"),
			"utls": map[string]any{
				"enabled":     true,
				"fingerprint": "chrome",
			},
			"reality": map[string]any{
				"enabled":    true,
				"public_key": str(p, "public_key"),
				"short_id":   str(p, "short_id"),
			},
		},
	}
}

// QX 格式参考用户提供：
//
//	anytls=host:port, password=, over-tls=true, tls-host=apple.com,
//	reality-base64-pubkey=..., reality-hex-shortid=..., udp-relay=true, tag=
func anytlsRealityToQX(n *store.Node) string {
	p := n.Params
	parts := []string{
		fmt.Sprintf("anytls=%s:%d", n.Server, n.Port),
		"password=" + str(p, "password"),
		"over-tls=true",
		"tls-host=" + str(p, "server_name"),
		"reality-base64-pubkey=" + str(p, "public_key"),
		"reality-hex-shortid=" + str(p, "short_id"),
		"udp-relay=true",
		"tag=" + n.Name,
	}
	return strings.Join(parts, ", ")
}
