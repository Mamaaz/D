package format

import (
	"fmt"
	"net/url"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

// VlessRealityShareURL 生成单节点 vless:// 分享 URL，标准格式 (xray/v2ray
// 客户端通用)。可以 QR 编码后扫码导入到 NekoBox / V2Box / sing-box-windows
// 等任意 Reality 客户端，不依赖订阅服务。
//
// 格式参考: https://github.com/XTLS/Xray-core/discussions/716
//
//	vless://<uuid>@<host>:<port>?
//	  encryption=none&flow=xtls-rprx-vision&
//	  type=tcp&security=reality&
//	  pbk=<publickey>&sni=<servername>&sid=<shortid>&
//	  fp=chrome&spx=%2F
//	  #<urlencoded-name>
func VlessRealityShareURL(n *store.Node) string {
	p := n.Params
	q := url.Values{}
	q.Set("encryption", "none")
	if flow := str(p, "flow"); flow != "" {
		q.Set("flow", flow)
	}
	q.Set("type", "tcp")
	q.Set("security", "reality")
	q.Set("pbk", str(p, "public_key"))
	q.Set("sni", str(p, "server_name"))
	q.Set("sid", str(p, "short_id"))
	q.Set("fp", "chrome")
	q.Set("spx", "/")
	return fmt.Sprintf("vless://%s@%s:%d?%s#%s",
		str(p, "uuid"),
		n.Server, n.Port,
		q.Encode(),
		url.QueryEscape(n.Name),
	)
}

// vlessRealityToSurge emits Surge's documented vless-reality syntax. Surge's
// official VLESS Reality support is recent and field names may shift; if your
// Surge build rejects this line, route the node through the Mac bridge script
// (xray output) instead.
func vlessRealityToSurge(n *store.Node) string {
	p := n.Params
	line := fmt.Sprintf(
		"%s = vless, %s, %d, username=%s, sni=%s, public-key=%s, short-id=%s, tfo=true, udp-relay=true",
		n.Name, n.Server, n.Port,
		str(p, "uuid"),
		str(p, "server_name"),
		str(p, "public_key"),
		str(p, "short_id"),
	)
	if flow := str(p, "flow"); flow != "" {
		line += ", flow=" + flow
	}
	return line
}

func vlessRealityToClash(n *store.Node) map[string]any {
	p := n.Params
	out := map[string]any{
		"name":               n.Name,
		"type":               "vless",
		"server":             n.Server,
		"port":               n.Port,
		"uuid":               str(p, "uuid"),
		"network":            "tcp",
		"tls":                true,
		"udp":                true,
		"servername":         str(p, "server_name"),
		"client-fingerprint": "chrome",
		"reality-opts": map[string]any{
			"public-key": str(p, "public_key"),
			"short-id":   str(p, "short_id"),
		},
	}
	if flow := str(p, "flow"); flow != "" {
		out["flow"] = flow
	}
	return out
}

func vlessRealityToSingbox(n *store.Node) map[string]any {
	p := n.Params
	out := map[string]any{
		"type":        "vless",
		"tag":         n.ID,
		"server":      n.Server,
		"server_port": n.Port,
		"uuid":        str(p, "uuid"),
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
	if flow := str(p, "flow"); flow != "" {
		out["flow"] = flow
	}
	return out
}

// vlessRealityToXray is the canonical bridge target. The Mac script reads
// these outbounds and writes them into a local xray config that exposes a
// SOCKS5 listener for Surge to consume.
func vlessRealityToXray(n *store.Node) map[string]any {
	p := n.Params
	user := map[string]any{
		"id":         str(p, "uuid"),
		"encryption": "none",
	}
	if flow := str(p, "flow"); flow != "" {
		user["flow"] = flow
	}
	return map[string]any{
		"tag":      n.ID,
		"protocol": "vless",
		"settings": map[string]any{
			"vnext": []any{
				map[string]any{
					"address": n.Server,
					"port":    n.Port,
					"users":   []any{user},
				},
			},
		},
		"streamSettings": map[string]any{
			"network":  "tcp",
			"security": "reality",
			"realitySettings": map[string]any{
				"show":        false,
				"fingerprint": "chrome",
				"serverName":  str(p, "server_name"),
				"publicKey":   str(p, "public_key"),
				"shortId":     str(p, "short_id"),
				"spiderX":     "/",
			},
		},
	}
}
