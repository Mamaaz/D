package format

import (
	"fmt"
	"strings"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func hysteria2ToSurge(n *store.Node) string {
	p := n.Params
	domain := str(p, "domain")
	if domain == "" {
		domain = n.Server
	}
	var sb strings.Builder
	fmt.Fprintf(&sb, "%s = hysteria2, %s, %d, password=%s, sni=%s",
		n.Name, domain, n.Port, str(p, "password"), domain)
	if boolean(p, "enable_obfs") {
		fmt.Fprintf(&sb, ", obfs=salamander, obfs-password=%s", str(p, "obfs_password"))
	}
	return sb.String()
}

func hysteria2ToClash(n *store.Node) map[string]any {
	p := n.Params
	domain := str(p, "domain")
	if domain == "" {
		domain = n.Server
	}
	out := map[string]any{
		"name":     n.Name,
		"type":     "hysteria2",
		"server":   domain,
		"port":     n.Port,
		"password": str(p, "password"),
		"sni":      domain,
	}
	if boolean(p, "enable_obfs") {
		out["obfs"] = "salamander"
		out["obfs-password"] = str(p, "obfs_password")
	}
	return out
}

func hysteria2ToSingbox(n *store.Node) map[string]any {
	p := n.Params
	domain := str(p, "domain")
	if domain == "" {
		domain = n.Server
	}
	out := map[string]any{
		"type":        "hysteria2",
		"tag":         n.ID,
		"server":      domain,
		"server_port": n.Port,
		"password":    str(p, "password"),
		"tls": map[string]any{
			"enabled":     true,
			"server_name": domain,
		},
	}
	if boolean(p, "enable_obfs") {
		out["obfs"] = map[string]any{
			"type":     "salamander",
			"password": str(p, "obfs_password"),
		}
	}
	return out
}
