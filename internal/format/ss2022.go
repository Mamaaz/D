package format

import (
	"fmt"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func ss2022ToSurge(n *store.Node) string {
	p := n.Params
	return fmt.Sprintf(
		"%s = ss, %s, %d, encrypt-method=%s, password=%s, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=%d",
		n.Name, n.Server, n.Port,
		str(p, "method"),
		str(p, "password"),
		str(p, "shadow_tls_password"),
		str(p, "shadow_tls_sni"),
		defaultInt(num(p, "shadow_tls_version"), 3),
	)
}

func ss2022ToClash(n *store.Node) map[string]any {
	p := n.Params
	return map[string]any{
		"name":     n.Name,
		"type":     "ss",
		"server":   n.Server,
		"port":     n.Port,
		"cipher":   str(p, "method"),
		"password": str(p, "password"),
		"plugin":   "shadow-tls",
		"client-fingerprint": "chrome",
		"plugin-opts": map[string]any{
			"host":     str(p, "shadow_tls_sni"),
			"password": str(p, "shadow_tls_password"),
			"version":  defaultInt(num(p, "shadow_tls_version"), 3),
		},
	}
}

// ss2022ToSingbox renders the ShadowTLS+SS2022 stack as two chained
// outbounds: outer shadowtls + inner shadowsocks linked via detour.
func ss2022ToSingbox(n *store.Node) []map[string]any {
	p := n.Params
	innerTag := n.ID + "-ss"
	inner := map[string]any{
		"type":        "shadowsocks",
		"tag":         innerTag,
		"server":      "127.0.0.1",
		"server_port": 0,
		"method":      str(p, "method"),
		"password":    str(p, "password"),
	}
	outer := map[string]any{
		"type":        "shadowtls",
		"tag":         n.ID,
		"server":      n.Server,
		"server_port": n.Port,
		"version":     defaultInt(num(p, "shadow_tls_version"), 3),
		"password":    str(p, "shadow_tls_password"),
		"tls": map[string]any{
			"enabled":     true,
			"server_name": str(p, "shadow_tls_sni"),
			"utls": map[string]any{
				"enabled":     true,
				"fingerprint": "chrome",
			},
		},
		"detour": innerTag,
	}
	return []map[string]any{outer, inner}
}
