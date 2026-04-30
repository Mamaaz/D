package format

import (
	"fmt"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func anytlsToSurge(n *store.Node) string {
	p := n.Params
	domain := str(p, "domain")
	if domain == "" {
		domain = n.Server
	}
	return fmt.Sprintf("%s = anytls, %s, %d, password=%s, sni=%s",
		n.Name, domain, n.Port, str(p, "password"), domain)
}

func anytlsToClash(n *store.Node) map[string]any {
	p := n.Params
	domain := str(p, "domain")
	if domain == "" {
		domain = n.Server
	}
	return map[string]any{
		"name":     n.Name,
		"type":     "anytls",
		"server":   domain,
		"port":     n.Port,
		"password": str(p, "password"),
		"sni":      domain,
	}
}

func anytlsToSingbox(n *store.Node) map[string]any {
	p := n.Params
	domain := str(p, "domain")
	if domain == "" {
		domain = n.Server
	}
	out := map[string]any{
		"type":        "anytls",
		"tag":         n.ID,
		"server":      domain,
		"server_port": n.Port,
		"password":    str(p, "password"),
		"tls": map[string]any{
			"enabled":     true,
			"server_name": domain,
		},
	}
	if name := str(p, "padding_name"); name != "" {
		out["padding_scheme"] = name
	}
	return out
}
