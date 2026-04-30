package format

import (
	"fmt"

	"github.com/Mamaaz/proxy-manager/internal/store"
)

func snellToSurge(n *store.Node) string {
	p := n.Params
	return fmt.Sprintf(
		"%s = snell, %s, %d, psk=%s, version=%s, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=%d",
		n.Name, n.Server, n.Port,
		str(p, "snell_psk"),
		defaultStr(str(p, "snell_version"), "4"),
		str(p, "shadow_tls_password"),
		str(p, "shadow_tls_sni"),
		defaultInt(num(p, "shadow_tls_version"), 3),
	)
}

func snellToClash(n *store.Node) map[string]any {
	p := n.Params
	return map[string]any{
		"name":     n.Name,
		"type":     "snell",
		"server":   n.Server,
		"port":     n.Port,
		"psk":      str(p, "snell_psk"),
		"version":  defaultInt(parseStrInt(str(p, "snell_version")), 4),
		"obfs-opts": map[string]any{
			"mode": "tls",
			"host": str(p, "shadow_tls_sni"),
		},
	}
}

func defaultStr(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

func defaultInt(n, fallback int) int {
	if n == 0 {
		return fallback
	}
	return n
}

func parseStrInt(s string) int {
	var n int
	fmt.Sscanf(s, "%d", &n)
	return n
}
